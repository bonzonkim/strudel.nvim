local osc = require("strudel.osc")
local visuals = require("strudel.visuals")
local M = {}

M.config = {
  host = "127.0.0.1",
  port = 9129, -- Default Strudel Desktop OSC port
}

function M.setup(opts)
  M.is_setup = true
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  
  -- Setup dictionary for autocomplete (if setup is called)
  local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h")
  local dict_path = plugin_dir .. "/dict/strudel.dict"
  
  -- Add autocmd to set dictionary for javascript files (or specific filetype)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = {"javascript", "javascriptreact"},
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

function M.eval_line()
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_get_current_line()
  visuals.flash_line(line_num)
  visuals.set_eval_line(line_num)  -- Track for inline beat visuals
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

  local lines = vim.api.nvim_buf_get_text(0, start_row, start_col, end_row, end_col, {})
  local code = table.concat(lines, "\n")
  visuals.flash_range(start_row + 1, end_row + 1)
  visuals.set_eval_line(start_row + 1)  -- Track first line for inline beat visuals
  M.eval(code)
end

function M.eval_file()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local code = table.concat(lines, "\n")
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
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then print("[Strudel] " .. line) end
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
      print("[Strudel] Bridge stopped.")
    end,
  })
  
  if M.bridge_job_id > 0 then
    vim.notify("Strudel Bridge started!", vim.log.levels.INFO)
    -- Start beat listener automatically
    local has_listener, listener = pcall(require, "strudel.listener")
    if has_listener then
      listener.start()
    end
  else
    vim.notify("Failed to start Strudel Bridge.", vim.log.levels.ERROR)
    M.bridge_job_id = nil
  end
end

function M.stop_bridge()
  if M.bridge_job_id then
    vim.fn.jobstop(M.bridge_job_id)
    M.bridge_job_id = nil
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
