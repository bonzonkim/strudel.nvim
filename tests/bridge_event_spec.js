const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  serializeBridgeEvent,
} = require('../osc-bridge/headless-bridge.js');

const bridgeSource = fs.readFileSync(
  path.join(__dirname, '..', 'osc-bridge', 'headless-bridge.js'),
  'utf8',
);

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

function hap(value = {}, overrides = {}) {
  return {
    value,
    whole: { begin: 2, end: 3 },
    endClipped: 2.5,
    duration: 0.5,
    context: { locations: [{ start: 10, end: 14 }] },
    ...overrides,
  };
}

test('keeps the legacy fields and adds cycle-space event data', () => {
  const event = serializeBridgeEvent(hap({ s: 'piano', note: 'C4', velocity: 0.8 }), 12.5, 2, 0.25);

  assert.strictEqual(event.schema, 'strudel-event');
  assert.strictEqual(event.version, 1);
  assert.strictEqual(event.time, 12.5);
  assert.deepStrictEqual(event.locs, [[10, 14]]);
  assert.strictEqual(event.s, 'piano');
  assert.strictEqual(event.dur, 0.25);
  assert.strictEqual(event.begin, 2);
  assert.strictEqual(event.end, 3);
  assert.strictEqual(event.end_clipped, 2.5);
  assert.strictEqual(event.duration, 0.5);
  assert.strictEqual(event.pitch, 60);
  assert.strictEqual(event.note, 'C4');
  assert.strictEqual(event.sound, 'piano');
  assert.strictEqual(event.velocity, 0.8);
  assert.strictEqual(event.gain, 1);
  assert.strictEqual(event.label, 'C4');
});

test('derives legacy seconds duration when no trigger duration is supplied', () => {
  const event = serializeBridgeEvent(hap(), 12.5, 2);

  assert.strictEqual(event.duration, 0.5);
  assert.strictEqual(event.dur, 0.25);
});

test('uses headed Chrome and one real mouse gesture for audio activation', () => {
  assert.match(bridgeSource, /headless:\s*false/);
  assert.match(bridgeSource, /await page\.mouse\.click\(400, 300\)/);
  assert.doesNotMatch(bridgeSource, /headless:\s*['"]new['"]/);
  assert.doesNotMatch(bridgeSource, /page\.evaluate\(\(\) => window\.strudelMirror\.repl\.evaluate\(['"]silence['"]\)/);
  assert.doesNotMatch(bridgeSource, /button\[title="play"\]/);
});

test('awaits pattern evaluation without audio-context fallbacks or toggles', () => {
  assert.match(bridgeSource, /page\.evaluate\(async \(code\) =>/);
  assert.match(bridgeSource, /return await window\.strudelMirror\.repl\.evaluate\(code\)/);
  assert.match(bridgeSource, /return await window\.repl\.evaluate\(code\)/);
  assert.doesNotMatch(bridgeSource, /scheduler\?\.audioContext/);
  assert.doesNotMatch(bridgeSource, /new \(window\.AudioContext \|\| window\.webkitAudioContext\)\(\)/);
});

test('uses frequency, note, then n for normalized MIDI pitch', () => {
  assert.strictEqual(serializeBridgeEvent(hap({ freq: 440, note: 'C2', n: 1 })).pitch, 69);
  assert.strictEqual(serializeBridgeEvent(hap({ note: 'Db-1', n: 1 })).pitch, 1);
  assert.strictEqual(serializeBridgeEvent(hap({ n: 42 })).pitch, 42);
});

test('handles malformed and missing data without producing unsafe JSON', () => {
  const cyclic = {};
  cyclic.self = cyclic;
  const event = serializeBridgeEvent({ value: { freq: NaN, note: cyclic, s: cyclic, velocity: Infinity } }, NaN, Infinity);

  assert.strictEqual(event.time, null);
  assert.strictEqual(event.pitch, null);
  assert.strictEqual(event.note, null);
  assert.strictEqual(event.sound, null);
  assert.strictEqual(event.dur, 0.1);
  assert.doesNotThrow(() => JSON.stringify(event));
  assert.deepStrictEqual(serializeBridgeEvent({}, { time: 4 }), {
    schema: 'strudel-event',
    version: 1,
    time: 4,
    begin: null,
    end: null,
    end_clipped: null,
    duration: null,
    pitch: null,
    note: null,
    sound: null,
    velocity: 1,
    gain: 1,
    label: 'unknown',
    locs: [],
    s: 'unknown',
    dur: 0.1,
  });
});

test('preserves the old note and n sound labels', () => {
  assert.strictEqual(serializeBridgeEvent(hap({ note: 'E3' })).s, 'note:E3');
  assert.strictEqual(serializeBridgeEvent(hap({ n: 7, s: 'sine' })).label, 'sine:7');
  assert.strictEqual(serializeBridgeEvent(hap({ n: 7 })).s, 'n:7');
});
