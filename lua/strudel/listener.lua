-- Strudel Beat Event Listener
-- Receives beat data from headless-bridge via UDP

local M = {}

M.server = nil
M.is_listening = false
M.current_beat = nil
M.callbacks = {}

local LISTEN_PORT = 9130

-- Start listening for beat events
function M.start()
  if M.is_listening then return end
  
  local uv = vim.uv or vim.loop
  M.server = uv.new_udp()
  
  local ok, err = pcall(function()
    M.server:bind("127.0.0.1", LISTEN_PORT)
  end)
  
  if not ok then
    vim.notify("Strudel listener: port " .. LISTEN_PORT .. " in use", vim.log.levels.WARN)
    return
  end
  
  M.server:recv_start(function(err, data, addr, flags)
    if err then return end
    if data then
      vim.schedule(function()
        M.handle_message(data)
      end)
    end
  end)
  
  M.is_listening = true
  vim.notify("Strudel beat listener started (UDP " .. LISTEN_PORT .. ")", vim.log.levels.INFO)
end

-- Stop listening
function M.stop()
  if not M.is_listening then return end
  
  if M.server then
    pcall(function()
      M.server:recv_stop()
      M.server:close()
    end)
    M.server = nil
  end
  
  M.is_listening = false
  M.current_beat = nil
end

-- Handle incoming message
function M.handle_message(data)
  local ok, beat_data = pcall(vim.fn.json_decode, data)
  if not ok then return end
  
  M.current_beat = beat_data
  
  -- Notify all registered callbacks
  for _, callback in ipairs(M.callbacks) do
    pcall(callback, beat_data)
  end
end

-- Register a callback for beat events
function M.on_beat(callback)
  table.insert(M.callbacks, callback)
end

-- Clear all callbacks
function M.clear_callbacks()
  M.callbacks = {}
end

-- Get current beat data
function M.get_beat()
  return M.current_beat
end

return M
