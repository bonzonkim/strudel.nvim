-- Minimal init for running plenary tests in headless mode.

local function add_to_rtp(path)
  vim.opt.rtp:prepend(path)
end

add_to_rtp(vim.fn.getcwd())
vim.g.did_load_ftplugin = 1
vim.cmd("filetype plugin indent off")

local plenary_paths = {
  vim.fn.stdpath("data") .. "/lazy/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim",
  vim.fn.stdpath("data") .. "/site/pack/*/start/plenary.nvim",
  vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
}

for _, pattern in ipairs(plenary_paths) do
  for _, expanded in ipairs(vim.fn.glob(pattern, false, true)) do
    if vim.fn.isdirectory(expanded) == 1 then
      add_to_rtp(expanded)
    end
  end
end

vim.cmd("runtime plugin/plenary.vim")
require("plenary.busted")
