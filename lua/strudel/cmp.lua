local source = {}

-- Resolve path at module level to ensure correctness
local current_file = debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fn.fnamemodify(current_file, ":h:h:h")
local dict_path = plugin_dir .. "/dict/strudel.dict"
local docs_path = plugin_dir .. "/dict/strudel_docs.json"

local items_cache = nil

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return true
end

function source:get_debug_name()
  return "strudel"
end

function source:get_keyword_pattern()
  return [[\k\+]]
end

function source:complete(params, callback)
  if items_cache then
    callback(items_cache)
    return
  end

  -- Load docs
  local docs = {}
  local f_docs = io.open(docs_path, "r")
  if f_docs then
    local content = f_docs:read("*a")
    f_docs:close()
    local ok, parsed = pcall(vim.fn.json_decode, content)
    if ok then docs = parsed end
  end

  local items = {}
  local f = io.open(dict_path, "r")
  if f then
    for line in f:lines() do
      if line ~= "" then
        local item = {
          label = line,
          kind = 3, -- cmp.lsp.CompletionItemKind.Function is 3
          detail = "Strudel Function",
        }
        
        local doc_data = docs[line]
        if doc_data then
          local doc_text = "**" .. line .. "**\n\n" .. doc_data.description
          if doc_data.params and #doc_data.params > 0 then
            doc_text = doc_text .. "\n\n**Parameters:**\n- " .. table.concat(doc_data.params, "\n- ")
          end
          item.documentation = {
            kind = "markdown",
            value = doc_text
          }
        end
        
        table.insert(items, item)
      end
    end
    f:close()
  else
    vim.notify("Strudel: Could not open dictionary at " .. dict_path, vim.log.levels.ERROR)
  end

  items_cache = items
  callback(items)
end

return source
