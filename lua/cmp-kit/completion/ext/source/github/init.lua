local kit = require('cmp-kit.kit')
local Async = require('cmp-kit.kit.Async')
local System = require('cmp-kit.kit.System')

local gh_executable = vim.fn.executable('gh') == 1

local stat_format = table.concat({
  '# %s: #%s',
  '------------------------------------------------------------',
  'title: %s',
  'author: %s',
  '------------------------------------------------------------',
  '',
}, '\n')

---Find the root directory of the git repository.
---@type table|fun(): string|nil
local try_get_git_root = setmetatable({
  cache = {}
}, {
  __call = function(self)
    local candidates = { vim.fn.expand('%:p:h'), vim.fn.getcwd() }
    for _, candidate in ipairs(candidates) do
      if not self.cache[candidate] then
        self.cache[candidate] = {
          git_root = kit.findup(vim.fs.normalize(candidate), { '.git' })
        }
      end
      if self.cache[candidate].git_root then
        return self.cache[candidate].git_root
      end
    end
  end
})

---Run gh command.
---@param args string[]
---@param option { cwd: string }
---@return cmp-kit.kit.Async.AsyncTask
local function gh_command(args, option)
  return Async.new(function(resolve, reject)
    local stdout = {}
    local stderr = {}
    System.spawn(kit.concat({ 'gh' }, args), {
      cwd = option.cwd,
      on_stdout = function(data)
        if data then
          table.insert(stdout, data)
        end
      end,
      on_stderr = function(data)
        if data then
          table.insert(stderr, data)
        end
      end,
      on_exit = function(code)
        if code == 0 then
          resolve(table.concat(stdout, ''))
        else
          reject('gh command failed with code: ' .. table.concat(stderr, ''))
        end
      end,
    })
  end)
end

---Get repository information from the current directory.
---@return { owner: string, name: string } | nil
local function get_repo_info()
  local repo = vim.json.decode(gh_command({
    'repo',
    'view',
    '--json',
    'owner,name',
    '--jq',
    '{ owner: .owner.login, name: .name }'
  }, {
    cwd = assert(try_get_git_root())
  }):await())
  return repo and repo.owner and repo.name and { owner = repo.owner, name = repo.name } or nil
end

---Get issues and pull requests from the current repository.
---@async
---@return cmp-kit.kit.LSP.CompletionItem[]
local function get_prs_and_issues()
  local items = {}

  -- fetch prs.
  local prs = vim.json.decode(gh_command({
    'pr',
    'list',
    '--search',
    'is:pr is:open',
    '--json',
    'number,title,body,author'
  }, {
    cwd = assert(try_get_git_root())
  }):await())
  for _, pr in ipairs(prs) do
    local stat = stat_format:format('Pull Request', pr.number, pr.title, pr.author.login)
    table.insert(items, {
      label = ('#%s %s'):format(pr.number, pr.title),
      insertText = ('#%s'):format(pr.number),
      nvim_previewText = ('#%s'):format(pr.number),
      filterText = ('#%s %s %s'):format(pr.number, pr.title, pr.author.login),
      labelDetails = { description = 'Pull Request', },
      documentation = {
        kind = 'markdown',
        value = stat .. (pr.body ~= '' and pr.body or 'empty body'),
      },
      sortText = #items + 1
    })
  end

  -- fetch issues.
  local issues = vim.json.decode(gh_command({
    'issue',
    'list',
    '--search',
    'is:open',
    '--json',
    'number,title,body,author'
  }, {
    cwd = assert(try_get_git_root())
  }):await())
  for _, issue in ipairs(issues) do
    local stat = stat_format:format('Issue', issue.number, issue.title, issue.author.login)
    table.insert(items, {
      label = ('#%s %s'):format(issue.number, issue.title),
      insertText = ('#%s'):format(issue.number),
      nvim_previewText = ('#%s'):format(issue.number),
      filterText = ('#%s %s %s'):format(issue.number, issue.title, issue.author.login),
      labelDetails = { description = 'Issue', },
      documentation = {
        kind = 'markdown',
        value = stat .. (issue.body ~= '' and issue.body or 'empty body'),
      },
      sortText = #items + 1
    })
  end

  return items
end

---Get mentionable users from the current repository.
---@async
---@param owner string
---@param name string
---@param member_type 'collaborators' | 'contributors'
---@return cmp-kit.kit.LSP.CompletionItem[]
local function get_mentionable_users(owner, name, member_type)
  local items = {}

  local users = vim.json.decode(gh_command({
    'api',
    ('/repos/%s/%s/%s'):format(owner, name, member_type),
    '--paginate',
    '--jq',
    '[.[] | {login: .login, name: .name}]'
  }, {
    cwd = assert(try_get_git_root())
  }):await())

  for _, user in ipairs(users) do
    if user.login and user.name then
      table.insert(items, {
        label = ('@%s'):format(user.login),
        insertText = ('@%s'):format(user.login),
        nvim_previewText = ('@%s'):format(user.login),
        filterText = ('@%s %s'):format(user.login, user.name),
        sortText = #items + 1
      })
    end
  end

  return items
end

return setmetatable({
  checkhealth = function()
    Async.run(function()
      if not gh_executable then
        vim.notify('[NG] `gh` command is not executable', vim.log.levels.ERROR)
      else
        vim.notify('[OK] `gh` command is executable', vim.log.levels.INFO)
      end
      local auth_status = gh_command({ 'auth', 'status' }, {
        cwd = assert(try_get_git_root())
      }):await()
      vim.notify('[INFO] GitHub CLI authentication status: ' .. auth_status, vim.log.levels.INFO)
    end)
  end
}, {
  __call = function()
    ---@type cmp-kit.completion.CompletionSource
    return {
      name = 'github',
      get_configuration = function()
        return {
          trigger_characters = { '#', '@' },
          keyword_pattern = [=[\%(#\|@\).*]=],
        }
      end,
      capable = function()
        if not gh_executable then
          return false
        end

        if vim.api.nvim_get_option_value('filetype', { buf = 0 }) ~= 'gitcommit' then
          return false
        end

        return try_get_git_root() ~= nil
      end,
      complete = function(_, completion_context, callback)
        if not vim.regex([=[\%(#\|@\).*]=]):match_str(vim.api.nvim_get_current_line()) then
          return callback(nil, {})
        end

        Async.run(function()
          local items = {}
          if completion_context.triggerCharacter == '#' then
            for _, item in ipairs(get_prs_and_issues()) do
              table.insert(items, item)
            end
          elseif completion_context.triggerCharacter == '@' then
            local repo = get_repo_info()
            if repo and repo.owner and repo.name then
              local ok = false
              if not ok then
                ok = pcall(function()
                  for _, item in ipairs(get_mentionable_users(repo.owner, repo.name, 'collaborators')) do
                    table.insert(items, item)
                  end
                end)
              end
              if not ok then
                ok = pcall(function()
                  for _, item in ipairs(get_mentionable_users(repo.owner, repo.name, 'contributors')) do
                    table.insert(items, item)
                  end
                end)
              end
            end
          end
          callback(nil, items)
        end):dispatch(function(res)
          callback(nil, res)
        end, function()
          callback(nil, nil)
        end)
      end
    }
  end
})
