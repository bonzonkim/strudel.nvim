describe("strudel.cmp source completion", function()
  local cmp_source
  local tmpdir
  local bufnr

  local function write_catalog(entries)
    local path = tmpdir .. "/catalog.json"
    local fd = assert(io.open(path, "w"))
    fd:write(vim.json.encode({
      version = 1,
      generated_from = { source = "test" },
      entries = entries,
    }))
    fd:close()
    cmp_source._set_catalog_path(path)
    return path
  end

  local function complete_items(params)
    local source = cmp_source.new()
    local calls = 0
    local received

    source:complete(params or {}, function(items)
      calls = calls + 1
      received = items
    end)

    return received, calls
  end

  before_each(function()
    package.loaded["strudel.cmp"] = nil
    cmp_source = require("strudel.cmp")
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
  end)

  after_each(function()
    if cmp_source._set_catalog_path then
      cmp_source._set_catalog_path(nil)
    end
    if cmp_source._reset_cache then
      cmp_source._reset_cache()
    end
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    vim.fn.delete(tmpdir, "rf")
  end)

  it("returns canonical and alias labels from the bundled catalog", function()
    write_catalog({
      {
        label = "s",
        insert_text = "s",
        kind = "function",
        detail = "Strudel Function",
        canonical = "sound",
      },
      {
        label = "sound",
        insert_text = "sound",
        kind = "function",
        detail = "Strudel Function",
        aliases = { "s" },
      },
    })

    local items = complete_items()
    local labels = vim.tbl_map(function(item) return item.label end, items)

    assert.are.same({ "s", "sound" }, labels)
  end)

  it("uses the selected label as exact insert text", function()
    write_catalog({
      {
        label = "s",
        insert_text = "s",
        kind = "function",
        detail = "Strudel Function",
        canonical = "sound",
      },
    })

    local items = complete_items()

    assert.are.equal("s", items[1].label)
    assert.are.equal("s", items[1].insertText)
  end)

  it("calls the completion callback exactly once", function()
    write_catalog({
      { label = "sound", kind = "function" },
    })

    local _, calls = complete_items()

    assert.are.equal(1, calls)
  end)

  it("is available in javascript buffers", function()
    vim.bo[bufnr].filetype = "javascript"
    assert.is_true(cmp_source.new():is_available())
  end)

  it("is available in javascriptreact buffers", function()
    vim.bo[bufnr].filetype = "javascriptreact"
    assert.is_true(cmp_source.new():is_available())
  end)

  it("is available in typescript buffers", function()
    vim.bo[bufnr].filetype = "typescript"
    assert.is_true(cmp_source.new():is_available())
  end)

  it("is available in typescriptreact buffers", function()
    vim.bo[bufnr].filetype = "typescriptreact"
    assert.is_true(cmp_source.new():is_available())
  end)

  it("is available in strudel buffers", function()
    vim.bo[bufnr].filetype = "strudel"
    assert.is_true(cmp_source.new():is_available())
  end)

  it("is unavailable in unrelated buffers", function()
    vim.bo[bufnr].filetype = "strudelunrelated"
    assert.is_false(cmp_source.new():is_available())
  end)

  it("sets cmp word and filterText for note and s labels", function()
    write_catalog({
      {
        label = "note",
        insert_text = "note",
        kind = "function",
        detail = "Strudel Function",
      },
      {
        label = "s",
        insert_text = "s",
        kind = "function",
        detail = "Strudel Function",
      },
    })

    local items = complete_items()
    local by_label = {}
    for _, item in ipairs(items) do
      by_label[item.label] = item
    end

    assert.are.equal("note", by_label.note.word)
    assert.are.equal("note", by_label.note.filterText)
    assert.are.equal("s", by_label.s.word)
    assert.are.equal("s", by_label.s.filterText)
  end)

  it("renders markdown documentation with description aliases parameters and examples", function()
    write_catalog({
      {
        label = "sound",
        kind = "function",
        detail = "Strudel Function",
        aliases = { "s" },
        documentation = {
          description = "Set the sound name.",
          synonyms_text = "s",
          parameters = {
            {
              name = "name",
              types = { "string" },
              description = "Sound name or mini-notation pattern.",
            },
          },
          examples = { 'sound("bd sd")' },
        },
      },
    })

    local items = complete_items()
    local doc = items[1].documentation

    assert.are.equal("markdown", doc.kind)
    assert.is_truthy(doc.value:match("%*%*sound%*%*"))
    assert.is_truthy(doc.value:match("Set the sound name%."))
    assert.is_truthy(doc.value:match("Aliases:%s+s"))
    assert.is_truthy(doc.value:match("Parameters"))
    assert.is_truthy(doc.value:match("name %(string%)"))
    assert.is_truthy(doc.value:match("Sound name or mini%-notation pattern%."))
    assert.is_truthy(doc.value:match("Examples"))
    assert.is_truthy(doc.value:match('sound%("bd sd"%)'))
  end)

  it("omits empty documentation sections", function()
    write_catalog({
      {
        label = "minimal",
        kind = "function",
        documentation = {},
      },
    })

    local items = complete_items()
    local doc = items[1].documentation

    assert.are.equal("**minimal**", doc.value)
    assert.is_nil(doc.value:match("Parameters"))
    assert.is_nil(doc.value:match("Examples"))
    assert.is_nil(doc.value:match("Aliases"))
  end)

  it("strips html from descriptions and parameter descriptions", function()
    write_catalog({
      {
        label = "gain",
        kind = "function",
        documentation = {
          description = "<p>Set <strong>gain</strong>.</p>",
          parameters = {
            {
              name = "value",
              types = { "number" },
              description = "<em>Gain</em> amount.",
            },
          },
        },
      },
    })

    local items = complete_items()
    local value = items[1].documentation.value

    assert.is_truthy(value:match("Set gain%."))
    assert.is_truthy(value:match("Gain amount%."))
    assert.is_nil(value:match("<strong>"))
    assert.is_nil(value:match("<em>"))
  end)

  it("detects sound context inside s string arguments", function()
    write_catalog({
      { label = "bd", kind = "sound", detail = "Strudel Sound" },
      { label = "sound", kind = "function", detail = "Strudel Function" },
    })

    local items = complete_items({
      context = {
        cursor_before_line = 's("b',
      },
    })

    assert.are.equal(1, #items)
    assert.are.equal("bd", items[1].label)
  end)

  it("detects sound context inside sound string arguments", function()
    write_catalog({
      { label = "bd", kind = "sound", detail = "Strudel Sound" },
      { label = "sound", kind = "function", detail = "Strudel Function" },
    })

    local items = complete_items({
      context = {
        cursor_before_line = 'sound("b',
      },
    })

    assert.are.equal(1, #items)
    assert.are.equal("bd", items[1].label)
  end)

  it("does not use sound context outside string arguments", function()
    write_catalog({
      { label = "bd", kind = "sound", detail = "Strudel Sound" },
      { label = "sound", kind = "function", detail = "Strudel Function" },
    })

    local items = complete_items({
      context = {
        cursor_before_line = "s(",
      },
    })
    local labels = vim.tbl_map(function(item) return item.label end, items)

    assert.are.same({ "sound" }, labels)
  end)

  it("falls back to function completions outside recognized value contexts", function()
    write_catalog({
      { label = "bd", kind = "sound", detail = "Strudel Sound" },
      { label = "gain", kind = "function", detail = "Strudel Function" },
      { label = "sound", kind = "function", detail = "Strudel Function" },
    })

    local items = complete_items({
      context = {
        cursor_before_line = "ga",
      },
    })
    local labels = vim.tbl_map(function(item) return item.label end, items)

    assert.are.same({ "gain", "sound" }, labels)
  end)

  it("serves cached completion requests under 100ms", function()
    local entries = {}
    for i = 1, 500 do
      table.insert(entries, {
        label = string.format("fn%03d", i),
        kind = "function",
        detail = "Strudel Function",
      })
    end
    write_catalog(entries)

    complete_items()

    local start = vim.uv.hrtime()
    local items = complete_items()
    local elapsed_ms = (vim.uv.hrtime() - start) / 1000000

    assert.are.equal(500, #items)
    assert.is_true(elapsed_ms < 100)
  end)
end)
