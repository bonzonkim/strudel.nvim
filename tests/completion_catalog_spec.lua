describe("strudel.cmp catalog loading", function()
  local cmp_source
  local tmpdir

  local function encode(value)
    if vim.json and vim.json.encode then
      return vim.json.encode(value)
    end
    return vim.fn.json_encode(value)
  end

  local function write_file(path, content)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = assert(io.open(path, "w"))
    fd:write(content)
    fd:close()
  end

  local function write_catalog(catalog)
    local path = tmpdir .. "/catalog.json"
    write_file(path, encode(catalog))
    cmp_source._set_catalog_path(path)
    return path
  end

  before_each(function()
    package.loaded["strudel.cmp"] = nil
    cmp_source = require("strudel.cmp")
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  after_each(function()
    if cmp_source._set_catalog_path then
      cmp_source._set_catalog_path(nil)
    end
    if cmp_source._reset_cache then
      cmp_source._reset_cache()
    end
    vim.fn.delete(tmpdir, "rf")
  end)

  it("loads a valid catalog and returns sorted entries", function()
    write_catalog({
      version = 1,
      generated_from = { source = "test" },
      entries = {
        { label = "gain", kind = "function" },
        { label = "sound", kind = "function" },
      },
    })

    local ok, catalog = cmp_source._load_catalog()

    assert.is_true(ok)
    assert.are.equal(2, #catalog.entries)
    assert.are.equal("gain", catalog.entries[1].label)
    assert.are.equal("sound", catalog.entries[2].label)
  end)

  it("loads the bundled catalog and includes note s and sound entries", function()
    local ok, catalog = cmp_source._load_catalog()

    assert.is_true(ok)
    assert.is_true(#catalog.entries > 0)

    local labels = {}
    for _, entry in ipairs(catalog.entries) do
      labels[entry.label] = true
    end
    assert.is_true(labels.note)
    assert.is_true(labels.s)
    assert.is_true(labels.sound)
  end)

  it("returns an empty catalog for a missing file", function()
    cmp_source._set_catalog_path(tmpdir .. "/missing.json")

    local ok, catalog = cmp_source._load_catalog()

    assert.is_false(ok)
    assert.are.equal(0, #catalog.entries)
    assert.is_truthy(catalog.error:match("missing"))
  end)

  it("returns an empty catalog for invalid JSON", function()
    local path = tmpdir .. "/broken.json"
    write_file(path, "{")
    cmp_source._set_catalog_path(path)

    local ok, catalog = cmp_source._load_catalog()

    assert.is_false(ok)
    assert.are.equal(0, #catalog.entries)
    assert.is_truthy(catalog.error:match("invalid JSON"))
  end)

  it("rejects unsupported schema versions", function()
    write_catalog({
      version = 99,
      entries = {},
    })

    local ok, catalog = cmp_source._load_catalog()

    assert.is_false(ok)
    assert.is_truthy(catalog.error:match("unsupported"))
  end)

  it("rejects duplicate labels", function()
    write_catalog({
      version = 1,
      entries = {
        { label = "sound", kind = "function" },
        { label = "sound", kind = "function" },
      },
    })

    local ok, catalog = cmp_source._load_catalog()

    assert.is_false(ok)
    assert.are.equal(0, #catalog.entries)
    assert.is_truthy(catalog.error:match("duplicate"))
  end)

  it("rejects unsorted labels", function()
    write_catalog({
      version = 1,
      entries = {
        { label = "sound", kind = "function" },
        { label = "gain", kind = "function" },
      },
    })

    local ok, catalog = cmp_source._load_catalog()

    assert.is_false(ok)
    assert.are.equal(0, #catalog.entries)
    assert.is_truthy(catalog.error:match("sorted"))
  end)

  it("cache reset forces the next load to read the updated file", function()
    local path = write_catalog({
      version = 1,
      entries = {
        { label = "gain", kind = "function" },
      },
    })

    local ok, catalog = cmp_source._load_catalog()
    assert.is_true(ok)
    assert.are.equal(1, #catalog.entries)

    write_file(path, encode({
      version = 1,
      entries = {
        { label = "gain", kind = "function" },
        { label = "sound", kind = "function" },
      },
    }))

    local _, cached = cmp_source._load_catalog()
    assert.are.equal(1, #cached.entries)

    cmp_source._reset_cache()
    local _, reloaded = cmp_source._load_catalog()
    assert.are.equal(2, #reloaded.entries)
  end)

  it("reports representative entries and value family availability", function()
    local path = write_catalog({
      version = 1,
      generated_from = { source = "test" },
      entries = {
        { label = "note", kind = "function" },
        { label = "s", kind = "function" },
        { label = "sound", kind = "function" },
      },
      value_catalogs = {
        sound = { availability = "generated", entries = { { label = "bd", kind = "sound" } } },
        bank = { availability = "generated", entries = { { label = "tr909", kind = "bank" } } },
        pitch = { availability = "bundled", entries = { { label = "C", kind = "pitch" } } },
        scale = { availability = "bundled", entries = { { label = "minor", kind = "scale" } } },
        mode = { availability = "bundled", entries = { { label = "below", kind = "mode" } } },
        chord = { availability = "bundled", entries = { { label = "m7", kind = "chord" } } },
      },
    })

    local status = cmp_source._catalog_status()

    assert.are.equal(path, status.path)
    assert.is_true(status.ok)
    assert.are.equal(3, status.entry_count)
    assert.is_true(status.samples.note)
    assert.is_true(status.samples.s)
    assert.is_true(status.samples.sound)
    assert.is_true(status.value_catalogs.sound.available)
    assert.are.equal(1, status.value_catalogs.chord.count)
  end)
end)
