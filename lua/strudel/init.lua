local osc = require("strudel.osc")
local M = {}

M.config = {
  host = "127.0.0.1",
  port = 9129, -- Default Strudel Desktop OSC port
}

function M.setup(opts)
  M.is_setup = true
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Forward visual_effects opts to the visual module
  require("strudel.visual").setup((opts or {}).visual_effects)
  require("strudel.piano_roll").setup((opts or {}).piano_roll)

  -- Setup dictionary for autocomplete (if setup is called)
  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
  local dict_path = plugin_dir .. "/dict/strudel.dict"
  -- Add autocmd to set the dictionary for Strudel-oriented buffers.
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "javascript", "javascriptreact", "typescript", "typescriptreact", "strudel" },
    callback = function()
      vim.opt_local.dictionary:append(dict_path)
      vim.opt_local.complete:append("k")
    end,
  })
end

-- Auto-register nvim-cmp source (Top-level execution)
local function register_cmp()
  local has_cmp, cmp = pcall(require, "cmp")
  if has_cmp then
    cmp.register_source("strudel", require("strudel.cmp").new())
    --vim.notify("Strudel: Registered nvim-cmp source", vim.log.levels.INFO)
    return true
  end
  return false
end

vim.schedule(function()
  if not register_cmp() then
    -- If cmp is not loaded yet, try again on InsertEnter (common for lazy loading)
    vim.api.nvim_create_autocmd("InsertEnter", {
      once = true,
      callback = function()
        if register_cmp() then
           -- Success
        else
           vim.notify("Strudel: nvim-cmp not found even after InsertEnter. Please configure manually.", vim.log.levels.WARN)
        end
      end
    })
  end
end)

function M.eval(code)
  if not code or code == "" then return end
  -- Strudel expects the code as a single string argument to /eval
  osc.send(M.config.host, M.config.port, "/eval", { code })
end

local function visual()
  -- Lazy load to avoid hard dep at file scope
  return require("strudel.visual")
end

local function piano_roll()
  local ok, module = pcall(require, "strudel.piano_roll")
  if not ok or type(module) ~= "table" then return nil end
  return module
end

local function skip_quoted(source, index, quote)
  index = index + 1
  while index <= #source do
    local char = source:sub(index, index)
    if char == "\\" then
      index = index + 2
    elseif char == quote then
      return index + 1
    else
      index = index + 1
    end
  end
  return index
end

local function skip_comment(source, index)
  if source:sub(index, index + 1) == "//" then
    local newline = source:find("\n", index + 2, true)
    return newline and newline + 1 or #source + 1
  end
  if source:sub(index, index + 1) == "/*" then
    local finish = source:find("*/", index + 2, true)
    return finish and finish + 2 or #source + 1
  end
  return nil
end

local function skip_space_and_comments(source, index)
  while index <= #source do
    local next_index = skip_comment(source, index)
    if next_index then
      index = next_index
    elseif source:sub(index, index):match("%s") then
      index = index + 1
    else
      break
    end
  end
  return index
end

local function matching_parenthesis(source, opening)
  local depth = 1
  local index = opening + 1
  while index <= #source do
    local char = source:sub(index, index)
    if char == "'" or char == '"' or char == "`" then
      index = skip_quoted(source, index, char)
    else
      local next_index = skip_comment(source, index)
      if next_index then
        index = next_index
      elseif char == "(" then
        depth = depth + 1
        index = index + 1
      elseif char == ")" then
        depth = depth - 1
        if depth == 0 then return index end
        index = index + 1
      else
        index = index + 1
      end
    end
  end
  return nil
end

