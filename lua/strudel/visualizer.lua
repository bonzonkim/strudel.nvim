-- Strudel ASCII Visualizer
-- Displays pattern visualization in a Neovim buffer

local M = {}

-- State
M.buf = nil
M.win = nil
M.is_visible = false
M.timer = nil

-- Visualizer config
M.config = {
  width = 60,
  height = 12,
  position = "bottom", -- "bottom", "right", "float"
  update_interval = 50, -- ms
}

-- ASCII waveform characters
local wave_chars = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

-- Generate simple waveform pattern
local function generate_wave(width, phase)
  local result = {}
  for i = 1, width do
    local t = (i / width * 2 * math.pi) + phase
    local value = math.sin(t) * 0.5 + 0.5 -- Normalize to 0-1
    local char_idx = math.floor(value * (#wave_chars - 1)) + 1
    table.insert(result, wave_chars[char_idx])
  end
  return table.concat(result)
end

-- Generate beat pattern visualization
local function generate_beat_pattern(width, cycle_pos)
  local pattern = {}
  local beat_count = 8
  local beat_width = math.floor(width / beat_count)
  local active_beat = math.floor((cycle_pos or 0) * beat_count) % beat_count + 1
  
  for i = 1, beat_count do
    local char = i == active_beat and "█" or "░"
    for _ = 1, beat_width do
      table.insert(pattern, char)
    end
  end
  
  return table.concat(pattern)
end

-- Create visualizer buffer
local function create_buffer()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  
  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].buftype = "nofile"
  vim.bo[M.buf].bufhidden = "hide"
  vim.bo[M.buf].swapfile = false
  vim.api.nvim_buf_set_name(M.buf, "Strudel Visualizer")
  
  return M.buf
end

-- Open visualizer window
function M.open()
  if M.is_visible then return end
  
  create_buffer()
  
  if M.config.position == "float" then
    local width = M.config.width
    local height = M.config.height
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    
    M.win = vim.api.nvim_open_win(M.buf, false, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
      style = "minimal",
      border = "rounded",
      title = " ♪ Strudel ",
      title_pos = "center",
    })
  elseif M.config.position == "bottom" then
    vim.cmd("botright " .. M.config.height .. "split")
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.win, M.buf)
    vim.cmd("wincmd p") -- Return to previous window
  else -- right
    vim.cmd("botright " .. M.config.width .. "vsplit")
    M.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.win, M.buf)
    vim.cmd("wincmd p")
  end
  
  -- Set window options
  vim.wo[M.win].number = false
  vim.wo[M.win].relativenumber = false
  vim.wo[M.win].cursorline = false
  vim.wo[M.win].signcolumn = "no"
  
  M.is_visible = true
  M.start_animation()
end

-- Close visualizer window
function M.close()
  if not M.is_visible then return end
  
  M.stop_animation()
  
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
  end
  
  M.is_visible = false
end

-- Toggle visualizer
function M.toggle()
  if M.is_visible then
    M.close()
    vim.notify("Strudel Visualizer closed", vim.log.levels.INFO)
  else
    M.open()
    vim.notify("Strudel Visualizer opened", vim.log.levels.INFO)
  end
end

-- Animation state (fallback when no real data)
local phase = 0
local fallback_cycle_pos = 0

-- Update visualizer content
local function update_content()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
  
  local width = vim.api.nvim_win_get_width(M.win)
  
  -- Try to get real beat data from listener
  local beat_data = nil
  local has_listener, listener = pcall(require, "strudel.listener")
  if has_listener then
    beat_data = listener.get_beat()
  end
  
  local cycle_pos, beat, cycle, active_notes, is_playing
  
  if beat_data and beat_data.type == "beat" then
    -- Use real data from Strudel
    cycle_pos = beat_data.cyclePos or 0
    beat = beat_data.beat or 0
    cycle = beat_data.cycle or 0
    active_notes = beat_data.activeNotes or {}
    is_playing = true
    phase = beat_data.time or phase
  else
    -- Fallback animation
    phase = phase + 0.2
    fallback_cycle_pos = (fallback_cycle_pos + 0.02) % 1
    cycle_pos = fallback_cycle_pos
    beat = math.floor(fallback_cycle_pos * 4)
    cycle = 0
    active_notes = {}
    is_playing = false
  end
  
  -- Format active notes display
  local notes_str = "  │  Notes: "
  if #active_notes > 0 then
    local note_parts = {}
    for i, n in ipairs(active_notes) do
      if i > 5 then break end
      local note = n.note ~= "" and n.note or n.sound
      table.insert(note_parts, note)
    end
    notes_str = notes_str .. table.concat(note_parts, " ")
  else
    notes_str = notes_str .. (is_playing and "♪" or "—")
  end
  
  -- Status indicator
  local status = is_playing and "▶ PLAYING" or "⏸ IDLE"
  local cycle_str = string.format("Cycle: %d  Beat: %d/4", cycle, beat + 1)
  
  local lines = {
    "",
    "  ╭─────────────────────────────────────────────────────╮",
    "  │  ♪ STRUDEL VISUALIZER  " .. string.format("%-28s", status) .. "│",
    "  ├─────────────────────────────────────────────────────┤",
    "  │  " .. string.format("%-52s", cycle_str) .. "│",
    "  │                                                     │",
    "  │  Waveform:                                          │",
    "  │  " .. generate_wave(math.min(width - 6, 50), phase),
    "  │                                                     │",
    "  │  Beat Pattern:                                      │",
    "  │  " .. generate_beat_pattern(math.min(width - 6, 48), cycle_pos),
    notes_str .. string.rep(" ", math.max(0, 53 - #notes_str)) .. "│",
    "  ╰─────────────────────────────────────────────────────╯",
  }
  
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  
  -- Apply highlighting
  local ns = vim.api.nvim_create_namespace("strudel_visualizer")
  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
  
  -- Highlight status line based on playing state
  if is_playing then
    vim.api.nvim_buf_add_highlight(M.buf, ns, "StrudelBeat", 2, 25, 36)
  end
  
  -- Highlight wave line
  if vim.api.nvim_buf_line_count(M.buf) >= 8 then
    vim.api.nvim_buf_add_highlight(M.buf, ns, "StrudelWave", 7, 5, -1)
  end
  -- Highlight beat line
  if vim.api.nvim_buf_line_count(M.buf) >= 11 then
    vim.api.nvim_buf_add_highlight(M.buf, ns, "StrudelBeat", 10, 5, -1)
  end
end

-- Start animation loop
function M.start_animation()
  if M.timer then return end
  
  local uv = vim.uv or vim.loop
  M.timer = uv.new_timer()
  M.timer:start(0, M.config.update_interval, vim.schedule_wrap(function()
    if M.is_visible then
      update_content()
    else
      M.stop_animation()
    end
  end))
end

-- Stop animation loop
function M.stop_animation()
  if M.timer then
    M.timer:stop()
    M.timer:close()
    M.timer = nil
  end
end

-- Setup function
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
end

return M
