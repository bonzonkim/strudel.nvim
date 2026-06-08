local source = {}

-- Resolve path at module level to ensure correctness
local current_file = debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fn.fnamemodify(current_file, ":h:h:h")
local dict_path = plugin_dir .. "/dict/strudel.dict"
local docs_path = plugin_dir .. "/dict/strudel_docs.json"
local default_catalog_path = plugin_dir .. "/dict/strudel_completions.json"
local catalog_path = default_catalog_path

local items_cache = nil
local catalog_cache = nil
local notified_catalog_error = false
local available_filetypes = {
  javascript = true,
  javascriptreact = true,
  strudel = true,
  typescript = true,
  typescriptreact = true,
}

local function empty_catalog(error_message)
  return {
    version = 1,
    generated_from = {},
    entries = {},
    error = error_message,
  }
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

local function validate_catalog(catalog)
  if type(catalog) ~= "table" then
    return false, "invalid catalog"
  end
  if catalog.version ~= 1 then
    return false, "unsupported catalog version"
  end
  if type(catalog.entries) ~= "table" then
    return false, "invalid catalog entries"
  end

  local seen = {}
  local previous
  for _, entry in ipairs(catalog.entries) do
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
      return false, "invalid catalog entry label"
    end
    if seen[entry.label] then
      return false, "duplicate label: " .. entry.label
    end
    if previous and previous > entry.label then
      return false, "catalog entries must be sorted"
    end
    seen[entry.label] = true
    previous = entry.label
  end

  return true, nil
end

local function strip_html(value)
  if type(value) ~= "string" then
    return nil
  end
  local text = value:gsub("<[^>]->", "")
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&amp;", "&")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

local function render_documentation(entry)
  local doc = entry.documentation or {}
  local lines = { "**" .. entry.label .. "**" }

  local description = strip_html(doc.description)
  if description and description ~= "" then
    table.insert(lines, "")
    table.insert(lines, description)
  end

  local aliases = doc.synonyms_text
  if (not aliases or aliases == "") and type(entry.aliases) == "table" and #entry.aliases > 0 then
    aliases = table.concat(entry.aliases, ", ")
  end
  if aliases and aliases ~= "" then
    table.insert(lines, "")
    table.insert(lines, "Aliases: " .. aliases)
  end

  if type(doc.parameters) == "table" and #doc.parameters > 0 then
    table.insert(lines, "")
    table.insert(lines, "Parameters:")
    for _, param in ipairs(doc.parameters) do
      local name = param.name or "value"
      local types = ""
      if type(param.types) == "table" and #param.types > 0 then
        types = " (" .. table.concat(param.types, " | ") .. ")"
      end
      local desc = strip_html(param.description)
      if desc and desc ~= "" then
        table.insert(lines, "- " .. name .. types .. ": " .. desc)
      else
        table.insert(lines, "- " .. name .. types)
      end
    end
  end

  if type(doc.examples) == "table" and #doc.examples > 0 then
    table.insert(lines, "")
    table.insert(lines, "Examples:")
    for _, example in ipairs(doc.examples) do
      table.insert(lines, "```javascript")
      table.insert(lines, tostring(example))
      table.insert(lines, "```")
    end
  end

  return {
    kind = "markdown",
    value = table.concat(lines, "\n"),
  }
end

local function sound_context(line)
  if type(line) ~= "string" then
    return nil
  end
  local fragment = line:match('s%(%s*["\']([^"\']*)$')
  if fragment == nil then
    fragment = line:match('sound%(%s*["\']([^"\']*)$')
  end
  if fragment == nil then
    return nil
  end
  return fragment:match("([%w_]*)$") or ""
end

local function item_matches_context(item, context)
  local kind = item.data and item.data.catalog_kind
  local fragment = sound_context(context.line_before_cursor)
  if fragment ~= nil then
    if kind ~= "sound" then
      return false
    end
    if fragment == "" then
      return true
    end
    return item.label:find(fragment, 1, true) ~= nil
  end
  return kind == "function"
end

local function completion_context(params)
  params = params or {}
  local context = params.context or {}
  return {
    line_before_cursor = context.cursor_before_line or context.line_before_cursor or "",
    explicit_request = context.option and context.option.reason == "manual",
  }
end

function source._set_catalog_path(path)
  catalog_path = path or default_catalog_path
  source._reset_cache()
end

function source._reset_cache()
  items_cache = nil
  catalog_cache = nil
  notified_catalog_error = false
end

function source._load_catalog()
  if catalog_cache then
    return catalog_cache.ok, catalog_cache.catalog
  end

  local content = read_file(catalog_path)
  if not content then
    local catalog = empty_catalog("missing catalog: " .. catalog_path)
    catalog_cache = { ok = false, catalog = catalog }
    return false, catalog
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    local catalog = empty_catalog("invalid JSON catalog: " .. catalog_path)
    catalog_cache = { ok = false, catalog = catalog }
    return false, catalog
  end

  local valid, err = validate_catalog(decoded)
  if not valid then
    local catalog = empty_catalog(err)
    catalog_cache = { ok = false, catalog = catalog }
    return false, catalog
  end

  catalog_cache = { ok = true, catalog = decoded }
  return true, decoded
end

function source._catalog_status()
  local ok, catalog = source._load_catalog()
  return {
    path = catalog_path,
    ok = ok,
    entry_count = #(catalog.entries or {}),
    error = catalog.error,
  }
end

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return available_filetypes[vim.bo.filetype] == true
end

function source:get_debug_name()
  return "strudel"
end

function source:get_keyword_pattern()
  return [[\k\+]]
end

function source:complete(params, callback)
  local context = completion_context(params)

  if items_cache then
    callback(vim.tbl_filter(function(item)
      return item_matches_context(item, context)
    end, items_cache))
    return
  end

  local items = {}
  local ok, catalog = source._load_catalog()
  if not ok then
    if not notified_catalog_error then
      notified_catalog_error = true
      vim.notify("Strudel: completion catalog unavailable: " .. (catalog.error or "unknown error"), vim.log.levels.WARN)
    end
    items_cache = items
    callback(items)
    return
  end

  for _, entry in ipairs(catalog.entries) do
    table.insert(items, {
      label = entry.label,
      word = entry.insert_text or entry.label,
      filterText = entry.label,
      insertText = entry.insert_text or entry.label,
      kind = 3, -- cmp.lsp.CompletionItemKind.Function
      detail = entry.detail or "Strudel Function",
      documentation = render_documentation(entry),
      data = {
        canonical = entry.canonical,
        aliases = entry.aliases,
        catalog_kind = entry.kind,
      },
    })
  end

  items_cache = items
  callback(vim.tbl_filter(function(item)
    return item_matches_context(item, context)
  end, items_cache))
end

return source
