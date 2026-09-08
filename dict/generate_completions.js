#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const PITCH_NAMES = [
  'A',
  'A#',
  'Ab',
  'B',
  'B#',
  'Bb',
  'C',
  'C#',
  'Cb',
  'D',
  'D#',
  'Db',
  'E',
  'E#',
  'Eb',
  'F',
  'F#',
  'Fb',
  'G',
  'G#',
  'Gb',
];

const SCALE_NAMES = [
  'major',
  'minor',
  'ionian',
  'dorian',
  'phrygian',
  'lydian',
  'mixolydian',
  'aeolian',
  'locrian',
  'major pentatonic',
  'minor pentatonic',
  'chromatic',
  'harmonic minor',
  'melodic minor',
  'whole tone',
];

const MODE_NAMES = ['above', 'below', 'duck', 'root'];

const CHORD_SYMBOLS = [
  '',
  'm',
  'min',
  'maj',
  'maj7',
  'm7',
  '7',
  'dim',
  'dim7',
  'aug',
  'sus2',
  'sus4',
  'add9',
  'm9',
  '9',
  '11',
  '13',
  '^',
  '^7',
  '+',
  'o',
  'ø',
];

const DEFAULT_SOUNDS = ['bd', 'cp', 'hh', 'oh', 'rim', 'sd'];
const DEFAULT_BANKS = ['RolandTR808', 'RolandTR909', 'tr808', 'tr909'];

function parseArgs(argv) {
  const args = { outDir: path.resolve(__dirname) };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--strudel-repo') {
      args.strudelRepo = argv[++i];
    } else if (arg === '--doc-json') {
      args.docJson = argv[++i];
    } else if (arg === '--out-dir') {
      args.outDir = argv[++i];
    } else if (arg === '--help' || arg === '-h') {
      args.help = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (args.help) return args;
  if (!args.docJson && args.strudelRepo) {
    args.docJson = path.join(args.strudelRepo, 'doc.json');
  }
  if (!args.docJson) {
    throw new Error('Provide --doc-json <path> or --strudel-repo <path>');
  }

  args.docJson = path.resolve(args.docJson);
  args.outDir = path.resolve(args.outDir);
  return args;
}

function decodeHtml(value) {
  return value
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}

function stripHtml(value) {
  if (typeof value !== 'string') return undefined;
  const text = decodeHtml(value.replace(/<[^>]*>/g, ' '))
    .replace(/\s+/g, ' ')
    .replace(/\s+([.,;:!?])/g, '$1')
    .trim();
  return text || undefined;
}

function tagName(tag) {
  if (typeof tag === 'string') return tag;
  if (tag && typeof tag === 'object') {
    return tag.originalTitle || tag.title || tag.value || tag.text;
  }
  return undefined;
}

function normalizeTags(doc) {
  const tags = [];
  if (Array.isArray(doc.tags)) {
    for (const tag of doc.tags) {
      const name = tagName(tag);
      if (name) {
        for (const part of String(name).split(',')) {
          const trimmed = part.trim();
          if (trimmed) tags.push(trimmed);
        }
      }
    }
  }
  for (const key of ['noAutocomplete', 'superdirtOnly']) {
    if (doc[key]) tags.push(key);
  }
  return uniqueSorted(tags);
}

function getDocLabel(doc) {
  return doc.name || doc.longname;
}

function isExcluded(doc, label, tags) {
  if (!label || label.startsWith('_')) return true;
  if (doc.kind === 'package') return true;
  return tags.includes('superdirtOnly') || tags.includes('noAutocomplete');
}

function normalizeParams(params) {
  if (!Array.isArray(params)) return [];
  return params
    .filter((param) => param && param.name)
    .map((param) => ({
      name: String(param.name),
      types: Array.isArray(param.type && param.type.names) ? param.type.names.map(String) : [],
      description: stripHtml(param.description),
    }))
    .map((param) => {
      const out = { name: param.name };
      if (param.types.length) out.types = param.types;
      if (param.description) out.description = param.description;
      return out;
    });
}

