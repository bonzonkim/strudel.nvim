-- A small, self contained piano roll.  It deliberately does not know about
-- the bridge: callers may feed it either decoded tables or JSON strings.
local M = {}

M.ns_id = vim.api.nvim_create_namespace("strudel_piano_roll")
M.events = {}
M.config = {}
M.bufnr = nil
M.winid = nil
M.timer = nil
M.is_open = false
M.playhead = 0
M._epoch = 0

local defaults = {
  width = 80, height = 20, cycles = 8, redraw_hz = 30,
  max_events = 2000, midi_low = 36, midi_high = 84,
}

local function number(value)
  value = tonumber(value)
  return value and value == value and value or nil
end

local function midi(value)
  local n = number(value)
  if n then return math.floor(n + 0.5) end
  if type(value) ~= "string" then return nil end
  local names = { c = 0, ["c#"] = 1, db = 1, d = 2, ["d#"] = 3, eb = 3,
    e = 4, f = 5, ["f#"] = 6, gb = 6, g = 7, ["g#"] = 8, ab = 8,
    a = 9, ["a#"] = 10, bb = 10, b = 11 }
  local note, octave = value:lower():match("^([a-g][#b]?)(%-?%d+)$")
  if note and names[note] then return (tonumber(octave) + 1) * 12 + names[note] end
  return nil
end

local function decode_json(value)
  if vim.json and type(vim.json.decode) == "function" then
    local ok, decoded = pcall(vim.json.decode, value)
    if ok then return decoded end
  end
  if vim.fn and type(vim.fn.json_decode) == "function" then
    local ok, decoded = pcall(vim.fn.json_decode, value)
    if ok then return decoded end
  end
  return nil
end

-- Exposed because it makes bridge compatibility and tests pleasantly boring.
function M._normalize(event)
  if type(event) == "string" then
    event = decode_json(event)
  end
  if type(event) ~= "table" then return nil end
  local start = number(event.time or event.begin or event.t or event.start)
  local duration = number(event.duration or event.dur or event.length) or 1
  if not start or duration <= 0 then return nil end
  local pitch = midi(event.pitch or event.midi or event.note)
  return {
    time = math.max(0, start), duration = duration, pitch = pitch,
    sound = type(event.sound or event.s) == "string" and (event.sound or event.s) or nil,
    label = type(event.label) == "string" and event.label or nil,
    velocity = number(event.velocity or event.vel), gain = number(event.gain),
  }
end

local function valid_buffer()
  return M.bufnr and vim.api.nvim_buf_is_valid(M.bufnr)
end

local function valid_window()
  return M.winid and vim.api.nvim_win_is_valid(M.winid)
end

local function stop_timer()
  if M.timer then M.timer:stop(); M.timer:close(); M.timer = nil end
end

local function highlight(name, opts)
  pcall(vim.api.nvim_set_hl, 0, name, opts)
end

