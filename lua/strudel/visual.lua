local M = {}

M.ns_id = vim.api.nvim_create_namespace("strudel_visual")
M.enabled = true
M.color_overrides = {}
M.hl_cache = {}
M.last_eval = { bufnr = nil, offset = 0 }

function M.setup(opts)
  opts = opts or {}
  if opts.enabled ~= nil then
    M.enabled = opts.enabled
  else
    M.enabled = true
  end
  M.color_overrides = opts.colors or {}
  M.hl_cache = {}
  M.last_eval = { bufnr = nil, offset = 0 }
end

return M
