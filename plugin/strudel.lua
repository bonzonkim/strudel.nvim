if vim.g.loaded_strudel_plugin then
  return
end
vim.g.loaded_strudel_plugin = true

local status, strudel = pcall(require, "strudel")
if not status then
  vim.notify("Failed to load strudel module: " .. strudel, vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command("StrudelEval", function(opts)
  if opts.range > 0 then
    strudel.eval_visual()
  else
    strudel.eval_line()
  end
end, { range = true })

vim.api.nvim_create_user_command("StrudelStop", function()
  strudel.stop()
end, {})

vim.api.nvim_create_user_command("StrudelEvalFile", function()
  strudel.eval_file()
end, {})

vim.api.nvim_create_user_command("StrudelStart", function()
  strudel.start_bridge()
end, {})

vim.api.nvim_create_user_command("StrudelStopBridge", function()
  strudel.stop_bridge()
end, {})

vim.api.nvim_create_user_command("StrudelShow", function()
  strudel.show_window()
end, {})

vim.api.nvim_create_user_command("StrudelHide", function()
  strudel.hide_window()
end, {})

-- Visualizer Commands
local vis_status, visualizer = pcall(require, "strudel.visualizer")
if vis_status then
  vim.api.nvim_create_user_command("StrudelVisuals", function()
    visualizer.toggle()
  end, {})

  vim.api.nvim_create_user_command("StrudelVisualsOpen", function()
    visualizer.open()
  end, {})

  vim.api.nvim_create_user_command("StrudelVisualsClose", function()
    visualizer.close()
  end, {})

  -- Keybindings
  vim.keymap.set("n", "<leader>se", function() strudel.eval_line() end, { desc = "Strudel Eval Line" })
  vim.keymap.set("v", "<leader>se", function() strudel.eval_visual() end, { desc = "Strudel Eval Selection" })
  vim.keymap.set("n", "<leader>sf", function() strudel.eval_file() end, { desc = "Strudel Eval File" })
  vim.keymap.set("n", "<leader>ss", function() strudel.stop() end, { desc = "Strudel Stop" })

  -- Bridge Control Keybindings
  vim.keymap.set("n", "<leader>sS", function() strudel.start_bridge() end, { desc = "Strudel Start Bridge" })
  vim.keymap.set("n", "<leader>sq", function() strudel.stop_bridge() end, { desc = "Strudel Stop Bridge" })
  vim.keymap.set("n", "<leader>sv", function() visualizer.toggle() end, { desc = "Strudel Toggle Visualizer" })
  vim.keymap.set("n", "<leader>sh", function() strudel.hide_window() end, { desc = "Strudel Hide Window" })
else
  vim.notify("Failed to load strudel.visualizer: " .. tostring(visualizer), vim.log.levels.WARN)
  
  -- Still set up keybindings without visualizer
  vim.keymap.set("n", "<leader>se", function() strudel.eval_line() end, { desc = "Strudel Eval Line" })
  vim.keymap.set("v", "<leader>se", function() strudel.eval_visual() end, { desc = "Strudel Eval Selection" })
  vim.keymap.set("n", "<leader>sf", function() strudel.eval_file() end, { desc = "Strudel Eval File" })
  vim.keymap.set("n", "<leader>ss", function() strudel.stop() end, { desc = "Strudel Stop" })
  vim.keymap.set("n", "<leader>sS", function() strudel.start_bridge() end, { desc = "Strudel Start Bridge" })
  vim.keymap.set("n", "<leader>sq", function() strudel.stop_bridge() end, { desc = "Strudel Stop Bridge" })
  vim.keymap.set("n", "<leader>sv", function() strudel.show_window() end, { desc = "Strudel Show Window" })
  vim.keymap.set("n", "<leader>sh", function() strudel.hide_window() end, { desc = "Strudel Hide Window" })
end

vim.api.nvim_create_user_command("StrudelDebug", function()
  print("--- Strudel Debug Info ---")
  
  local strudel_mod = require("strudel")
  print("Bridge running: " .. tostring(strudel_mod.bridge_job_id ~= nil))
  
  local has_listener, listener = pcall(require, "strudel.listener")
  print("Listener module: " .. tostring(has_listener))
  if has_listener then
    print("Listener active: " .. tostring(listener.is_listening))
    print("Current beat data: " .. tostring(listener.get_beat() ~= nil))
  end
  
  local has_visuals, visuals = pcall(require, "strudel.visuals")
  print("Visuals module: " .. tostring(has_visuals))
  if has_visuals then
    print("Inline enabled: " .. tostring(visuals.inline_enabled))
    print("Eval line: " .. tostring(visuals.eval_line or "nil"))
    print("Callbacks registered: " .. tostring(#(listener.callbacks or {})))
  end
  
  print("--------------------------")
end, {})

-- Manual commands to start listener and inline visuals
vim.api.nvim_create_user_command("StrudelListenerStart", function()
  local listener = require("strudel.listener")
  listener.start()
end, {})

vim.api.nvim_create_user_command("StrudelInline", function()
  local visuals = require("strudel.visuals")
  visuals.toggle_inline()
end, {})

-- Set current line for inline visuals
vim.api.nvim_create_user_command("StrudelInlineHere", function()
  local visuals = require("strudel.visuals")
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  visuals.set_eval_line(line_num)
  vim.notify("Inline visuals set to line " .. line_num, vim.log.levels.INFO)
end, {})

