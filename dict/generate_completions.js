#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function parseArgs(argv) {
  const args = {
    outDir: path.resolve(__dirname),
  };

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

function stripHtml(value) {
  if (typeof value !== 'string') return undefined;
  return value
    .replace(/<[^>]*>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\s+/g, ' ')
    .trim();
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
      if (name) tags.push(name);
    }
  }
  for (const key of ['noAutocomplete', 'superdirtOnly']) {
    if (doc[key]) tags.push(key);
  }
  return [...new Set(tags)].sort();
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
      name: param.name,
      types: Array.isArray(param.type && param.type.names) ? param.type.names : [],
      description: stripHtml(param.description) || undefined,
    }));
}

function buildDocumentation(doc, relatedNames) {
  const documentation = {};
  const description = stripHtml(doc.description);
  const params = normalizeParams(doc.params);

  if (description) documentation.description = description;
  if (relatedNames.length) documentation.synonyms_text = relatedNames.join(', ');
  if (params.length) documentation.parameters = params;
  if (Array.isArray(doc.examples) && doc.examples.length) {
    documentation.examples = doc.examples.map((example) => String(example));
  }

  return documentation;
}

function makeEntry({ label, canonical, relatedNames, doc, tags }) {
  const entry = {
    label,
    insert_text: label,
    kind: doc.kind && doc.kind !== 'member' ? doc.kind : 'function',
    detail: doc.kind === 'sound' ? 'Strudel Sound' : 'Strudel Function',
  };
  if (canonical && canonical !== label) entry.canonical = canonical;
  if (relatedNames.length) entry.aliases = relatedNames;
  if (tags.length) entry.tags = tags;

  const documentation = buildDocumentation(doc, relatedNames);
  if (Object.keys(documentation).length) entry.documentation = documentation;

  return entry;
}

function compareLabels(a, b) {
  if (a.label < b.label) return -1;
  if (a.label > b.label) return 1;
  return 0;
}

function normalizeDocJson(raw, sourcePath) {
  const docs = Array.isArray(raw.docs) ? raw.docs : [];
  const entries = [];
  const seen = new Set();
  const seenCanonicalDocs = new Set();

  for (const doc of docs) {
    const canonical = getDocLabel(doc);
    const tags = normalizeTags(doc);
    if (isExcluded(doc, canonical, tags)) continue;
    if (seenCanonicalDocs.has(canonical)) continue;
    seenCanonicalDocs.add(canonical);

    const synonyms = Array.isArray(doc.synonyms) ? doc.synonyms.filter(Boolean) : [];
    const labels = [canonical, ...synonyms];

    for (const label of labels) {
      if (!label || seen.has(label)) continue;
      seen.add(label);
      const relatedNames = labels.filter((name) => name && name !== label);
      entries.push(makeEntry({
        label,
        canonical,
        relatedNames,
        doc,
        tags,
      }));
    }
  }

  entries.sort(compareLabels);

  return {
    version: 1,
    generated_from: {
      source: 'strudel',
      path: sourcePath,
      revision: gitRevision(path.dirname(sourcePath)),
    },
    entries,
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
    docs[entry.label] = {
      description: doc.description || '',
      params,
    };
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
    console.error(err.message);
    process.exit(1);
  }
}

module.exports = {
  normalizeDocJson,
  writeOutputs,
};
