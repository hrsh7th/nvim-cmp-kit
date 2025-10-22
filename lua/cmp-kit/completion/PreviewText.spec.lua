local PreviewText = require('cmp-kit.completion.PreviewText')

describe('cmp-kit.completion', function()
  describe('PreviewText', function()
    describe('.create', function()
      it('should return preview text', function()
        -- simple: num only.
        assert.are.equal(
          '16',
          PreviewText.create({
            insert_text = '16',
            before_text = '',
            after_text = '',
          })
        )
        -- simple: keyword only.
        assert.are.equal(
          'insert',
          PreviewText.create({
            insert_text = 'insert',
            before_text = '',
            after_text = '',
          })
        )
        -- pairs.
        assert.are.equal(
          '"true"',
          PreviewText.create({
            insert_text = '"true"',
            before_text = '',
            after_text = '',
          })
        )
        -- pairs stack.
        assert.are.equal(
          '(insert)',
          PreviewText.create({
            insert_text = '(insert))',
            before_text = '',
            after_text = '',
          })
        )
        -- after_text overlap: symbolic chars.
        assert.are.equal(
          '"repository',
          PreviewText.create({
            insert_text = '"repository"',
            before_text = '',
            after_text = '"',
          })
        )
        -- after_text overlap: symbolic chars only.
        assert.are.equal(
          '"',
          PreviewText.create({
            insert_text = '""',
            before_text = '',
            after_text = '"',
          })
        )
        -- after_text overlap: alphabetical chars.
        assert.are.equal(
          'signature',
          PreviewText.create({
            insert_text = 'signature',
            before_text = '',
            after_text = 'exit',
          })
        )
        -- don't consume pairs after is_alnum_consumed=true
        assert.are.equal(
          'insert',
          PreviewText.create({
            insert_text = 'insert(list, pos, value)',
            before_text = '',
            after_text = '',
          })
        )
      end)
    end)
  end)
end)
