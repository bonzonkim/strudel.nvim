const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const generator = path.join(root, 'dict', 'generate_completions.js');
const fixture = path.join(root, 'tests', 'fixtures', 'strudel_doc_fixture.json');

function runGenerator(outDir, docJson = fixture) {
  execFileSync(process.execPath, [generator, '--doc-json', docJson, '--out-dir', outDir], {
    cwd: root,
    stdio: 'pipe',
  });
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function withTempDir(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'strudel-completions-'));
  try {
    return fn(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function test(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`not ok - ${name}`);
    console.error(err.stack || err.message);
    process.exitCode = 1;
  }
}

test('generates canonical entries aliases and excludes hidden upstream docs', () => {
  withTempDir((dir) => {
    runGenerator(dir);
    const catalog = readJson(path.join(dir, 'strudel_completions.json'));
    const labels = catalog.entries.map((entry) => entry.label);

    assert.strictEqual(catalog.version, 1);
    assert(labels.includes('s'));
    assert(labels.includes('sound'));
    assert(labels.includes('note'));
    assert(labels.includes('gain'));
    assert(labels.includes('amp'));
    assert(labels.includes('volume'));
    assert(labels.includes('slow'));
    assert(labels.includes('slowcat'));
    assert(labels.includes('minimal'));
    assert(!labels.includes('_internal'));
    assert(!labels.includes('packageEntry'));
    assert(!labels.includes('hidden'));
    assert(!labels.includes('superOnly'));
  });
});

test('generates sorted duplicate-free output with first duplicate retained', () => {
  withTempDir((dir) => {
    runGenerator(dir);
    const catalog = readJson(path.join(dir, 'strudel_completions.json'));
    const labels = catalog.entries.map((entry) => entry.label);
    const sorted = [...labels].sort();

    assert.deepStrictEqual(labels, sorted);
    assert.strictEqual(new Set(labels).size, labels.length);

    const duplicate = catalog.entries.find((entry) => entry.label === 'duplicate');
    assert.strictEqual(duplicate.documentation.description, 'First duplicate wins.');
    assert(labels.includes('dupAlias'));

    const sEntry = catalog.entries.find((entry) => entry.label === 's');
    assert.strictEqual(sEntry.canonical, undefined);
  });
});

test('sorts labels with the same bytewise order used by Lua validation', () => {
  withTempDir((dir) => {
    const docJson = path.join(dir, 'case-doc.json');
    fs.writeFileSync(docJson, JSON.stringify({
      docs: [
        { name: 'absoluteOrientationZ', kind: 'function' },
        { name: 'absOriA', kind: 'function' },
      ],
    }));

    runGenerator(dir, docJson);
    const catalog = readJson(path.join(dir, 'strudel_completions.json'));
    assert.deepStrictEqual(catalog.entries.map((entry) => entry.label), ['absOriA', 'absoluteOrientationZ']);
  });
});

test('normalizes documentation parameters examples and html', () => {
  withTempDir((dir) => {
    runGenerator(dir);
    const catalog = readJson(path.join(dir, 'strudel_completions.json'));
    const gain = catalog.entries.find((entry) => entry.label === 'gain');

    assert.strictEqual(gain.documentation.description, 'Set output gain.');
    assert.deepStrictEqual(gain.documentation.parameters[0].types, ['number', 'Pattern']);
    assert.strictEqual(gain.documentation.parameters[0].description, 'Gain value.');
    assert.deepStrictEqual(gain.documentation.examples, ['s("bd").gain(0.8)']);
  });
});

test('preserves upstream synonym text instead of recomputing it per alias', () => {
  withTempDir((dir) => {
    runGenerator(dir);
    const catalog = readJson(path.join(dir, 'strudel_completions.json'));
    const expected = 'ftrans, fTrans, ftranspose, fTranspose';

    for (const label of ['ftranspose', 'ftrans', 'fTrans', 'fTranspose']) {
      const entry = catalog.entries.find((candidate) => candidate.label === label);
      assert.strictEqual(entry.documentation.synonyms_text, expected);
    }
  });
});

