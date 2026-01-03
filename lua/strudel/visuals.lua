-- Strudel Visual Effects Module
-- Provides visual feedback for live coding in Neovim

local M = {}

-- Namespace for extmarks
M.ns = vim.api.nvim_create_namespace("strudel_visuals")

-- Configuration
M.config = {
  flash_duration = 150, -- milliseconds
  flash_color = "#FFD700", -- Gold color
  beat_indicator = "▸",
}

-- Setup highlight groups
function M.setup_highlights()
  vim.api.nvim_set_hl(0, "StrudelFlash", {
    bg = M.config.flash_color,
    fg = "#000000",
    bold = true,
  })
  vim.api.nvim_set_hl(0, "StrudelFlashFade1", {
    bg = "#CCAC00",
    fg = "#000000",
  })
  vim.api.nvim_set_hl(0, "StrudelFlashFade2", {
    bg = "#997F00",
    fg = "#1a1a1a",
  })
  vim.api.nvim_set_hl(0, "StrudelFlashFade3", {
    bg = "#665500",
    fg = "#333333",
  })
  vim.api.nvim_set_hl(0, "StrudelBeat", {
    fg = "#00FF00",
    bold = true,
  })
  vim.api.nvim_set_hl(0, "StrudelWave", {
    fg = "#00BFFF",
  })
  -- White box highlight like Strudel browser
  vim.api.nvim_set_hl(0, "StrudelHighlight", {
    bg = "#FFFFFF",
    fg = "#000000",
    bold = true,
  })
  vim.api.nvim_set_hl(0, "StrudelHighlightDim", {
    bg = "#AAAAAA",
    fg = "#000000",
  })
end

-- Flash a single line with fade effect
function M.flash_line(line_num, duration)
  duration = duration or M.config.flash_duration
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Get the line content to determine end column
  local line = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1] or ""
  local end_col = #line
  
  -- Apply initial highlight
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, line_num - 1, 0, {
    end_col = end_col,
    hl_group = "StrudelFlash",
    hl_eol = true,
    priority = 1000,
  })
  
  -- Fade effect with timer
  local uv = vim.uv or vim.loop
  local fade_stages = {"StrudelFlashFade1", "StrudelFlashFade2", "StrudelFlashFade3"}
  local stage = 0
  local fade_interval = duration / 4
  
  local timer = uv.new_timer()
  timer:start(fade_interval, fade_interval, vim.schedule_wrap(function()
    stage = stage + 1
    
    if stage > #fade_stages then
      -- Remove the highlight
      pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, mark_id)
      timer:stop()
      timer:close()
    else
      -- Update to next fade stage
      pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, mark_id)
      mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, line_num - 1, 0, {
        end_col = end_col,
        hl_group = fade_stages[stage],
        hl_eol = true,
        priority = 1000,
      })
    end
  end))
end

-- Flash a range of lines (for visual selection)
function M.flash_range(start_row, end_row, duration)
  duration = duration or M.config.flash_duration
  for line = start_row, end_row do
    M.flash_line(line, duration)
  end
end

-- Beat indicator using virtual text
M.beat_marks = {}

function M.show_beat(line_num, cycle_pos)
  local bufnr = vim.api.nvim_get_current_buf()
  local indicator = M.config.beat_indicator .. " " .. string.format("%.2f", cycle_pos or 0)
  
  -- Clear previous beat marks
  for _, mark_id in ipairs(M.beat_marks) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, mark_id)
  end
  M.beat_marks = {}
  
  -- Add new beat indicator
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, line_num - 1, 0, {
    virt_text = {{ indicator, "StrudelBeat" }},
    virt_text_pos = "eol",
  })
  table.insert(M.beat_marks, mark_id)
end

function M.clear_beats()
  local bufnr = vim.api.nvim_get_current_buf()
  for _, mark_id in ipairs(M.beat_marks) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, mark_id)
  end
  M.beat_marks = {}
end

-- Inline beat pulse for code buffer
M.inline_enabled = true  -- ENABLED BY DEFAULT
M.eval_line = nil  -- Track which line was last evaluated
M.eval_bufnr = nil -- Track which buffer was evaluated
M.pulse_marks = {}
M.last_beat = -1  -- Track last beat for highlighting

-- Beat symbols for different beats
local beat_symbols = { "●", "○", "○", "○" }  -- Beat 1 highlighted
local note_symbols = { "♪", "♫", "♬", "♩" }

