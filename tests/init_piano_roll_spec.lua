describe("strudel source piano-roll calls", function()
  local original_loaded
  local buffer
  local piano_roll
  local sent

  before_each(function()
    original_loaded = {
      strudel = package.loaded["strudel"],
      osc = package.loaded["strudel.osc"],
      visual = package.loaded["strudel.visual"],
      piano_roll = package.loaded["strudel.piano_roll"],
    }

    sent = {}
    piano_roll = {
      targets = {},
      opened = 0,
      clear_calls = {},
      set_inline_target = function(bufnr, offset, opts)
        piano_roll.targets[#piano_roll.targets + 1] = {
          bufnr = bufnr, offset = offset, opts = opts,
        }
      end,
      clear_inline_targets = function(bufnr, start_offset, end_offset)
        piano_roll.clear_calls[#piano_roll.clear_calls + 1] = {
          bufnr = bufnr, start_offset = start_offset, end_offset = end_offset,
        }
      end,
      open = function() piano_roll.opened = piano_roll.opened + 1 end,
    }

    package.loaded["strudel"] = nil
    package.loaded["strudel.osc"] = {
      send = function(_, _, _, args) sent[#sent + 1] = args[1] end,
    }
    package.loaded["strudel.visual"] = {
      set_last_eval = function() end,
    }
    package.loaded["strudel.piano_roll"] = piano_roll

    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buffer)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(buffer) then
      vim.api.nvim_buf_delete(buffer, { force = true })
    end
    package.loaded["strudel"] = original_loaded.strudel
    package.loaded["strudel.osc"] = original_loaded.osc
    package.loaded["strudel.visual"] = original_loaded.visual
    package.loaded["strudel.piano_roll"] = original_loaded.piano_roll
  end)

  it("recognizes calls but ignores strings and comments without changing source", function()
    local source = 'const text = "._pianoroll()"; /* .pianoroll() */ sound("bd")._pianoroll({ labels: 1 }).pianoroll() // ._pianoroll()'
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { source })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    require("strudel").eval_line()

    assert.are.equal(source, sent[1])
    assert.are.equal(1, #piano_roll.targets)
    assert.are.equal(buffer, piano_roll.targets[1].bufnr)
    local method_close = source:find(")._pianoroll", 1, true)
    assert.are.equal(method_close, piano_roll.targets[1].offset)
    assert.are.equal(1, piano_roll.targets[1].opts.labels)
    assert.are.equal(1, piano_roll.opened)
    assert.are.equal(1, #piano_roll.clear_calls)
  end)
end)
