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

describe("strudel.visual color_for", function()
  local visual

  before_each(function()
    package.loaded["strudel.visual"] = nil
    visual = require("strudel.visual")
    visual.setup({})
  end)

  it("returns the same hl_group for the same sound", function()
    local a = visual.color_for("bd")
    local b = visual.color_for("bd")
    assert.are.equal(a, b)
  end)

  it("returns different hl_groups for different sounds", function()
    assert.are_not.equal(visual.color_for("bd"), visual.color_for("sd"))
  end)

  it("registers a highlight group with a bg color", function()
    local hl_group = visual.color_for("bd")
    local hl = vim.api.nvim_get_hl(0, { name = hl_group })
    assert.is_number(hl.bg)
  end)

  it("uses override color when valid", function()
    visual.setup({ colors = { bd = "#ff0000" } })
    local hl_group = visual.color_for("bd")
    local hl = vim.api.nvim_get_hl(0, { name = hl_group })
    -- 0xff0000 = 16711680
    assert.are.equal(16711680, hl.bg)
  end)

  it("falls back to hash when override is invalid", function()
    visual.setup({ colors = { bd = "not-a-color" } })
    local hl_group = visual.color_for("bd")
    local hl = vim.api.nvim_get_hl(0, { name = hl_group })
    assert.is_number(hl.bg)
    assert.are_not.equal(0, hl.bg)
  end)

  it("sanitizes sound names with non-word chars for hl_group", function()
    local hl_group = visual.color_for("note:c3")
    -- Must be a valid hl_group identifier (word chars + underscore only)
    assert.is_truthy(hl_group:match("^[%w_]+$"))
  end)
end)
