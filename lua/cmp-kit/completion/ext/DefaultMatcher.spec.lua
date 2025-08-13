local DefaultMatcher = require('cmp-kit.completion.ext.DefaultMatcher')

describe('cmp-kit.completion.ext', function()
  describe('DefaultMatcher', function()
    describe('.match', function()
      it('should match', function()
        assert.is_true(DefaultMatcher.match('', 'a') > 0)
        assert.is_true(DefaultMatcher.match('a', 'a') > 0)
        assert.is_true(DefaultMatcher.match('ab', 'a') == 0)
        assert.is_true(DefaultMatcher.match('ab', 'a_b_c') > 0)

        assert.is_true(
          DefaultMatcher.match('a', 'a') > DefaultMatcher.match('a', 'A')
        )
      end)
    end)
  end)
end)
