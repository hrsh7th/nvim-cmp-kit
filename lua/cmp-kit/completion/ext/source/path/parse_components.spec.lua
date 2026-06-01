local parse_components = require "cmp-kit.completion.ext.source.path.parse_components"
describe('cmp-kit.completion.ext.source.path.parse_components', function()

  it('works', function()
    assert.are_same({ '' }, parse_components('#'))
    assert.are_same({ '', '' }, parse_components('/'))
    assert.are_same({ '', 'Users' }, parse_components('/Users'))
    assert.are_same({ '~', 'Users' }, parse_components('~/Users'))
  end)

end)

