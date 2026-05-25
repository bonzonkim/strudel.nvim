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

local bit = require("bit")

local function fnv1a(s)
  local h = 0x811C9DC5
  for i = 1, #s do
    h = bit.bxor(h, string.byte(s, i))
    h = bit.tobit(h * 16777619)
  end
  -- Convert to unsigned 32-bit for modulo
  if h < 0 then h = h + 0x100000000 end
  return h
end

local function hsl_to_hex(h_deg, s, l)
  local function f(n)
    local k = (n + h_deg / 30) % 12
    local a = s * math.min(l, 1 - l)
    return l - a * math.max(-1, math.min(k - 3, 9 - k, 1))
  end
  local r = math.floor(f(0) * 255 + 0.5)
  local g = math.floor(f(8) * 255 + 0.5)
  local b = math.floor(f(4) * 255 + 0.5)
  return string.format("#%02x%02x%02x", r, g, b)
end

local function sanitize_hl_name(s)
  return (s:gsub("[^%w_]", "_"))
end

function M.color_for(sound)
  if M.hl_cache[sound] then
    return M.hl_cache[sound]
  end

  local hl_group = "StrudelSound_" .. sanitize_hl_name(sound)
  local color
  local override = M.color_overrides[sound]

  if type(override) == "string" and override:match("^#%x%x%x%x%x%x$") then
    color = override
  else
    if type(override) == "string" then
      vim.notify(
        "Strudel: invalid color override for '" .. sound .. "': " .. override,
        vim.log.levels.WARN
      )
    end
    local hue = fnv1a(sound) % 360
    color = hsl_to_hex(hue, 0.7, 0.55)
  end

  vim.api.nvim_set_hl(0, hl_group, { bg = color })
  M.hl_cache[sound] = hl_group
  return hl_group
end

-- Convert an absolute byte offset to (row, byte_col), both 0-indexed.
-- byte_col is a byte offset within the line (what nvim_buf_set_extmark expects).
-- Exposed as M._byte_to_pos for unit testing.
function M._byte_to_pos(bufnr, byte_offset)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if byte_offset <= 0 then return 0, 0 end

  local lo, hi = 0, line_count
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    local start = vim.api.nvim_buf_get_offset(bufnr, mid)
    if start <= byte_offset then
      lo = mid + 1
    else
      hi = mid
    end
  end

  local row = lo - 1
  if row < 0 then row = 0 end
  local row_start = vim.api.nvim_buf_get_offset(bufnr, row)
  return row, byte_offset - row_start
end

function M.set_last_eval(bufnr, offset)
  M.last_eval = { bufnr = bufnr, offset = offset or 0 }
end

local function flash(locs, sound, dur_ms)
  local bufnr = M.last_eval.bufnr
  local offset = M.last_eval.offset
  local hl_group = M.color_for(sound)

  for _, loc in ipairs(locs) do
    local from, to = loc[1], loc[2]
    if type(from) == "number" and type(to) == "number" and from >= 0 and from <= to then
      local row_from, col_from = M._byte_to_pos(bufnr, offset + from)
      local row_to, col_to = M._byte_to_pos(bufnr, offset + to)

      local ok, mark_id = pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns_id, row_from, col_from, {
        end_row = row_to,
        end_col = col_to,
        hl_group = hl_group,
        priority = 200,
      })

      if ok and mark_id then
        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            pcall(vim.api.nvim_buf_del_extmark, bufnr, M.ns_id, mark_id)
          end
        end, dur_ms)
      end
    end
  end
end

function M.handle_event(json_str)
  if not M.enabled then return end
  if not M.last_eval.bufnr then return end
  if not vim.api.nvim_buf_is_valid(M.last_eval.bufnr) then return end

  local ok, payload = pcall(vim.json.decode, json_str)
  if not ok or type(payload) ~= "table" then return end
  if type(payload.locs) ~= "table" or #payload.locs == 0 then return end

  local sound = payload.s
  if type(sound) ~= "string" then sound = "unknown" end

  local dur = tonumber(payload.dur) or 0.1
  local dur_ms = math.max(dur * 1000, 50)

  flash(payload.locs, sound, dur_ms)
end

return M
