local M = {}

-- Helper to pad string to 4-byte boundary
local function pad_string(str)
  local len = #str
  local pad = 4 - (len % 4)
  return str .. string.rep('\0', pad)
end

-- Encode an OSC message
-- Address: string (e.g., "/eval")
-- Args: list of values (currently supports strings only)
function M.encode_message(address, args)
  local osc_addr = pad_string(address)
  local type_tags = ","
  local encoded_args = ""

  for _, arg in ipairs(args) do
    if type(arg) == "string" then
      type_tags = type_tags .. "s"
      encoded_args = encoded_args .. pad_string(arg)
    else
      -- TODO: Support other types if needed (i, f, etc.)
      error("Unsupported argument type: " .. type(arg))
    end
  end

  type_tags = pad_string(type_tags)
  return osc_addr .. type_tags .. encoded_args
end

-- Send OSC message via UDP
function M.send(host, port, address, args)
  local uv = vim.uv or vim.loop
  local client = uv.new_udp()
  local msg = M.encode_message(address, args)

  client:send(msg, host, port, function(err)
    if err then
      vim.schedule(function()
        vim.notify("Strudel OSC Error: " .. err, vim.log.levels.ERROR)
      end)
    end
    client:close()
  end)
end

return M
