describe("strudel.cmp catalog loading", function()
  local cmp_source
  local tmpdir

  local function write_file(path, content)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local fd = assert(io.open(path, "w"))
    fd:write(content)
    fd:close()
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
    local path = tmpdir .. "/catalog.json"
    write_file(path, vim.json.encode({
      version = 1,
      generated_from = { source = "test" },
      entries = {
        { label = "gain", kind = "function" },
        { label = "sound", kind = "function" },
      },
    }))

    cmp_source._set_catalog_path(path)
    local ok, catalog = cmp_source._load_catalog()

    assert.is_true(ok)
    assert.are.equal(2, #catalog.entries)
    assert.are.equal("gain", catalog.entries[1].label)
    assert.are.equal("sound", catalog.entries[2].label)
  end)

  it("loads the bundled catalog and includes note and s entries", function()
    local ok, catalog = cmp_source._load_catalog()

    assert.is_true(ok)
    assert.is_true(#catalog.entries > 0)

    local labels = {}
    for _, entry in ipairs(catalog.entries) do
      labels[entry.label] = true
    end
    assert.is_true(labels.note)
    assert.is_true(labels.s)
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

  it("rejects duplicate labels", function()
    local path = tmpdir .. "/duplicates.json"
    write_file(path, vim.json.encode({
      version = 1,
      entries = {
        { label = "sound", kind = "function" },
        { label = "sound", kind = "function" },
      },
    }))
    cmp_source._set_catalog_path(path)

    local ok, catalog = cmp_source._load_catalog()

    assert.is_false(ok)
    assert.are.equal(0, #catalog.entries)
    assert.is_truthy(catalog.error:match("duplicate label"))
  end)

  it("rejects unsorted labels", function()
    local path = tmpdir .. "/unsorted.json"
    write_file(path, vim.json.encode({
      version = 1,
      entries = {
        { label = "sound", kind = "function" },
        { label = "gain", kind = "function" },
      },
    }))
    cmp_source._set_catalog_path(path)

    local ok, catalog = cmp_source._load_catalog()

    assert.is_false(ok)
    assert.are.equal(0, #catalog.entries)
    assert.is_truthy(catalog.error:match("sorted"))
  end)

  it("cache reset forces the next load to read the updated file", function()
    local path = tmpdir .. "/catalog.json"
    write_file(path, vim.json.encode({
      version = 1,
      entries = {
        { label = "gain", kind = "function" },
      },
    }))
    cmp_source._set_catalog_path(path)

    local ok, catalog = cmp_source._load_catalog()
    assert.is_true(ok)
    assert.are.equal(1, #catalog.entries)

    write_file(path, vim.json.encode({
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

  it("reports catalog status for debug output", function()
    local path = tmpdir .. "/catalog.json"
    write_file(path, vim.json.encode({
      version = 1,
      generated_from = { source = "test" },
      entries = {
        { label = "gain", kind = "function" },
        { label = "sound", kind = "function" },
      },
    }))
    cmp_source._set_catalog_path(path)

    local status = cmp_source._catalog_status()

    assert.are.equal(path, status.path)
    assert.is_true(status.ok)
    assert.are.equal(2, status.entry_count)
  end)
end)
