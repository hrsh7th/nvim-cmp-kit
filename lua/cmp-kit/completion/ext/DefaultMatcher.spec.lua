local DefaultMatcher = require('cmp-kit.completion.ext.DefaultMatcher')

describe('cmp-kit.completion', function()
  describe('DefaultMatcher', function()
    describe('.matcher', function()
      it('should return correct scores', function()
        assert.is_truthy(DefaultMatcher.matcher('', 'a') > 0)
        assert.is_truthy(DefaultMatcher.matcher('a', 'a') > 0)
        assert.is_truthy(DefaultMatcher.matcher('ab', 'a') == 0)
        assert.is_truthy(DefaultMatcher.matcher('ab', 'ab') > DefaultMatcher.matcher('ab', 'a_b'))
        assert.is_truthy(DefaultMatcher.matcher('ab', 'a_b_c') > DefaultMatcher.matcher('ac', 'a_b_c'))

        assert.is_truthy(DefaultMatcher.matcher('bora', 'border-radius') > 0)
        assert.is_truthy(DefaultMatcher.matcher('woroff', 'word_offset') > 0)
        assert.is_truthy(DefaultMatcher.matcher('call', 'call') > DefaultMatcher.matcher('call', 'condition_all'))
        assert.is_truthy(DefaultMatcher.matcher('Buffer', 'Buffer') > DefaultMatcher.matcher('Buffer', 'buffer'))
        assert.is_truthy(DefaultMatcher.matcher('candlesingle', 'candle#accept#single') > 0)

        assert.is_truthy(DefaultMatcher.matcher('vo', 'void#') > 0)
        assert.is_truthy(DefaultMatcher.matcher('var_', 'var_dump') > 0)
        assert.is_truthy(DefaultMatcher.matcher('conso', 'console') >
        DefaultMatcher.matcher('conso', 'ConstantSourceNode'))
        assert.is_truthy(DefaultMatcher.matcher('usela', 'useLayoutEffect') >
        DefaultMatcher.matcher('usela', 'useDataLayer'))
        assert.is_truthy(DefaultMatcher.matcher('my_', 'my_awesome_variable') >
        DefaultMatcher.matcher('my_', 'completion_matching_strategy_list'))
        assert.is_truthy(DefaultMatcher.matcher('2', '[[2021') > 0)

        assert.is_truthy(DefaultMatcher.matcher(',', 'pri,') > 0)
        assert.is_truthy(DefaultMatcher.matcher('/', '/**') > 0)
      end)
    end)
  end)
end)
