describe("strudel.visual setup", function()
  local visual

  before_each(function()
    package.loaded["strudel.visual"] = nil
    visual = require("strudel.visual")
  end)

  it("defaults enabled to true", function()
    visual.setup({})
    assert.is_true(visual.enabled)
  end)

  it("respects enabled = false", function()
    visual.setup({ enabled = false })
    assert.is_false(visual.enabled)
  end)

  it("stores color overrides", function()
    visual.setup({ colors = { bd = "#ff0000" } })
    assert.are.equal("#ff0000", visual.color_overrides.bd)
  end)

  it("creates a namespace", function()
    visual.setup({})
    assert.is_number(visual.ns_id)
  end)

  it("initializes last_eval with nil bufnr", function()
    visual.setup({})
    assert.is_nil(visual.last_eval.bufnr)
    assert.are.equal(0, visual.last_eval.offset)
  end)

  it("tolerates being called with no args", function()
    visual.setup()
    assert.is_true(visual.enabled)
  end)
end)
