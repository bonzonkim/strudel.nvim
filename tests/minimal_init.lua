-- Minimal init for running plenary tests in headless mode.
-- Adds plenary and this plugin to runtimepath, then requires plenary.busted.

local function add_to_rtp(path)
  vim.opt.rtp:prepend(path)
end

-- This plugin
add_to_rtp(vim.fn.getcwd())

-- Plenary: try common install locations
local plenary_paths = {
  vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/*/start/plenary.nvim",
  vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
}

for _, p in ipairs(plenary_paths) do
  for _, expanded in ipairs(vim.fn.glob(p, false, true)) do
    if vim.fn.isdirectory(expanded) == 1 then
      add_to_rtp(expanded)
    end
  end
end

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