-- Show beat pulse inline (called on each beat from listener)
function M.show_inline_beat(beat_data)
  if not M.inline_enabled then return end
  if not M.eval_line or not M.eval_bufnr then return end
  
  local bufnr = M.eval_bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  
  -- Clear previous pulse marks
  for _, mark_id in ipairs(M.pulse_marks) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, mark_id)
  end
  M.pulse_marks = {}
  
  local beat = (beat_data.beat or 0) + 1
  local cycle = beat_data.cycle or 0
  local notes = beat_data.activeNotes or {}
  local line_num = M.eval_line
  
  -- Get the line content
  local line = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)[1] or ""
  if #line == 0 then return end
  
  -- === SMART NOTE HIGHLIGHTING ===
  -- Find and highlight the exact note that is currently playing
  local highlighted = false
  
  for _, note_data in ipairs(notes) do
    local note = note_data.note or ""
    if note ~= "" then
      -- Extract just the note name (e.g., "c3" -> "c", "eb4" -> "eb")
      local note_name = note:match("^([a-g][#b]?)") or note:match("^([a-g])") or ""
      
      if note_name ~= "" then
        -- Search for this note in the code
        -- Look for patterns like: "c", 'c', c (in brackets), n("c...")
        local patterns = {
          '"' .. note_name .. '[^"]*"',   -- "c3" or "c"
          "'" .. note_name .. "[^']*'",   -- 'c3' or 'c'
          "%[.-%f[%a]" .. note_name .. "%f[%A]",  -- [c e g] - note in brackets
          note_name .. "%d",              -- c3 (note with octave)
        }
        
        local start_pos, end_pos
        for _, pattern in ipairs(patterns) do
          local s, e = line:find(pattern)
          if s then
            -- For bracket patterns, find the specific note position
            if pattern:match("^%%[") then
              -- Find the note within brackets
              local bracket_start = line:find("%[")
              if bracket_start then
                local bracket_content = line:match("%[([^%]]*)%]")
                if bracket_content then
                  -- Find the specific note in bracket content
                  local note_s = bracket_content:find("%f[%a]" .. note_name .. "%f[%A]")
                  if note_s then
                    start_pos = bracket_start + note_s
                    end_pos = start_pos + #note_name - 1
                  end
                end
              end
            else
              start_pos = s
              end_pos = e
            end
            break
          end
        end
        
        if start_pos and end_pos then
          local mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, line_num - 1, start_pos - 1, {
            end_col = end_pos,
            hl_group = "StrudelHighlight",
            priority = 1001,
          })
          table.insert(M.pulse_marks, mark_id)
          highlighted = true
        end
      end
    end
  end
  
  -- Fallback: if no note found, highlight based on beat position
  if not highlighted and #notes > 0 then
    local segments = 4
    local seg_len = math.ceil(#line / segments)
    local start_col = (beat - 1) * seg_len
    local end_col = math.min(beat * seg_len, #line)
    
    if start_col < #line then
      local mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, line_num - 1, start_col, {
        end_col = end_col,
        hl_group = "StrudelHighlight",
        priority = 1001,
      })
      table.insert(M.pulse_marks, mark_id)
    end
  end
  
  -- Virtual text with current note info
  local note_str = ""
  if #notes > 0 then
    for i, n in ipairs(notes) do
      if i > 2 then break end
      note_str = note_str .. " " .. (n.note ~= "" and n.note or n.sound)
    end
  end
  
  local beat_vis = string.rep("○", beat - 1) .. "●" .. string.rep("○", 4 - beat)
  local display = string.format(" %s%s", beat_vis, note_str)
  
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, line_num - 1, 0, {
    virt_text = {{ display, "StrudelBeat" }},
    virt_text_pos = "eol",
    priority = 999,
  })
  table.insert(M.pulse_marks, mark_id)
end

-- Enable/disable inline beat visuals
function M.enable_inline()
  M.inline_enabled = true
  
  -- Register with listener for beat callbacks
  local has_listener, listener = pcall(require, "strudel.listener")
  if has_listener then
    listener.on_beat(function(beat_data)
      if beat_data.type == "beat" then
        vim.schedule(function()
          M.show_inline_beat(beat_data)
        end)
      elseif beat_data.type == "stop" then
        vim.schedule(function()
          M.disable_inline()
        end)
      end
    end)
    vim.notify("Strudel inline visuals enabled", vim.log.levels.INFO)
  end
end

function M.disable_inline()
  M.inline_enabled = false
  M.eval_line = nil
  
  -- Clear all pulse marks
  local bufnr = vim.api.nvim_get_current_buf()
  for _, mark_id in ipairs(M.pulse_marks) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns, mark_id)
  end
  M.pulse_marks = {}
end

function M.toggle_inline()
  if M.inline_enabled then
    M.disable_inline()
    vim.notify("Strudel inline visuals disabled", vim.log.levels.INFO)
  else
    M.enable_inline()
  end
end

-- Set the line being evaluated (for inline visuals)
function M.set_eval_line(line_num)
  M.eval_line = line_num
  M.eval_bufnr = vim.api.nvim_get_current_buf()
  
  -- Ensure callback is registered
  local has_listener, listener = pcall(require, "strudel.listener")
  if has_listener and #listener.callbacks == 0 then
    listener.on_beat(function(beat_data)
      vim.schedule(function()
        if beat_data.type == "beat" then
          M.show_inline_beat(beat_data)
        elseif beat_data.type == "stop" then
          M.disable_inline()
        end
      end)
    end)
  end
end

-- Initialize module
function M.setup(opts)
  if opts then
    M.config = vim.tbl_deep_extend("force", M.config, opts)
  end
  M.setup_highlights()
end

-- Auto-setup highlights on load
M.setup_highlights()

return M