local function quote_object_keys(source)
  local result = {}
  local index = 1
  while index <= #source do
    local char = source:sub(index, index)
    if char == "'" or char == '"' then
      local finish = skip_quoted(source, index, char)
      result[#result + 1] = source:sub(index, finish - 1)
      index = finish
    elseif char:match("[%a_$]") then
      local finish = index + 1
      while finish <= #source and source:sub(finish, finish):match("[%w_$]") do
        finish = finish + 1
      end
      local after = skip_space_and_comments(source, finish)
      if source:sub(after, after) == ":" then
        result[#result + 1] = '"' .. source:sub(index, finish - 1) .. '"'
        result[#result + 1] = source:sub(finish, after - 1)
        index = after
      else
        result[#result + 1] = source:sub(index, finish - 1)
        index = finish
      end
    else
      result[#result + 1] = char
      index = index + 1
    end
  end
  return table.concat(result)
end

local function decode_json(value)
  local decoder
  if vim.json and type(vim.json.decode) == "function" then
    decoder = vim.json.decode
  elseif vim.fn and type(vim.fn.json_decode) == "function" then
    decoder = vim.fn.json_decode
  else
    return false, nil
  end
  return pcall(decoder, value)
end

local function parse_inline_opts(argument)
  local text = vim.trim(argument or "")
  if text == "" then return {} end

  local ok, decoded = decode_json(text)
  if ok and type(decoded) == "table" then return decoded end

  if text:sub(1, 1) == "{" and text:sub(-1) == "}" then
    ok, decoded = decode_json(quote_object_keys(text))
    if ok and type(decoded) == "table" then return decoded end
  end
  return {}
end

local function find_piano_roll_calls(source)
  local calls = {}
  local index = 1
  while index <= #source do
    local char = source:sub(index, index)
    if char == "'" or char == '"' or char == "`" then
      index = skip_quoted(source, index, char)
    else
      local next_index = skip_comment(source, index)
      if next_index then
        index = next_index
      elseif char == "." then
        local name
        if source:sub(index + 1, index + 10) == "_pianoroll" then
          name = "_pianoroll"
        elseif source:sub(index + 1, index + 9) == "pianoroll" then
          name = "pianoroll"
        end

        if name then
          local opening = skip_space_and_comments(source, index + #name + 1)
          if source:sub(opening, opening) == "(" then
            local closing = matching_parenthesis(source, opening)
            if closing then
              calls[#calls + 1] = {
                name = name,
                offset = index - 1,
                opts = parse_inline_opts(source:sub(opening + 1, closing - 1)),
              }
            end
          end
        end
        index = index + 1
      else
        index = index + 1
      end
    end
  end
  return calls
end

local function ranges_overlap(first_start, first_end, second_start, second_end)
  return first_start <= second_end and second_start <= first_end
end

local function sync_inline_targets(bufnr, absolute_offset, source)
  local calls = find_piano_roll_calls(source)
  local absolute_end = absolute_offset + #source
  local scopes = M._inline_scopes and M._inline_scopes[bufnr] or {}
  local affected = false
  for _, scope in ipairs(scopes) do
    if ranges_overlap(scope.start, scope.finish, absolute_offset, absolute_end) then
      affected = true
      break
    end
  end
  if #calls == 0 and not affected then return end

  local module = piano_roll()
  if not module then return end
  local set_target = module.set_inline_target
  local clear_targets = module.clear_inline_targets
  if type(clear_targets) ~= "function" then
    clear_targets = module.clear_inline_target
  end

  if affected or #calls > 0 then
    if type(clear_targets) == "function" then
      pcall(clear_targets, bufnr, absolute_offset, absolute_end)
    end
  end

  local registered = false
  for _, call in ipairs(calls) do
    if call.name == "pianoroll" then
      if type(module.open) == "function" then pcall(module.open) end
    elseif type(set_target) == "function" then
      local ok = pcall(set_target, bufnr, absolute_offset + call.offset, call.opts)
      registered = registered or ok
    end
  end

  local remaining = {}
  for _, scope in ipairs(scopes) do
    if not ranges_overlap(scope.start, scope.finish, absolute_offset, absolute_end) then
      remaining[#remaining + 1] = scope
    end
  end
  if registered then
    remaining[#remaining + 1] = { start = absolute_offset, finish = absolute_end }
  end
  M._inline_scopes = M._inline_scopes or {}
  M._inline_scopes[bufnr] = remaining
end

function M.eval_line()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1  -- 0-indexed
  local offset = vim.api.nvim_buf_get_offset(bufnr, row)
  visual().set_last_eval(bufnr, offset)

  local line = vim.api.nvim_get_current_line()
  sync_inline_targets(bufnr, offset, line)
  M.eval(line)
end

function M.eval_visual()
  -- Get visual selection
  local _, start_row, start_col, _ = unpack(vim.fn.getpos("'<"))
  local _, end_row, end_col, _ = unpack(vim.fn.getpos("'>"))

  -- Adjust for 0-based indexing in API
  start_row = start_row - 1
  start_col = start_col - 1
  end_row = end_row - 1

  -- Handle end_col being 2147483647 (max int) when selecting whole line
  if end_col > 2147483647 then end_col = 2147483647 end

  local bufnr = vim.api.nvim_get_current_buf()
  local offset = vim.api.nvim_buf_get_offset(bufnr, start_row) + start_col
  visual().set_last_eval(bufnr, offset)

  local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  local code = table.concat(lines, "\n")
  sync_inline_targets(bufnr, offset, code)
  M.eval(code)
end

function M.eval_file()
  local bufnr = vim.api.nvim_get_current_buf()
  visual().set_last_eval(bufnr, 0)

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local code = table.concat(lines, "\n")
  sync_inline_targets(bufnr, 0, code)
  M.eval(code)
end

-- Stop sound (Strudel usually stops if you send empty code or specific command)
-- Sending "hush()" is a common pattern in Tidal/Strudel to stop sound
function M.stop()
  M.eval("hush()")
end

-- Bridge Management
M.bridge_job_id = nil

function M.start_bridge()
  if M.bridge_job_id then
    vim.notify("Strudel Bridge is already running.", vim.log.levels.INFO)
    return
  end

  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
  local script_path = plugin_dir .. "/osc-bridge/headless-bridge.js"
  
  -- Check if node_modules exists, if not, notify user to install
  local node_modules = plugin_dir .. "/osc-bridge/node_modules"
  if vim.fn.isdirectory(node_modules) == 0 then
     vim.notify("Strudel Bridge dependencies not found. Please run 'npm install' in " .. plugin_dir .. "/osc-bridge", vim.log.levels.ERROR)
     return
  end

  M.bridge_job_id = vim.fn.jobstart({"node", script_path}, {
    on_stdout = function(_, data)
      if not data then return end
      local prefix = "__STRUDEL_EVENT__"
      local prefix_len = #prefix
      for _, line in ipairs(data) do
        if line ~= "" then
          if line:sub(1, prefix_len) == prefix then
            local event = line:sub(prefix_len + 1)
            require("strudel.visual").handle_event(event)
            require("strudel.piano_roll").handle_event(event)
          else
            print("[Strudel] " .. line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
           if line ~= "" then print("[Strudel Error] " .. line) end
        end
      end
    end,
    on_exit = function()
      M.bridge_job_id = nil
      require("strudel.visual").clear_all()
      require("strudel.piano_roll").shutdown()
      print("[Strudel] Bridge stopped.")
    end,
  })
  
  if M.bridge_job_id > 0 then
    vim.notify("Strudel Bridge started!", vim.log.levels.INFO)
  else
    vim.notify("Failed to start Strudel Bridge.", vim.log.levels.ERROR)
    M.bridge_job_id = nil
  end
end

function M.stop_bridge()
  if M.bridge_job_id then
    vim.fn.jobstop(M.bridge_job_id)
    M.bridge_job_id = nil
    require("strudel.visual").clear_all()
    require("strudel.piano_roll").shutdown()
  else
    vim.notify("Strudel Bridge is not running.", vim.log.levels.WARN)
  end
end

function M.show_window()
  osc.send(M.config.host, M.config.port, "/bridge/show", {})
end

function M.hide_window()
  osc.send(M.config.host, M.config.port, "/bridge/hide", {})
end

return M
