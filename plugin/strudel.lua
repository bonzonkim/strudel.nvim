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

vim.api.nvim_create_user_command("StrudelVisualToggle", function()
  local enabled = require("strudel.visual").toggle()
  vim.notify("Strudel visual effects: " .. (enabled and "ON" or "OFF"), vim.log.levels.INFO)
end, {})

-- Keybindings
vim.keymap.set("n", "<leader>se", function() strudel.eval_line() end, { desc = "Strudel Eval Line" })
vim.keymap.set("v", "<leader>se", function() strudel.eval_visual() end, { desc = "Strudel Eval Selection" })
vim.keymap.set("n", "<leader>sf", function() strudel.eval_file() end, { desc = "Strudel Eval File" })
vim.keymap.set("n", "<leader>ss", function() strudel.stop() end, { desc = "Strudel Stop" })

-- Bridge Control Keybindings
vim.keymap.set("n", "<leader>sS", function() strudel.start_bridge() end, { desc = "Strudel Start Bridge" })
vim.keymap.set("n", "<leader>sq", function() strudel.stop_bridge() end, { desc = "Strudel Stop Bridge" })
vim.keymap.set("n", "<leader>sv", function() strudel.show_window() end, { desc = "Strudel Show Window" })
vim.keymap.set("n", "<leader>sh", function() strudel.hide_window() end, { desc = "Strudel Hide Window" })
vim.keymap.set("n", "<leader>sV", function()
  local enabled = require("strudel.visual").toggle()
  vim.notify("Strudel visual effects: " .. (enabled and "ON" or "OFF"), vim.log.levels.INFO)
end, { desc = "Strudel Toggle Visual Effects" })

vim.api.nvim_create_user_command("StrudelDebug", function()
  local status, cmp = pcall(require, "cmp")
  print("--- Strudel Debug Info ---")
  print("nvim-cmp loaded: " .. tostring(status))
  
  local strudel_mod = require("strudel")
  print("Strudel module loaded: true")
  print("Strudel setup called: " .. tostring(strudel_mod.is_setup or false))
  
  -- Check dictionary path resolution
  local info = debug.getinfo(require("strudel.cmp").new().complete, "S")
  local source_path = info.source:sub(2)
  print("cmp.lua path: " .. source_path)
  
  local plugin_dir = vim.fn.fnamemodify(source_path, ":h:h:h")
  print("Resolved plugin_dir: " .. plugin_dir)
  
  local dict_path = plugin_dir .. "/dict/strudel.dict"
  print("Resolved dict_path: " .. dict_path)
  
  local f = io.open(dict_path, "r")
  if f then
    print("Dictionary file exists: YES")
    f:close()
  else
    print("Dictionary file exists: NO")
  end
  
  print("--------------------------")
end, {})
