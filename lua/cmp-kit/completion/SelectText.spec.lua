local SelectText = require('cmp-kit.completion.SelectText')

describe('cmp-kit.completion', function()
  describe('SelectText', function()
    describe('.create', function()
      it('should return select text', function()
        assert.are.equal('#[test]', SelectText.create({
          insert_text = '#[test]',
          before_text = '',
          after_text = '',
        }))
        assert.are.equal('#[[test]]', SelectText.create({
          insert_text = '#[[test]]',
          before_text = '',
          after_text = ''
        }))
        assert.are.equal('insert', SelectText.create({
          insert_text = 'insert()',
          before_text = '',
          after_text = ''
        }))
        assert.are.equal('insert_text', SelectText.create({
          insert_text = 'insert_text',
          before_text = '',
          after_text = ''
        }))
        assert.are.equal('(insert)', SelectText.create({
          insert_text = '(insert))',
          before_text = '',
          after_text = ''
        }))
        assert.are.equal('"true"', SelectText.create({
          insert_text = '"true"',
          before_text = '',
          after_text = ''
        }))
        assert.are.equal('16', SelectText.create({
          insert_text = '16',
          before_text = '',
          after_text = ''
        }))
        assert.are.equal('"repository', SelectText.create({
          insert_text = '"repository"',
          before_text = '',
          after_text = '"'
        }))
        assert.are.equal('import ', SelectText.create({
          insert_text = 'import { URL } from "url";',
          before_text = 'import URL',
          after_text = ''
        }))
        assert.are.equal('signature', SelectText.create({
          insert_text = 'signature',
          before_text = '',
          after_text = 'exit'
        }))
        assert.are.equal('insert', SelectText.create({
          insert_text = 'insert(${1:list}, ${2:pos}, ${3:value})',
          before_text = 'insert',
          after_text = ''
        }))
      end)
    end)
  end)
end)
