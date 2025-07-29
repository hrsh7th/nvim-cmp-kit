local PreviewText = require('cmp-kit.completion.PreviewText')

describe('cmp-kit.completion', function()
  describe('PreviewText', function()
    describe('.create', function()
      it('should return preview text', function()
        assert.are.equal(
          '#[test]',
          PreviewText.create({
            insert_text = '#[test]',
            before_text = '',
            after_text = '',
          })
        )
        assert.are.equal(
          '#[[test]]',
          PreviewText.create({
            insert_text = '#[[test]]',
            before_text = '',
            after_text = '',
          })
        )
        assert.are.equal(
          'insert',
          PreviewText.create({
            insert_text = 'insert()',
            before_text = '',
            after_text = '',
          })
        )
        assert.are.equal(
          'insert_text',
          PreviewText.create({
            insert_text = 'insert_text',
            before_text = '',
            after_text = '',
          })
        )
        assert.are.equal(
          '(insert)',
          PreviewText.create({
            insert_text = '(insert))',
            before_text = '',
            after_text = '',
          })
        )
        assert.are.equal(
          '"true"',
          PreviewText.create({
            insert_text = '"true"',
            before_text = '',
            after_text = '',
          })
        )
        assert.are.equal(
          '16',
          PreviewText.create({
            insert_text = '16',
            before_text = '',
            after_text = '',
          })
        )
        assert.are.equal(
          '"repository',
          PreviewText.create({
            insert_text = '"repository"',
            before_text = '',
            after_text = '"',
          })
        )
        assert.are.equal(
          'import ',
          PreviewText.create({
            insert_text = 'import { URL } from "url";',
            before_text = 'import URL',
            after_text = '',
          })
        )
        assert.are.equal(
          'signature',
          PreviewText.create({
            insert_text = 'signature',
            before_text = '',
            after_text = 'exit',
          })
        )
        assert.are.equal(
          'insert',
          PreviewText.create({
            insert_text = 'insert(list, pos, value)',
            before_text = 'insert',
            after_text = '',
          })
        )
        assert.are.equal(
          'font-size:',
          PreviewText.create({
            insert_text = 'font-size: ;',
            before_text = '',
            after_text = '',
          })
        )
      end)
    end)
  end)
end)
