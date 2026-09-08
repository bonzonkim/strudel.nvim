describe("strudel.cmp source completion", function()
  local cmp_source
  local tmpdir
  local bufnr

  local function encode(value)
    if vim.json and vim.json.encode then
      return vim.json.encode(value)
    end
    return vim.fn.json_encode(value)
  end

  local function write_catalog(entries, value_catalogs)
    local path = tmpdir .. "/catalog.json"
    local fd = assert(io.open(path, "w"))
    fd:write(encode({
      version = 1,
      generated_from = { source = "test" },
      entries = entries,
      value_catalogs = value_catalogs or {},
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

  local function labels(items)
    return vim.tbl_map(function(item)
      return item.label
    end, items)
  end

  local value_catalogs = {
    sound = {
      availability = "generated",
      entries = {
        { label = "bd", insert_text = "bd", kind = "sound", detail = "Strudel sound" },
        { label = "hh", insert_text = "hh", kind = "sound", detail = "Strudel sound" },
        { label = "rim", insert_text = "rim", kind = "sound", detail = "Strudel sound" },
      },
    },
    bank = {
      availability = "generated",
      entries = {
        { label = "RolandTR909", insert_text = "RolandTR909", kind = "bank", detail = "Strudel bank" },
        { label = "tr808", insert_text = "tr808", kind = "bank", detail = "Strudel bank" },
      },
    },
    pitch = {
      availability = "bundled",
      entries = {
        { label = "C", insert_text = "C", kind = "pitch", detail = "Strudel pitch" },
        { label = "D", insert_text = "D", kind = "pitch", detail = "Strudel pitch" },
      },
    },
    scale = {
      availability = "bundled",
      entries = {
        { label = "major", insert_text = "major", kind = "scale", detail = "Strudel scale" },
        { label = "minor", insert_text = "minor", kind = "scale", detail = "Strudel scale" },
      },
    },
    mode = {
      availability = "bundled",
      entries = {
        { label = "above", insert_text = "above", kind = "mode", detail = "Strudel mode" },
        { label = "below", insert_text = "below", kind = "mode", detail = "Strudel mode" },
      },
    },
    chord = {
      availability = "bundled",
      entries = {
        { label = "7", insert_text = "7", kind = "chord", detail = "Strudel chord" },
        { label = "m7", insert_text = "m7", kind = "chord", detail = "Strudel chord" },
      },
    },
  }

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
      { label = "s", insert_text = "s", kind = "function", detail = "Strudel Function", aliases = { "sound" } },
      { label = "sound", insert_text = "sound", kind = "function", detail = "Strudel Function", canonical = "s" },
    })

    local items = complete_items()

    assert.are.same({ "s", "sound" }, labels(items))
  end)

  it("uses exact insert text word and filterText", function()
    write_catalog({
      { label = "note", insert_text = "note", kind = "function", detail = "Strudel Function" },
      { label = "s", insert_text = "s", kind = "function", detail = "Strudel Function" },
    })

    local items = complete_items()
    local by_label = {}
    for _, item in ipairs(items) do
      by_label[item.label] = item
    end

    assert.are.equal("note", by_label.note.word)
    assert.are.equal("note", by_label.note.filterText)
    assert.are.equal("s", by_label.s.word)
    assert.are.equal("s", by_label.s.insertText)
  end)

  it("calls the completion callback exactly once", function()
    write_catalog({
      { label = "sound", kind = "function" },
    })

    local _, calls = complete_items()

    assert.are.equal(1, calls)
  end)

  it("is available only in Strudel-oriented filetypes", function()
    for _, filetype in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact", "strudel" }) do
      vim.bo[bufnr].filetype = filetype
      assert.is_true(cmp_source.new():is_available())
    end

    vim.bo[bufnr].filetype = "lua"
    assert.is_false(cmp_source.new():is_available())
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
    assert.is_truthy(doc.value:match("Signature:%s+sound%(name%)"))
    assert.is_truthy(doc.value:match("Set the sound name%."))
    assert.is_truthy(doc.value:match("Aliases:%s+s"))
    assert.is_truthy(doc.value:match("Parameters"))
    assert.is_truthy(doc.value:match("name %(string%)"))
    assert.is_truthy(doc.value:match("Examples"))
    assert.is_truthy(doc.value:match('sound%("bd sd"%)'))
  end)

  it("omits empty documentation sections and strips html while preserving non-ascii", function()
    write_catalog({
      {
        label = "gain",
        kind = "function",
        documentation = {
          description = "<p>Set <strong>gain</strong>. 한글</p>",
          parameters = {
            { name = "value", types = { "number" }, description = "<em>Gain</em> amount." },
          },
        },
      },
      { label = "minimal", kind = "function", documentation = {} },
    })

    local items = complete_items()
    assert.is_truthy(items[1].documentation.value:match("Set gain%. 한글"))
    assert.is_truthy(items[1].documentation.value:match("Gain amount%."))
    assert.is_nil(items[1].documentation.value:match("<strong>"))
    assert.are.equal("**minimal**\nSignature: minimal()", items[2].documentation.value)
  end)

  it("returns sound suggestions inside quoted s and sound contexts", function()
    write_catalog({
      { label = "sound", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = 's("b' } })
    assert.are.same({ "bd" }, labels(items))

    items = complete_items({ context = { cursor_before_line = 'sound("i' } })
    assert.are.same({ "rim" }, labels(items))
  end)

  it("suppresses misleading generic suggestions in unquoted sound contexts", function()
    write_catalog({
      { label = "sound", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = "s(" } })

    assert.are.same({}, labels(items))
  end)

  it("returns bank suggestions only inside quoted bank contexts", function()
    write_catalog({
      { label = "bank", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = 'bank("Ro' } })
    assert.are.same({ "RolandTR909" }, labels(items))

    items = complete_items({ context = { cursor_before_line = "bank(" } })
    assert.are.same({}, labels(items))
  end)

  it("returns pitch before scale separator and scale after separator", function()
    write_catalog({
      { label = "scale", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = 'scale("C' } })
    assert.are.same({ "C" }, labels(items))

    items = complete_items({ context = { cursor_before_line = 'scale("C:mi' } })
    assert.are.same({ "minor" }, labels(items))
  end)

  it("returns mode before mode separator and pitch after separator", function()
    write_catalog({
      { label = "mode", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = 'mode("be' } })
    assert.are.same({ "below" }, labels(items))

    items = complete_items({ context = { cursor_before_line = 'mode("below:C' } })
    assert.are.same({ "C" }, labels(items))
  end)

  it("returns pitch roots then chord symbols inside chord contexts", function()
    write_catalog({
      { label = "chord", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = 'chord("' } })
    assert.are.same({ "C", "D" }, labels(items))

    items = complete_items({ context = { cursor_before_line = 'chord("Cm' } })
    assert.are.same({ "m7" }, labels(items))
  end)

  it("detects the innermost quoted call across nested and multiline input", function()
    write_catalog({
      { label = "sound", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      'const unrelated = "s(\\"not a call"';
      "outer(",
      '  sound("i',
    })
    vim.api.nvim_win_set_cursor(0, { 3, 11 })

    local items = complete_items({ context = { cursor_before_line = '  sound("i', cursor_after_line = 'gnore")' } })
    assert.are.same({ "rim" }, labels(items))
  end)

  it("does not detect a call-shaped fragment inside an escaped string", function()
    write_catalog({
      { label = "sound", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = [[const text = "s(\"b]] } })
    assert.are.same({ "sound" }, labels(items))
  end)

  it("uses a cursor-local replacement range for scale mode and chord suffixes", function()
    write_catalog({
      { label = "scale", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = 'scale("C:mi', cursor_after_line = 'nor")' } })
    assert.are.same({ "minor" }, labels(items))
    assert.are.equal("minor", items[1].word)
    assert.are.same({ line = 0, character = 9 }, items[1].textEdit.range.start)
    assert.are.same({ line = 0, character = 11 }, items[1].textEdit.range["end"])

    items = complete_items({ context = { cursor_before_line = 'mode("below:C', cursor_after_line = '")' } })
    assert.are.same({ "C" }, labels(items))
    assert.are.same({ line = 0, character = 12 }, items[1].textEdit.range.start)
    assert.are.same({ line = 0, character = 13 }, items[1].textEdit.range["end"])

    items = complete_items({ context = { cursor_before_line = 'chord("Cm', cursor_after_line = '")' } })
    assert.are.same({ "m7" }, labels(items))
    assert.are.same({ line = 0, character = 8 }, items[1].textEdit.range.start)
    assert.are.same({ line = 0, character = 9 }, items[1].textEdit.range["end"])
  end)

  it("deduplicates transformed values and keeps their order deterministic", function()
    write_catalog({
      { label = "scale", kind = "function", detail = "Strudel Function" },
    }, vim.tbl_deep_extend("force", value_catalogs, {
      scale = {
        availability = "bundled",
        entries = {
          { label = "major", insert_text = "major", kind = "scale" },
          { label = "minor scale", insert_text = "minor scale", kind = "scale" },
          { label = "minor:scale", insert_text = "minor:scale", kind = "scale" },
        },
      },
    }))

    local items = complete_items({ context = { cursor_before_line = 'scale("C:' } })
    assert.are.same({ "major", "minor scale" }, labels(items))
    assert.are.equal("minor:scale", items[2].insertText)
  end)

  it("falls back to function completions outside recognized value contexts", function()
    write_catalog({
      { label = "gain", kind = "function", detail = "Strudel Function" },
      { label = "sound", kind = "function", detail = "Strudel Function" },
    }, value_catalogs)

    local items = complete_items({ context = { cursor_before_line = "ga" } })

    assert.are.same({ "gain", "sound" }, labels(items))
  end)

  it("reports debug lines with catalog path samples value families errors and next action", function()
    write_catalog({
      { label = "note", kind = "function" },
      { label = "s", kind = "function" },
      { label = "sound", kind = "function" },
    }, value_catalogs)

    local lines = table.concat(cmp_source._diagnostic_lines(true, "javascript"), "\n")

    assert.is_truthy(lines:match("catalog path:"))
    assert.is_truthy(lines:match("catalog ok: true"))
    assert.is_truthy(lines:match("sample note: true"))
    assert.is_truthy(lines:match("value sound: available=true"))
    assert.is_truthy(lines:match("next action: Completion catalog is ready%."))
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

    local hrtime = (vim.uv or vim.loop).hrtime
    local start = hrtime()
    local items = complete_items()
    local elapsed_ms = (hrtime() - start) / 1000000

    assert.are.equal(500, #items)
    assert.is_true(elapsed_ms < 100)
  end)
end)
