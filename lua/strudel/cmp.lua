local source = {}

local current_file = debug.getinfo(1, "S").source:sub(2)
local plugin_dir = vim.fn.fnamemodify(current_file, ":h:h:h")
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
    value_catalogs = {},
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

local function json_decode(content)
  if vim.json and vim.json.decode then
    return vim.json.decode(content)
  end
  return vim.fn.json_decode(content)
end

local function validate_entry_list(entries, scope)
  if type(entries) ~= "table" then
    return false, "invalid " .. scope .. " entries"
  end

  local seen = {}
  local previous
  for _, entry in ipairs(entries) do
    if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
      return false, "invalid " .. scope .. " entry label"
    end
    if seen[entry.label] then
      return false, "duplicate " .. scope .. " label: " .. entry.label
    end
    if previous and previous > entry.label then
      return false, scope .. " entries must be sorted"
    end
    seen[entry.label] = true
    previous = entry.label
  end

  return true, nil
end

local function validate_catalog(catalog)
  if type(catalog) ~= "table" then
    return false, "invalid catalog"
  end
  if catalog.version ~= 1 then
    return false, "unsupported catalog version"
  end

  local ok, err = validate_entry_list(catalog.entries, "catalog")
  if not ok then
    return false, err
  end

  if catalog.value_catalogs ~= nil and type(catalog.value_catalogs) ~= "table" then
    return false, "invalid value_catalogs"
  end

  for family, value_catalog in pairs(catalog.value_catalogs or {}) do
    if type(value_catalog) ~= "table" then
      return false, "invalid value catalog: " .. family
    end
    ok, err = validate_entry_list(value_catalog.entries or {}, family)
    if not ok then
      return false, err
    end
  end

  return true, nil
end

local function strip_html(value)
  if type(value) ~= "string" then
    return nil
  end
  local text = value:gsub("<[^>]->", " ")
  text = text:gsub("&nbsp;", " ")
  text = text:gsub("&amp;", "&")
  text = text:gsub("&lt;", "<")
  text = text:gsub("&gt;", ">")
  text = text:gsub("&quot;", '"')
  text = text:gsub("&#39;", "'")
  text = text:gsub("%s+", " ")
  text = text:gsub("%s+([%.,%;:%!%?])", "%1")
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  return text
end

local function render_documentation(entry)
  local doc = entry.documentation or {}
  local lines = { "**" .. entry.label .. "**" }

  local parameters = doc.parameters
  if type(parameters) == "table" and #parameters > 0 then
    local names = {}
    for _, param in ipairs(parameters) do
      local name = param.name or "value"
      if param.optional or param.required == false then
        name = name .. "?"
      end
      table.insert(names, name)
    end
    table.insert(lines, "Signature: " .. entry.label .. "(" .. table.concat(names, ", ") .. ")")
  else
    table.insert(lines, "Signature: " .. entry.label .. "()")
  end

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

