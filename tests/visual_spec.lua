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

describe("strudel.visual handle_event happy path", function()
  local visual
  local bufnr

  before_each(function()
    package.loaded["strudel.visual"] = nil
    visual = require("strudel.visual")
    visual.setup({})
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 's("bd sd hh cp").play()' })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("set_last_eval stores bufnr and offset", function()
    visual.set_last_eval(bufnr, 42)
    assert.are.equal(bufnr, visual.last_eval.bufnr)
    assert.are.equal(42, visual.last_eval.offset)
  end)

  it("places an extmark at offset + loc for a valid event", function()
    visual.set_last_eval(bufnr, 0)
    -- "bd" is at character offsets 3..5 in 's("bd sd hh cp").play()'
    visual.handle_event('{"locs":[[3,5]],"s":"bd","dur":1.0}')

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, visual.ns_id, 0, -1, { details = true })
    assert.are.equal(1, #marks)
    local mark = marks[1]
    -- mark = { id, row, col, details }
    assert.are.equal(0, mark[2])  -- row
    assert.are.equal(3, mark[3])  -- col
    assert.are.equal(5, mark[4].end_col)
  end)

  it("applies offset when last_eval.offset is non-zero", function()
    -- Imagine a buffer where the eval'd region starts 10 bytes in
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'xxxxxxxxxxs("bd").play()' })
    visual.set_last_eval(bufnr, 10)
    visual.handle_event('{"locs":[[3,5]],"s":"bd","dur":1.0}')

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, visual.ns_id, 0, -1, { details = true })
    assert.are.equal(1, #marks)
    assert.are.equal(13, marks[1][3])  -- 10 + 3 = 13
    assert.are.equal(15, marks[1][4].end_col)
  end)

  it("places one extmark per loc in the event", function()
    visual.set_last_eval(bufnr, 0)
    visual.handle_event('{"locs":[[3,5],[6,8]],"s":"bd","dur":1.0}')

    local marks = vim.api.nvim_buf_get_extmarks(bufnr, visual.ns_id, 0, -1, {})
    assert.are.equal(2, #marks)
  end)
end)

describe("strudel.visual handle_event guards", function()
  local visual
  local bufnr

  before_each(function()
    package.loaded["strudel.visual"] = nil
    visual = require("strudel.visual")
    visual.setup({})
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 's("bd").play()' })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function mark_count()
    return #vim.api.nvim_buf_get_extmarks(bufnr, visual.ns_id, 0, -1, {})
  end

  it("skips when enabled is false", function()
    visual.set_last_eval(bufnr, 0)
    visual.enabled = false
    visual.handle_event('{"locs":[[3,5]],"s":"bd","dur":1.0}')
    assert.are.equal(0, mark_count())
  end)

  it("skips when last_eval.bufnr is nil", function()
    -- Don't call set_last_eval
    visual.handle_event('{"locs":[[3,5]],"s":"bd","dur":1.0}')
    assert.are.equal(0, mark_count())
  end)

  it("skips invalid JSON silently", function()
    visual.set_last_eval(bufnr, 0)
    -- Must not raise
    visual.handle_event("not valid json {")
    assert.are.equal(0, mark_count())
  end)

  it("skips when bufnr no longer valid", function()
    visual.set_last_eval(bufnr, 0)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    -- Must not raise
    visual.handle_event('{"locs":[[3,5]],"s":"bd","dur":1.0}')
    -- bufnr is gone; no asserting on it
  end)

  it("skips empty locs array", function()
    visual.set_last_eval(bufnr, 0)
    visual.handle_event('{"locs":[],"s":"bd","dur":1.0}')
    assert.are.equal(0, mark_count())
  end)

  it("skips loc with from > to", function()
    visual.set_last_eval(bufnr, 0)
    visual.handle_event('{"locs":[[5,3]],"s":"bd","dur":1.0}')
    assert.are.equal(0, mark_count())
  end)

  it("skips non-numeric loc entries", function()
    visual.set_last_eval(bufnr, 0)
    visual.handle_event('{"locs":[["a","b"]],"s":"bd","dur":1.0}')
    assert.are.equal(0, mark_count())
  end)

  it("uses 'unknown' when s is missing", function()
    visual.set_last_eval(bufnr, 0)
    visual.handle_event('{"locs":[[3,5]],"dur":1.0}')
    -- Should still place the mark (under "unknown" hl group)
    assert.are.equal(1, mark_count())
  end)
end)

describe("strudel.visual duration timer", function()
  local visual
  local bufnr

  before_each(function()
    package.loaded["strudel.visual"] = nil
    visual = require("strudel.visual")
    visual.setup({})
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 's("bd").play()' })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function mark_count()
    return #vim.api.nvim_buf_get_extmarks(bufnr, visual.ns_id, 0, -1, {})
  end

  it("removes extmark after duration elapses", function()
    visual.set_last_eval(bufnr, 0)
    visual.handle_event('{"locs":[[3,5]],"s":"bd","dur":0.08}')  -- 80ms
    assert.are.equal(1, mark_count())

    -- Wait until the timer fires (poll with a margin)
    vim.wait(200, function() return mark_count() == 0 end)
    assert.are.equal(0, mark_count())
  end)

  it("clamps sub-50ms durations to 50ms minimum", function()
    visual.set_last_eval(bufnr, 0)
    visual.handle_event('{"locs":[[3,5]],"s":"bd","dur":0.01}')  -- 10ms requested
    assert.are.equal(1, mark_count())

    -- After 30ms, mark must still be alive (not removed at 10ms)
    vim.wait(30, function() return false end)
    assert.are.equal(1, mark_count())

    -- By 200ms, mark should be gone (50ms clamp + scheduling slack)
    vim.wait(200, function() return mark_count() == 0 end)
    assert.are.equal(0, mark_count())
  end)
end)

describe("strudel.visual toggle and clear_all", function()
  local visual
  local bufnr

  before_each(function()
    package.loaded["strudel.visual"] = nil
    visual = require("strudel.visual")
    visual.setup({})
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 's("bd").play()' })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("toggle flips enabled and returns new state", function()
    assert.is_true(visual.enabled)
    assert.is_false(visual.toggle())
    assert.is_false(visual.enabled)
    assert.is_true(visual.toggle())
    assert.is_true(visual.enabled)
  end)

  it("clear_all removes all extmarks in the namespace", function()
    visual.set_last_eval(bufnr, 0)
    visual.handle_event('{"locs":[[3,5]],"s":"bd","dur":10.0}')  -- long duration
    assert.are.equal(1, #vim.api.nvim_buf_get_extmarks(bufnr, visual.ns_id, 0, -1, {}))

    visual.clear_all()
    assert.are.equal(0, #vim.api.nvim_buf_get_extmarks(bufnr, visual.ns_id, 0, -1, {}))
  end)

  it("clear_all clears last_eval", function()
    visual.set_last_eval(bufnr, 42)
    visual.clear_all()
    assert.is_nil(visual.last_eval.bufnr)
  end)

  it("clear_all is safe when last_eval.bufnr is nil", function()
    -- Must not raise
    visual.clear_all()
  end)
end)