test('generates value catalogs for sound bank pitch scale mode and chord', () => {
  withTempDir((dir) => {
    runGenerator(dir);
    const catalog = readJson(path.join(dir, 'strudel_completions.json'));

    assert(catalog.value_catalogs.sound.entries.some((entry) => entry.label === 'bd'));
    assert(catalog.value_catalogs.sound.entries.some((entry) => entry.label === 'hh'));
    assert(catalog.value_catalogs.bank.entries.some((entry) => entry.label === 'RolandTR909'));
    assert(catalog.value_catalogs.pitch.entries.some((entry) => entry.label === 'C'));
    assert(catalog.value_catalogs.scale.entries.some((entry) => entry.label === 'minor'));
    assert(catalog.value_catalogs.mode.entries.some((entry) => entry.label === 'below'));
    assert(catalog.value_catalogs.chord.entries.some((entry) => entry.label === 'm7'));
  });
});

test('generates compatibility strudel.dict and strudel_docs.json outputs', () => {
  withTempDir((dir) => {
    runGenerator(dir);
    const dict = fs.readFileSync(path.join(dir, 'strudel.dict'), 'utf8').trim().split('\n');
    const docs = readJson(path.join(dir, 'strudel_docs.json'));

    assert(dict.includes('sound'));
    assert(dict.includes('s'));
    assert(dict.includes('note'));
    assert.strictEqual(docs.sound.description, 'Set the sound name.');
    assert.strictEqual(docs.s.description, 'Set the sound name.');
    assert(docs.gain.params.includes('value (number | Pattern): Gain value.'));
    assert.deepStrictEqual(docs.ftranspose.examples, ['i("0 1 2").ftrans("7")']);
    assert.strictEqual(docs.ftranspose.synonyms_text, 'ftrans, fTrans, ftranspose, fTranspose');
    assert.deepStrictEqual(docs.ftranspose.synonyms, ['ftrans', 'fTrans', 'ftranspose', 'fTranspose']);
    assert.deepStrictEqual(docs.ftranspose.tags, ['tonal']);
  });
});

test('is deterministic for repeated generation from the same fixture', () => {
  withTempDir((dir) => {
    runGenerator(dir);
    const first = {
      catalog: fs.readFileSync(path.join(dir, 'strudel_completions.json'), 'utf8'),
      dict: fs.readFileSync(path.join(dir, 'strudel.dict'), 'utf8'),
      docs: fs.readFileSync(path.join(dir, 'strudel_docs.json'), 'utf8'),
    };

    runGenerator(dir);
    const second = {
      catalog: fs.readFileSync(path.join(dir, 'strudel_completions.json'), 'utf8'),
      dict: fs.readFileSync(path.join(dir, 'strudel.dict'), 'utf8'),
      docs: fs.readFileSync(path.join(dir, 'strudel_docs.json'), 'utf8'),
    };

    assert.deepStrictEqual(second, first);
  });
});

test('provenance is portable and output is independent of the local input path', () => {
  withTempDir((dir) => {
    const sourceA = path.join(dir, 'checkout-a', 'doc.json');
    const sourceB = path.join(dir, 'checkout-b', 'doc.json');
    fs.mkdirSync(path.dirname(sourceA), { recursive: true });
    fs.mkdirSync(path.dirname(sourceB), { recursive: true });
    fs.copyFileSync(fixture, sourceA);
    fs.copyFileSync(fixture, sourceB);

    const outA = path.join(dir, 'out-a');
    const outB = path.join(dir, 'out-b');
    runGenerator(outA, sourceA);
    runGenerator(outB, sourceB);

    const first = {
      catalog: fs.readFileSync(path.join(outA, 'strudel_completions.json'), 'utf8'),
      dict: fs.readFileSync(path.join(outA, 'strudel.dict'), 'utf8'),
      docs: fs.readFileSync(path.join(outA, 'strudel_docs.json'), 'utf8'),
    };
    const second = {
      catalog: fs.readFileSync(path.join(outB, 'strudel_completions.json'), 'utf8'),
      dict: fs.readFileSync(path.join(outB, 'strudel.dict'), 'utf8'),
      docs: fs.readFileSync(path.join(outB, 'strudel_docs.json'), 'utf8'),
    };

    assert.deepStrictEqual(second, first);
    const metadata = readJson(path.join(outA, 'strudel_completions.json')).generated_from;
    assert.deepStrictEqual(metadata, {
      source: 'strudel',
      path: 'doc.json',
      revision: 'unknown',
    });
    assert(!path.isAbsolute(metadata.path));
  });
});

process.on('exit', () => {
  if (process.exitCode) {
    process.exit(process.exitCode);
  }
});
