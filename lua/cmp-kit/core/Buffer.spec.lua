local Buffer = require('cmp-kit.core.Buffer')

---@return string
local function get_script_dir()
  return vim.fs.dirname(vim.fs.joinpath(vim.uv.cwd(), vim.fs.normalize(debug.getinfo(2, "S").source:sub(2))))
end

describe('cmp-kit.core', function()
  describe('Buffer', function()
    local function setup()
      vim.cmd.bdelete({ bang = true })
      local fixture_path = vim.fn.fnamemodify(vim.fs.joinpath(get_script_dir(), '../spec/fixtures/buffer.txt'), ':p')
      vim.cmd.edit(fixture_path)
      vim.cmd('setlocal noswapfile')
      local bufnr = vim.api.nvim_get_current_buf()
      local buffer = Buffer.new(bufnr)
      vim.wait(16)
      vim.wait(1000, function() return not buffer:is_indexing([[\k\+]]) end, 1)
      assert.are.equal(false, buffer:is_indexing([[\k\+]]))
      return buffer
    end

    it('.get_words (init)', function()
      local buffer = setup()
      for i = 1, vim.api.nvim_buf_line_count(buffer:get_buf()) do
        assert.are.same({
          ('word_%s_1'):format(i),
          ('word_%s_2'):format(i),
          ('word_%s_3'):format(i),
          ('word_%s_4'):format(i),
          ('word_%s_5'):format(i),
        }, buffer:get_words([[\k\+]], i - 1))
      end
    end)

    it('.get_words (remove)', function()
      local buffer = setup()
      vim.api.nvim_buf_set_lines(buffer:get_buf(), 120, 121, false, {})
      vim.wait(16)
      vim.wait(1000, function() return not buffer:is_indexing([[\k\+]]) end, 1)
      assert.are.equal(false, buffer:is_indexing([[\k\+]]))

      for i = 1, vim.api.nvim_buf_line_count(buffer:get_buf()) do
        assert.are.same({
          ('word_%s_1'):format(i + (i > 120 and 1 or 0)),
          ('word_%s_2'):format(i + (i > 120 and 1 or 0)),
          ('word_%s_3'):format(i + (i > 120 and 1 or 0)),
          ('word_%s_4'):format(i + (i > 120 and 1 or 0)),
          ('word_%s_5'):format(i + (i > 120 and 1 or 0)),
        }, buffer:get_words([[\k\+]], i - 1))
      end
    end)

    it('.get_words (add)', function()
      local buffer = setup()
      vim.api.nvim_buf_set_lines(buffer:get_buf(), 120, 120, false, { 'add' })
      vim.wait(16)
      vim.wait(1000, function() return not buffer:is_indexing([[\k\+]]) end, 1)
      assert.are.equal(false, buffer:is_indexing([[\k\+]]))

      for i = 1, vim.api.nvim_buf_line_count(buffer:get_buf()) do
        if i == 121 then
          assert.are.same({ 'add' }, buffer:get_words([[\k\+]], i - 1))
        else
          assert.are.same({
            ('word_%s_1'):format(i + (i > 120 and -1 or 0)),
            ('word_%s_2'):format(i + (i > 120 and -1 or 0)),
            ('word_%s_3'):format(i + (i > 120 and -1 or 0)),
            ('word_%s_4'):format(i + (i > 120 and -1 or 0)),
            ('word_%s_5'):format(i + (i > 120 and -1 or 0)),
          }, buffer:get_words([[\k\+]], i - 1))
        end
      end
    end)

    it('.get_words (modify)', function()
      local buffer = setup()
      vim.api.nvim_buf_set_lines(buffer:get_buf(), 120, 121, false, { 'modify' })
      vim.wait(16)
      vim.wait(1000, function() return not buffer:is_indexing([[\k\+]]) end, 1)
      assert.are.equal(false, buffer:is_indexing([[\k\+]]))

      for i = 1, vim.api.nvim_buf_line_count(buffer:get_buf()) do
        if i == 121 then
          assert.are.same({ 'modify' }, buffer:get_words([[\k\+]], i - 1))
        else
          assert.are.same({
            ('word_%s_1'):format(i),
            ('word_%s_2'):format(i),
            ('word_%s_3'):format(i),
            ('word_%s_4'):format(i),
            ('word_%s_5'):format(i),
          }, buffer:get_words([[\k\+]], i - 1))
        end
      end
    end)
  end)
end)