function buildDocumentation(doc, relatedNames) {
  const documentation = {};
  const description = stripHtml(doc.description);
  const parameters = normalizeParams(doc.params);

  if (description) documentation.description = description;
  if (typeof doc.synonyms_text === 'string' && doc.synonyms_text) {
    // doc.json's rendered synonym text is authoritative. In particular, it
    // can include the canonical name and ordering that the synonym array
    // loses when aliases are expanded into completion entries.
    documentation.synonyms_text = doc.synonyms_text;
  } else if (relatedNames.length) {
    documentation.synonyms_text = relatedNames.join(', ');
  }
  if (parameters.length) documentation.parameters = parameters;
  if (Array.isArray(doc.examples) && doc.examples.length) {
    documentation.examples = doc.examples.map((example) => String(example));
  }

  return documentation;
}

function makeEntry({ label, canonical, relatedNames, doc, tags }) {
  const entry = {
    label,
    insert_text: label,
    kind: 'function',
    detail: 'Strudel Function',
  };

  if (canonical && canonical !== label) entry.canonical = canonical;
  if (relatedNames.length) entry.aliases = relatedNames;
  if (tags.length) entry.tags = tags;

  const documentation = buildDocumentation(doc, relatedNames);
  if (Object.keys(documentation).length) entry.documentation = documentation;

  return entry;
}