local function completion_context(params)
  params = params or {}
  local context = params.context or {}
  local before = context.cursor_before_line or context.line_before_cursor or ""
  local after = context.cursor_after_line or ""
  local current_line = before .. after
  local line_before_cursor = before
  local text = current_line
  local cursor_offset = #before
  local cursor_line = 0

  -- nvim-cmp supplies the current line, while the buffer is the only
  -- reliable source for lines preceding it. Use the buffer only when it
  -- agrees with the supplied line so synthetic callers remain deterministic.
  local ok, position = pcall(vim.api.nvim_win_get_cursor, 0)
  local buffer_line = ok and vim.api.nvim_get_current_line() or nil
  local line_matches_context = buffer_line == current_line
  if ok and position and not line_matches_context and after == "" and buffer_line then
    line_matches_context = buffer_line:sub(1, #before) == before and position[2] == #before
  end
  if ok and position and line_matches_context then
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if #buffer_lines > 0 then
      cursor_line = position[1] - 1
      local prefix_lines = {}
      for index = 1, cursor_line do
        table.insert(prefix_lines, buffer_lines[index])
      end
      table.insert(prefix_lines, before)
      line_before_cursor = table.concat(prefix_lines, "\n")
      text = table.concat(buffer_lines, "\n")
      cursor_offset = #line_before_cursor
    end
  end

  return {
    line_before_cursor = line_before_cursor,
    cursor_offset = cursor_offset,
    cursor_line = cursor_line,
    cursor_character = #before,
    explicit_request = context.option and context.option.reason == "manual",
  }
end

local context_families = {
  s = "sound",
  sound = "sound",
  bank = "bank",
  scale = "scale",
  mode = "mode",
  chord = "chord",
}

local function is_identifier_character(character)
  return character ~= nil and character:match("[%w_$]") ~= nil
end

local function call_name_before(text, open_position)
  local position = open_position - 1
  while position > 0 and text:sub(position, position):match("%s") do
    position = position - 1
  end
  local finish = position
  while position > 0 and is_identifier_character(text:sub(position, position)) do
    position = position - 1
  end
  if finish < position + 1 then
    return nil
  end
  return text:sub(position + 1, finish)
end

local function matching_fragment_start(value, cursor)
  local position = cursor
  while position > 0 and value:sub(position, position):match("[%w_#b+^:-]") do
    position = position - 1
  end
  return position + 1
end

-- Parse only the prefix ending at the cursor. This avoids matching function
-- text in strings/comments and naturally handles nested calls, escaped quotes,
-- multiline input, and a cursor before the end of the current line.
local function detect_value_context(text)
  if type(text) ~= "string" then
    return nil
  end

  local stack = {}
  local quote = nil
  local quote_position = nil
  local quote_call = nil
  local escaped = false
  local line_comment = false
  local block_comment = false
  local position = 1

  while position <= #text do
    local character = text:sub(position, position)
    local next_character = text:sub(position + 1, position + 1)

    if quote then
      if escaped then
        escaped = false
      elseif character == "\\" then
        escaped = true
      elseif character == quote then
        quote = nil
        quote_position = nil
        quote_call = nil
      end
      position = position + 1
    elseif line_comment then
      if character == "\n" then
        line_comment = false
      end
      position = position + 1
    elseif block_comment then
      if character == "*" and next_character == "/" then
        block_comment = false
        position = position + 2
      else
        position = position + 1
      end
    elseif character == "/" and next_character == "/" then
      line_comment = true
      position = position + 2
    elseif character == "/" and next_character == "*" then
      block_comment = true
      position = position + 2
    elseif character == '"' or character == "'" or character == "`" then
      local parent = stack[#stack]
      if parent and parent.kind == "(" and parent.direct and parent.name then
        quote = character
        quote_position = position
        quote_call = parent.name
      end
      position = position + 1
    elseif character == "(" or character == "[" or character == "{" then
      local name = character == "(" and call_name_before(text, position) or nil
      table.insert(stack, {
        kind = character,
        name = name,
        direct = character == "(" and name ~= nil,
      })
      position = position + 1
    elseif character == ")" or character == "]" or character == "}" then
      local parent = stack[#stack]
      local expected = ({ [")"] = "(", ["]"] = "[", ["}"] = "{" })[character]
      if parent and parent.kind == expected then
        table.remove(stack)
      end
      position = position + 1
    else
      if #stack > 0 and stack[#stack].kind == "(" and character:match("%S") then
        stack[#stack].direct = false
      end
      position = position + 1
    end
  end

  if quote and quote_position and quote_call then
    local family = context_families[quote_call]
    if family then
      local inside = text:sub(quote_position + 1)
      local cursor = #inside
      local fragment_start = matching_fragment_start(inside, cursor)
      local context = {
        family = family,
        fragment = inside:sub(fragment_start, cursor),
        quoted = true,
        replace_start = #text - (cursor - fragment_start + 1),
        replace_end = #text,
      }

      if family == "sound" then
        context.contains = true
      elseif family == "scale" then
        local colon = inside:match("^.*():")
        if colon and colon < #inside + 1 then
          context.family = "scale"
          context.fragment = inside:sub(math.max(fragment_start, colon + 1), cursor)
          context.replace_start = #text - #context.fragment
          context.insert_spaces_as_colons = true
        else
          context.family = "pitch"
        end
      elseif family == "mode" then
        local colon = inside:match("^.*():")
        if colon and colon < #inside + 1 then
          context.family = "pitch"
          context.fragment = inside:sub(math.max(fragment_start, colon + 1), cursor)
          context.replace_start = #text - #context.fragment
        else
          context.family = "mode"
        end
      elseif family == "chord" then
        local root = inside:match("^%s*([A-Ga-g][#b]?)")
        if root then
          local root_start = inside:find(root, 1, true)
          local root_end = root_start + #root
          context.family = "chord"
          context.fragment = inside:sub(math.max(fragment_start, root_end), cursor)
          context.replace_start = #text - #context.fragment
        else
          context.family = "pitch"
        end
      end
      return context
    end
  end

  local parent = stack[#stack]
  if parent and parent.kind == "(" and parent.direct and context_families[parent.name] then
    return {
      family = context_families[parent.name],
      fragment = "",
      quoted = false,
      replace_start = #text,
      replace_end = #text,
    }
  end

  return nil
end

local function item_from_entry(entry, default_kind)
  local insert_text = entry.insert_text
  if insert_text == nil then
    insert_text = entry.label
  end

  return {
    label = entry.label,
    word = insert_text,
    filterText = entry.label,
    insertText = insert_text,
    kind = 3,
    detail = entry.detail or "Strudel Function",
    documentation = render_documentation(entry),
    data = {
      canonical = entry.canonical,
      aliases = entry.aliases,
      catalog_kind = entry.kind or default_kind,
      tags = entry.tags,
    },
  }
end

local function matches_fragment(label, fragment, contains)
  if not fragment or fragment == "" then
    return true
  end
  local left = string.lower(label)
  local right = string.lower(fragment)
  if contains then
    return left:find(right, 1, true) ~= nil
  end
  return left:sub(1, #right) == right
end

local function offset_to_position(text, offset)
  local line = 0
  local line_start = 0
  for index = 1, offset do
    if text:sub(index, index) == "\n" then
      line = line + 1
      line_start = index
    end
  end
  return {
    line = line,
    character = offset - line_start,
  }
end

local function add_value_edit(item, text, context)
  local start_offset = context.replace_start or #text
  local end_offset = context.replace_end or #text
  item.textEdit = {
    newText = item.insertText,
    range = {
      start = offset_to_position(text, start_offset),
      ["end"] = offset_to_position(text, end_offset),
    },
  }
end

local function value_items_for_context(catalog, context, line_before_cursor)
  if not context.quoted then
    return {}
  end

  local value_catalog = (catalog.value_catalogs or {})[context.family]
  if type(value_catalog) ~= "table" then
    return {}
  end

  local candidates = {}
  for _, entry in ipairs(value_catalog.entries or {}) do
    if matches_fragment(entry.label, context.fragment, context.contains) then
      local item = item_from_entry(entry, context.family)
      if context.insert_spaces_as_colons then
        item.insertText = item.insertText:gsub("%s+", ":")
        item.word = item.insertText
      end
      add_value_edit(item, line_before_cursor, context)
      table.insert(candidates, item)
    end
  end

  table.sort(candidates, function(left, right)
    if left.label == right.label then
      return left.insertText < right.insertText
    end
    return left.label < right.label
  end)

  local items = {}
  local seen = {}
  for _, item in ipairs(candidates) do
    local key = item.insertText
    if not seen[key] then
      seen[key] = true
      table.insert(items, item)
    end
  end
  return items
end

local function build_items(catalog)
  local items = {}
  for _, entry in ipairs(catalog.entries or {}) do
    table.insert(items, item_from_entry(entry, "function"))
  end
  return items
end

local function catalog_labels(catalog)
  local labels = {}
  for _, entry in ipairs(catalog.entries or {}) do
    labels[entry.label] = true
  end
  return labels
end

local function value_family_status(catalog)
  local status = {}
  for _, family in ipairs({ "sound", "bank", "pitch", "scale", "mode", "chord" }) do
    local value_catalog = (catalog.value_catalogs or {})[family]
    status[family] = {
      available = type(value_catalog) == "table" and type(value_catalog.entries) == "table" and #value_catalog.entries > 0,
      count = type(value_catalog) == "table" and type(value_catalog.entries) == "table" and #value_catalog.entries or 0,
      source = type(value_catalog) == "table" and value_catalog.availability or "missing",
    }
  end
  return status
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

  local ok, decoded = pcall(json_decode, content)
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
  local labels = catalog_labels(catalog)
  return {
    path = catalog_path,
    ok = ok,
    entry_count = #(catalog.entries or {}),
    error = catalog.error,
    samples = {
      note = labels.note == true,
      s = labels.s == true,
      sound = labels.sound == true,
    },
    value_catalogs = value_family_status(catalog),
  }
end

function source._is_filetype_available(filetype)
  return available_filetypes[filetype or vim.bo.filetype] == true
end

function source._diagnostic_report(cmp_loaded, filetype)
  local status = source._catalog_status()
  local ft = filetype or vim.bo.filetype
  local eligible = source._is_filetype_available(ft)
  local next_action = "Completion catalog is ready."

  if not cmp_loaded then
    next_action = "Install and configure nvim-cmp, then add source { name = 'strudel' }."
  elseif not eligible then
    next_action = "Open a Strudel-relevant filetype or set filetype to javascript/typescript/strudel."
  elseif not status.ok then
    next_action = "Regenerate dict/strudel_completions.json with dict/generate_completions.js."
  elseif not (status.samples.note and status.samples.s and status.samples.sound) then
    next_action = "Refresh the catalog from upstream Strudel doc.json; representative entries are missing."
  end

  return {
    source_name = "strudel",
    cmp_loaded = cmp_loaded == true,
    filetype = ft,
    filetype_eligible = eligible,
    catalog = status,
    next_action = next_action,
  }
end

function source._diagnostic_lines(cmp_loaded, filetype)
  local report = source._diagnostic_report(cmp_loaded, filetype)
  local lines = {
    "--- Strudel Debug Info ---",
    "nvim-cmp loaded: " .. tostring(report.cmp_loaded),
    "source name: " .. report.source_name,
    "current filetype: " .. tostring(report.filetype),
    "filetype eligible: " .. tostring(report.filetype_eligible),
    "catalog path: " .. report.catalog.path,
    "catalog ok: " .. tostring(report.catalog.ok),
    "catalog entry count: " .. tostring(report.catalog.entry_count),
  }

  if report.catalog.error then
    table.insert(lines, "catalog error: " .. report.catalog.error)
  end

  table.insert(lines, "sample note: " .. tostring(report.catalog.samples.note))
  table.insert(lines, "sample s: " .. tostring(report.catalog.samples.s))
  table.insert(lines, "sample sound: " .. tostring(report.catalog.samples.sound))

  for _, family in ipairs({ "sound", "bank", "pitch", "scale", "mode", "chord" }) do
    local value = report.catalog.value_catalogs[family]
    table.insert(lines, string.format(
      "value %s: available=%s count=%d source=%s",
      family,
      tostring(value.available),
      value.count,
      value.source
    ))
  end

  table.insert(lines, "next action: " .. report.next_action)
  table.insert(lines, "--------------------------")
  return lines
end

function source.new()
  return setmetatable({}, { __index = source })
end

function source:is_available()
  return source._is_filetype_available()
end

function source:get_debug_name()
  return "strudel"
end

function source:get_keyword_pattern()
  return [[\k\+]]
end

function source:complete(params, callback)
  local context = completion_context(params)
  local ok, catalog = source._load_catalog()

  if not ok then
    if not notified_catalog_error then
      notified_catalog_error = true
      vim.notify("Strudel: completion catalog unavailable: " .. (catalog.error or "unknown error"), vim.log.levels.WARN)
    end
    callback({})
    return
  end

  local value_context = detect_value_context(context.line_before_cursor)
  if value_context then
    callback(value_items_for_context(catalog, value_context, context.line_before_cursor))
    return
  end

  if not items_cache then
    items_cache = build_items(catalog)
  end
  callback(items_cache)
end

return source