local function redraw()
  if not M.is_open or not valid_window() or not valid_buffer() then return end
  local c = M.config
  local label_width = 7
  local timeline = math.max(8, c.width - label_width)
  local rows = math.max(2, c.height - 1)
  local lines = {}
  local pitch_rows = math.max(1, rows - 1)
  lines[1] = string.format(" %-5s%s", "pitch", string.rep("·", timeline))
  for row = 1, pitch_rows do
    local p = c.midi_high - math.floor((row - 1) * (c.midi_high - c.midi_low) / math.max(1, pitch_rows - 1) + 0.5)
    local name = ({ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" })[(p % 12) + 1]
    lines[#lines + 1] = string.format("%-6s ", name .. tostring(math.floor(p / 12) - 1)) .. string.rep(" ", timeline)
  end
  lines[#lines + 1] = string.format("%-6s ", "sound") .. string.rep(" ", timeline)
  vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(M.bufnr, M.ns_id, 0, -1)
  highlight("StrudelPianoRollGrid", { fg = "#4b5563" })
  highlight("StrudelPianoRollNote", { bg = "#7c3aed", fg = "#ffffff", bold = true })
  highlight("StrudelPianoRollSound", { bg = "#0e7490", fg = "#ffffff", bold = true })
  highlight("StrudelPianoRollPlayhead", { fg = "#fbbf24", bold = true })
  local function col(time)
    return label_width + math.floor((time - M.playhead + c.cycles / 2) / c.cycles * timeline)
  end
  for _, event in ipairs(M.events) do
    local x, x2 = col(event.time), col(event.time + event.duration)
    if x2 > 0 and x < c.width then
      x, x2 = math.max(0, x), math.min(c.width, math.max(x + 1, x2))
      local row, group
      if event.pitch and event.pitch >= c.midi_low and event.pitch <= c.midi_high then
        row = 2 + math.floor((c.midi_high - event.pitch) * (pitch_rows - 1) / math.max(1, c.midi_high - c.midi_low) + 0.5)
        group = "StrudelPianoRollNote"
      else
        row, group = #lines, "StrudelPianoRollSound"
      end
      local text = event.label or event.sound or "•"
      pcall(vim.api.nvim_buf_set_extmark, M.bufnr, M.ns_id, row - 1, x, {
        end_col = x2, hl_group = group, virt_text = { { text:sub(1, math.max(1, x2 - x)), group } },
        virt_text_pos = "overlay", priority = 100,
      })
    end
  end
  local head = math.max(0, math.min(c.width - 1, col(M.playhead)))
  for row = 0, #lines - 1 do
    pcall(vim.api.nvim_buf_set_extmark, M.bufnr, M.ns_id, row, head, { virt_text = { { "│", "StrudelPianoRollPlayhead" } }, virt_text_pos = "overlay", priority = 200 })
  end
end

function M.setup(opts)
  opts = opts or {}
  M.close()
  M.config = vim.tbl_deep_extend("force", defaults, opts)
  M.events, M.playhead = {}, 0
  M.is_open = false
end

function M.handle_event(event)
  local normalized = M._normalize(event)
  if not normalized then return false end
  M.events[#M.events + 1] = normalized
  local max_events = M.config.max_events or defaults.max_events
  while #M.events > max_events do table.remove(M.events, 1) end
  M.playhead = math.max(M.playhead, normalized.time)
  if M.is_open then redraw() end
  return true
end

function M.open()
  if M.is_open and valid_window() then return M.winid end
  if not next(M.config) then M.setup({}) end
  if not valid_buffer() then
    M.bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[M.bufnr].buftype, vim.bo[M.bufnr].bufhidden = "nofile", "wipe"
    vim.bo[M.bufnr].modifiable = true
  end
  local width, height = M.config.width, M.config.height
  M.winid = vim.api.nvim_open_win(M.bufnr, false, { relative = "editor", width = width, height = height, row = 1, col = math.max(0, (vim.o.columns - width) / 2), style = "minimal", border = "rounded", title = " Strudel piano roll ", title_pos = "center" })
  vim.wo[M.winid].wrap = false
  M.is_open = true
  redraw()
  stop_timer()
  M.timer = vim.loop.new_timer()
  M.timer:start(0, math.max(10, math.floor(1000 / M.config.redraw_hz)), function()
    if not valid_window() then stop_timer(); M.is_open = false; return end
    vim.schedule(redraw)
  end)
  return M.winid
end

function M.close()
  stop_timer()
  if valid_window() then pcall(vim.api.nvim_win_close, M.winid, true) end
  M.winid, M.is_open = nil, false
end

function M.toggle() if M.is_open then M.close(); return false else M.open(); return true end end
function M.clear() M.events, M.playhead = {}, 0; if valid_buffer() and M.is_open then redraw() end end
function M.shutdown() M.close(); if valid_buffer() then pcall(vim.api.nvim_buf_delete, M.bufnr, { force = true }) end; M.bufnr = nil; M.events = {} end

M._redraw = redraw
M._valid_window = valid_window
return M
