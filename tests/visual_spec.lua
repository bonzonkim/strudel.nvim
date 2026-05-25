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

describe("strudel.visual byte_to_pos", function()
  local visual
  local bufnr

  before_each(function()
    package.loaded["strudel.visual"] = nil
    visual = require("strudel.visual")
    visual.setup({})
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("returns (0,0) for byte offset 0", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abc", "def" })
    local row, col = visual._byte_to_pos(bufnr, 0)
    assert.are.equal(0, row)
    assert.are.equal(0, col)
  end)

  it("returns column within first line", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abc", "def" })
    local row, col = visual._byte_to_pos(bufnr, 2)
    assert.are.equal(0, row)
    assert.are.equal(2, col)
  end)

  it("returns position on second line", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abc", "def" })
    -- "abc\n" = 4 bytes; "d" is at byte 4, "e" at 5
    local row, col = visual._byte_to_pos(bufnr, 5)
    assert.are.equal(1, row)
    assert.are.equal(1, col)
  end)

  it("handles multibyte (UTF-8) characters", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "한글", "abc" })
    -- "한" = 3 bytes, "글" = 3 bytes; byte 6 is the end of "한글"
    local row, col = visual._byte_to_pos(bufnr, 6)
    assert.are.equal(0, row)
    assert.are.equal(6, col)
  end)
end)
