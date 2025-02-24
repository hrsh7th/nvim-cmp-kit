local DefaultMatcher = require('cmp-kit.core.DefaultMatcher')

describe('cmp-kit.core', function()
  describe('DefaultMatcher', function()
    describe('.matcher', function()
      it('should return corerct indexes', function()
        assert.same({ { start_index = 1, end_index = 3 } }, select(2, DefaultMatcher.matcher('aiu', 'aiueo')))
        assert.same({ { start_index = 1, end_index = 1 }, { start_index = 5, end_index = 5 } }, select(2, DefaultMatcher.matcher('ao', 'aiueo')))
      end)

      it('should return correct scores', function()
        assert.is_truthy(DefaultMatcher.matcher('', 'a') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('a', 'a') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('ab', 'a') == 0)
        assert.is_truthy(DefaultMatcher.matcher('ab', 'ab') > DefaultMatcher.matcher('ab', 'a_b'))
        assert.is_truthy(DefaultMatcher.matcher('ab', 'a_b_c') > DefaultMatcher.matcher('ac', 'a_b_c'))

        assert.is_truthy(DefaultMatcher.matcher('bora', 'border-radius') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('woroff', 'word_offset') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('call', 'call') > DefaultMatcher.matcher('call', 'condition_all'))
        assert.is_truthy(DefaultMatcher.matcher('Buffer', 'Buffer') > DefaultMatcher.matcher('Buffer', 'buffer'))
        assert.is_truthy(DefaultMatcher.matcher('luacon', 'lua_context') > DefaultMatcher.matcher('luacon', 'LuaContext'))
        assert.is_truthy(DefaultMatcher.matcher('fmodify', 'fnamemodify') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('candlesingle', 'candle#accept#single') >= 1)

        assert.is_truthy(DefaultMatcher.matcher('vi', 'void#') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('vo', 'void#') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('var_', 'var_dump') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('conso', 'console') > DefaultMatcher.matcher('conso', 'ConstantSourceNode'))
        assert.is_truthy(DefaultMatcher.matcher('usela', 'useLayoutEffect') > DefaultMatcher.matcher('usela', 'useDataLayer'))
        assert.is_truthy(DefaultMatcher.matcher('my_', 'my_awesome_variable') > DefaultMatcher.matcher('my_', 'completion_matching_strategy_list'))
        assert.is_truthy(DefaultMatcher.matcher('2', '[[2021') >= 1)

        assert.is_truthy(DefaultMatcher.matcher(',', 'pri,') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('/', '/**') >= 1)

        assert.is_truthy(DefaultMatcher.matcher('emg', 'error_msg') >= 1)
        assert.is_truthy(DefaultMatcher.matcher('sasr', 'saved_splitright') >= 1)

        assert.is_truthy(DefaultMatcher.matcher('fmt', 'FnMut') < DefaultMatcher.matcher('fmt', 'format!'))
      end)
    end)
  end)
end)
