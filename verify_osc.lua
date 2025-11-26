local uv = vim.uv or vim.loop
local server = uv.new_udp()
local host = "127.0.0.1"
local port = 9129

server:bind(host, port)
print("Listening for OSC on " .. host .. ":" .. port)

server:recv_start(function(err, chunk, addr, flags)
  if err then
    print("Error: " .. err)
  elseif chunk then
    print("Received " .. #chunk .. " bytes from " .. addr.ip .. ":" .. addr.port)
    -- Simple check for OSC address
    if chunk:sub(1, 5) == "/eval" then
      print("OSC Address: /eval")
      -- Find the string argument (skip address and type tags)
      -- Address is padded to 4 bytes, "/eval" + 3 nulls = 8 bytes
      -- Type tag string "," + "s" + 2 nulls = 4 bytes
      -- Total header = 12 bytes
      local code = chunk:sub(13)
      -- Remove null padding
      code = code:gsub("%z+$", "")
      print("Code: " .. code)
      server:close()
      vim.schedule(function()
        vim.cmd("q")
      end)
    else
      print("Unknown OSC message")
    end
  end
end)

vim.defer_fn(function()
  print("Timeout waiting for OSC")
  server:close()
  vim.cmd("q")
end, 5000)