function compareLabel(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function compareEntry(a, b) {
  return compareLabel(a.label, b.label);
}

function uniqueSorted(values) {
  return [...new Set(values.filter((value) => typeof value === 'string' && value.length > 0))].sort(compareLabel);
}

function extractQuotedValues(text, names) {
  const out = [];
  for (const name of names) {
    const re = new RegExp(`${name}\\s*\\(\\s*(['"])(.*?)\\1`, 'g');
    let match;
    while ((match = re.exec(text))) {
      out.push(match[2]);
    }
  }
  return out;
}

function tokenizeSoundPattern(pattern) {
  return pattern
    .replace(/[<>\[\]{}(),|!*?~]/g, ' ')
    .split(/\s+/)
    .map((token) => token.split(':')[0])
    .map((token) => token.trim())
    .filter((token) => /^[A-Za-z][A-Za-z0-9_-]*$/.test(token));
}

function extractValueFamilies(rawDocs) {
  const sounds = new Set(DEFAULT_SOUNDS);
  const banks = new Set(DEFAULT_BANKS);

  for (const doc of rawDocs) {
    const examples = Array.isArray(doc.examples) ? doc.examples.join('\n') : '';
    const description = typeof doc.description === 'string' ? doc.description : '';
    const comment = typeof doc.comment === 'string' ? doc.comment : '';
    const text = [examples, description, comment].join('\n');

    for (const pattern of extractQuotedValues(text, ['s', 'sound'])) {
      for (const sound of tokenizeSoundPattern(pattern)) {
        if (!['github', 'http', 'https'].includes(sound.toLowerCase())) sounds.add(sound);
      }
    }

    for (const bank of extractQuotedValues(text, ['bank'])) {
      if (/^[A-Za-z][A-Za-z0-9_-]*$/.test(bank)) banks.add(bank);
    }
  }

  return {
    sound: valueCatalog('sound', uniqueSorted([...sounds]), 'generated'),
    bank: valueCatalog('bank', uniqueSorted([...banks]), 'generated'),
    pitch: valueCatalog('pitch', uniqueSorted(PITCH_NAMES), 'bundled'),
    scale: valueCatalog('scale', uniqueSorted(SCALE_NAMES), 'bundled'),
    mode: valueCatalog('mode', uniqueSorted(MODE_NAMES), 'bundled'),
    chord: valueCatalog('chord', uniqueSorted(CHORD_SYMBOLS), 'bundled'),
  };
}

function valueCatalog(kind, labels, availability) {
  return {
    availability,
    entries: uniqueSorted(labels).map((label) => ({
      label: label === '' ? 'major' : label,
      insert_text: label,
      kind,
      detail: `Strudel ${kind}`,
    })),
  };
}

function gitRevision(cwd) {
  try {
    return execFileSync('git', ['rev-parse', '--short', 'HEAD'], {
      cwd,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch (_) {
    return 'unknown';
  }
}

function normalizeDocJson(raw, sourcePath) {
  const rawDocs = Array.isArray(raw.docs) ? raw.docs : [];
  const entries = [];
  const seenLabels = new Set();
  const seenCanonicalDocs = new Set();

  for (const doc of rawDocs) {
    const canonical = getDocLabel(doc);
    const tags = normalizeTags(doc);
    if (isExcluded(doc, canonical, tags)) continue;
    if (seenCanonicalDocs.has(canonical)) continue;
    seenCanonicalDocs.add(canonical);

    const synonyms = Array.isArray(doc.synonyms) ? doc.synonyms.map(String).filter(Boolean) : [];
    const labels = [canonical, ...synonyms];

    for (const label of labels) {
      if (!label || seenLabels.has(label)) continue;
      seenLabels.add(label);
      const relatedNames = labels.filter((name) => name && name !== label);
      entries.push(makeEntry({ label, canonical, relatedNames, doc, tags }));
    }
  }

  entries.sort(compareEntry);

  return {
    version: 1,
    generated_from: {
      source: 'strudel',
      // Keep provenance portable: the source identifier is useful to humans,
      // but the machine-specific checkout path is not part of the artifact.
      path: 'doc.json',
      revision: gitRevision(path.dirname(sourcePath)),
    },
    entries,
    value_catalogs: extractValueFamilies(rawDocs),
  };
}

function compatibilityDocs(catalog) {
  const docs = {};
  for (const entry of catalog.entries) {
    const doc = entry.documentation || {};
    const params = [];
    if (Array.isArray(doc.parameters)) {
      for (const param of doc.parameters) {
        const types = Array.isArray(param.types) && param.types.length ? ` (${param.types.join(' | ')})` : '';
        const desc = param.description ? `: ${param.description}` : '';
        params.push(`${param.name}${types}${desc}`);
      }
    }
    const compatibilityDoc = {
      description: doc.description || '',
      params,
    };
    if (Array.isArray(doc.examples) && doc.examples.length) {
      compatibilityDoc.examples = doc.examples;
    }
    if (doc.synonyms_text) {
      compatibilityDoc.synonyms_text = doc.synonyms_text;
      compatibilityDoc.synonyms = doc.synonyms_text.split(',').map((name) => name.trim());
    } else if (Array.isArray(entry.aliases) && entry.aliases.length) {
      compatibilityDoc.synonyms = entry.aliases;
    }
    if (Array.isArray(entry.tags) && entry.tags.length) {
      compatibilityDoc.tags = entry.tags;
    }
    docs[entry.label] = compatibilityDoc;
  }
  return docs;
}

function writeOutputs(catalog, outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'strudel_completions.json'), `${JSON.stringify(catalog, null, 2)}\n`);
  fs.writeFileSync(path.join(outDir, 'strudel.dict'), `${catalog.entries.map((entry) => entry.label).join('\n')}\n`);
  fs.writeFileSync(path.join(outDir, 'strudel_docs.json'), `${JSON.stringify(compatibilityDocs(catalog), null, 2)}\n`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log('Usage: node dict/generate_completions.js [--strudel-repo PATH | --doc-json PATH] [--out-dir PATH]');
    return;
  }

  const raw = JSON.parse(fs.readFileSync(args.docJson, 'utf8'));
  const catalog = normalizeDocJson(raw, args.docJson);
  writeOutputs(catalog, args.outDir);
  console.log(`Generated ${catalog.entries.length} completion entries.`);
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error(err.stack || err.message);
    process.exit(1);
  }
}

module.exports = {
  normalizeDocJson,
  writeOutputs,
  stripHtml,
};
