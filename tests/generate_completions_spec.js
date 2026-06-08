const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const generator = path.join(root, 'dict', 'generate_completions.js');
const fixture = path.join(root, 'tests', 'fixtures', 'strudel_doc_fixture.json');

function runGenerator(outDir) {
  execFileSync(process.execPath, [generator, '--doc-json', fixture, '--out-dir', outDir], {
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
    assert(labels.includes('sound'));
    assert(labels.includes('s'));
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

    execFileSync(process.execPath, [generator, '--doc-json', docJson, '--out-dir', dir], {
      cwd: root,
      stdio: 'pipe',
    });

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
    assert.deepStrictEqual(gain.documentation.examples, ['sound("bd").gain(0.8)']);
  });
});

test('generates compatibility strudel.dict and strudel_docs.json outputs', () => {
  withTempDir((dir) => {
    runGenerator(dir);
    const dict = fs.readFileSync(path.join(dir, 'strudel.dict'), 'utf8').trim().split('\n');
    const docs = readJson(path.join(dir, 'strudel_docs.json'));

    assert(dict.includes('sound'));
    assert(dict.includes('s'));
    assert(dict.includes('gain'));
    assert.strictEqual(docs.sound.description, 'Set the sound name.');
    assert.strictEqual(docs.s.description, 'Set the sound name.');
    assert(docs.gain.params.includes('value (number | Pattern): Gain value.'));
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

process.on('exit', () => {
  if (process.exitCode) {
    process.exit(process.exitCode);
  }
});
