const dgram = require('dgram');

const UDP_PORT = 9129;

/**
 * Turn a Strudel hap into the small, JSON-only event contract consumed by the
 * editor.  This deliberately has no dependencies: the same function is
 * stringified and installed in the browser page by injectHook, and is also
 * exported for node-side contract tests.
 */
function serializeBridgeEvent(hap, timeOrOptions, cps, secondsDuration) {
    const finiteNumber = (value) => {
        if (typeof value === 'number') return Number.isFinite(value) ? value : null;
        if (value == null || typeof value === 'string' || typeof value === 'boolean') return null;
        try {
            const number = Number(value);
            return Number.isFinite(number) ? number : null;
        } catch (_) {
            return null;
        }
    };
    const scalar = (value) => {
        if (typeof value === 'string' || typeof value === 'boolean') return value;
        if (typeof value === 'number') return Number.isFinite(value) ? value : null;
        return null;
    };
    const text = (value) => {
        if (value == null) return null;
        if (typeof value === 'string') return value;
        if (typeof value === 'number' || typeof value === 'boolean') return String(value);
        return null;
    };
    const safeString = (value) => {
        try {
            return String(value);
        } catch (_) {
            return null;
        }
    };
    const property = (object, key) => {
        if (!object || (typeof object !== 'object' && typeof object !== 'function')) return undefined;
        try {
            return object[key];
        } catch (_) {
            return undefined;
        }
    };

    // Accept an options object as well as positional arguments.  The latter
    // keeps this helper convenient for tests and the former makes its contract
    // unambiguous at call sites.
    const hasTimeOption = timeOrOptions && typeof timeOrOptions === 'object' && !Array.isArray(timeOrOptions)
        && (property(timeOrOptions, 'time') !== undefined || property(timeOrOptions, 't') !== undefined
            || property(timeOrOptions, 'cps') !== undefined || property(timeOrOptions, 'secondsDuration') !== undefined
            || property(timeOrOptions, 'dur') !== undefined);
    if (hasTimeOption) {
        const options = timeOrOptions;
        timeOrOptions = property(options, 'time');
        if (timeOrOptions == null) timeOrOptions = property(options, 't');
        cps = property(options, 'cps');
        secondsDuration = property(options, 'secondsDuration');
        if (secondsDuration == null) secondsDuration = property(options, 'dur');
    }

    const value = property(hap, 'value');
    const eventValue = value && typeof value === 'object' ? value : {};
    const whole = property(hap, 'whole');
    const begin = finiteNumber(property(whole, 'begin'));
    const end = finiteNumber(property(whole, 'end'));
    const endClipped = finiteNumber(property(hap, 'endClipped'));
    const cycleDuration = finiteNumber(property(hap, 'duration'));
    const time = finiteNumber(timeOrOptions);

    // This is intentionally the same precedence as draw/pianoroll.mjs:
    // frequency first, then note, then n.  An invalid higher-priority value
    // does not make a valid lower-priority value unusable.
    const freq = finiteNumber(property(eventValue, 'freq'));
    let noteValue;
    if (property(eventValue, 'note') != null) noteValue = property(eventValue, 'note');
    else if (property(eventValue, 'n') != null) noteValue = property(eventValue, 'n');
    const normalizedNote = scalar(noteValue);
    let pitch = null;
    if (freq != null && freq > 0) {
        const midi = (12 * Math.log(freq / 440)) / Math.LN2 + 69;
        pitch = Number.isFinite(midi) ? midi : null;
    } else if (typeof noteValue === 'number') {
        pitch = Number.isFinite(noteValue) ? noteValue : null;
    } else if (typeof noteValue === 'string') {
        // Strudel accepts repeated #/b (and the s/f aliases), with an
        // optional signed octave.  An omitted octave means octave 3.
        const match = noteValue.match(/^([a-gA-G])([#bsf]*)([+-]?\d*)$/);
        if (match) {
            const chroma = { c: 0, d: 2, e: 4, f: 5, g: 7, a: 9, b: 11 }[match[1].toLowerCase()];
            const accidental = match[2].split('').reduce((offset, part) => offset + ({ '#': 1, b: -1, s: 1, f: -1 }[part] || 0), 0);
            const octave = match[3] === '' || match[3] === '+' || match[3] === '-' ? 3 : Number(match[3]);
            const midi = (octave + 1) * 12 + chroma + accidental;
            pitch = Number.isFinite(midi) ? midi : null;
        }
    }

    const soundValue = property(eventValue, 's') != null ? property(eventValue, 's') : property(eventValue, 'sound');
    const sound = text(soundValue);
    const velocityValue = finiteNumber(property(eventValue, 'velocity'));
    const gainValue = finiteNumber(property(eventValue, 'gain'));
    const velocity = velocityValue == null ? 1 : velocityValue;
    const gain = gainValue == null ? 1 : gainValue;

    const customLabel = text(property(eventValue, 'label'));
    const explicitNote = property(eventValue, 'note');
    let label = customLabel;
    if (label == null && explicitNote != null) label = safeString(explicitNote);
    if (label == null && sound != null) {
      const n = property(eventValue, 'n');
      const nText = n ? safeString(n) : null;
      label = sound + (nText != null ? ':' + nText : '');
    }
    if (label == null && normalizedNote != null) label = safeString(normalizedNote);
    if (label == null && freq != null) label = safeString(freq) + 'Hz';
    if (label == null) label = 'unknown';

    const locations = property(property(hap, 'context'), 'locations');
    const locs = Array.isArray(locations)
        ? locations.map((location) => [
            finiteNumber(property(location, 'start')),
            finiteNumber(property(location, 'end')),
        ])
        : [];

    let legacyDuration = finiteNumber(secondsDuration);
    if (legacyDuration == null && cycleDuration != null) {
        const cyclesPerSecond = finiteNumber(cps);
        if (cyclesPerSecond != null && cyclesPerSecond !== 0) legacyDuration = cycleDuration / cyclesPerSecond;
    }
    if (legacyDuration == null || !Number.isFinite(legacyDuration)) legacyDuration = 0.1;

    // Keep locs, s, and dur stable for existing Neovim clients while adding
    // the cycle-space fields needed by a real piano roll.
    const legacySound = sound != null
        ? sound
        : property(eventValue, 'note') != null
            ? 'note:' + (safeString(property(eventValue, 'note')) || 'unknown')
            : property(eventValue, 'n') != null
                ? 'n:' + (safeString(property(eventValue, 'n')) || 'unknown')
                : 'unknown';

    return {
        schema: 'strudel-event',
        version: 1,
        time,
        begin,
        end,
        end_clipped: endClipped,
        duration: cycleDuration,
        pitch,
        note: normalizedNote,
        sound,
        velocity,
        gain,
        label,
        locs,
        s: legacySound,
        dur: legacyDuration,
    };
}

// Install the visual-effects hook by wrapping scheduler.setPattern.
//
// We can't access Strudel's `all()` from `page.evaluate` (it's module-scoped
// inside @strudel/core), and `repl.evaluate(<hook code>)` hangs because the
// transpiler treats the snippet as a pattern. Instead we wrap the scheduler's
// setPattern method: every evaluated pattern flows through it, and we attach
// `.onTrigger(fn, false)` before delegating to the original.
async function injectHook(page) {
    try {
        await page.evaluate((serializerSource) => {
            // The helper is dependency-free so it can safely cross the node /
            // browser boundary without duplicating the event contract.
            const serializePayload = Function('return (' + serializerSource + ')')();
            if (window.__strudelHookInstalled) return;
            const sch = window.strudelMirror && window.strudelMirror.repl && window.strudelMirror.repl.scheduler;
            if (!sch || typeof sch.setPattern !== 'function') {
                console.error('Strudel visual hook: scheduler.setPattern unavailable');
                return;
            }
            window.__strudelHookInstalled = true;
            const orig = sch.setPattern.bind(sch);
            sch.setPattern = async function(pat, autostart) {
                if (pat && typeof pat.onTrigger === 'function') {
                    try {
                        // Pattern.onTrigger callbacks receive (hap, currentTime,
                        // cps, targetTime); unlike scheduler outputs they do not
                        // receive deadline or duration arguments.
                        pat = pat.onTrigger((hap, currentTime, cps, targetTime) => {
                            const locs = hap && hap.context && hap.context.locations;
                            if (!locs || !locs.length) return;
                            console.log('__STRUDEL_EVENT__' + JSON.stringify(
                                serializePayload(hap, targetTime, cps, currentTime),
                            ));
                        }, false);  // false = NOT dominant; preserves audio output
                    } catch (e) {
                        console.error('Strudel visual hook wrap failed:', e && e.message);
                    }
                }
                return orig(pat, autostart);
            };
        }, serializeBridgeEvent.toString());
    } catch (err) {
        console.error('injectHook page.evaluate failed:', err && err.message);
    }
}

async function main() {
    console.log('Starting Headless Strudel...');

    // Launch Chrome with autoplay allowed
    const puppeteer = require('puppeteer');
    const browser = await puppeteer.launch({
        headless: 'new', // Launch headless
        ignoreDefaultArgs: ['--mute-audio'],
        args: [
            '--autoplay-policy=no-user-gesture-required',
            '--use-fake-ui-for-media-stream',
            '--window-size=1920,1080', // To ensure sufficient viewport
        ]
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 800, height: 600 })

    // Forward event payloads from console.log lines, and surface real errors.
    page.on('console', msg => {
        const text = msg.text();
        if (text.startsWith('__STRUDEL_EVENT__')) {
            console.log(text);
            return;
        }
        if (msg.type() === 'error') {
            // msg.text() shows `@JSHandle@error` for Error objects.
            // JSHandle.evaluate runs in the browser, where we can extract real fields.
            Promise.all(msg.args().map(arg => arg.evaluate(o => {
                if (o instanceof Error) return o.stack || o.message || String(o);
                if (o && typeof o === 'object') {
                    try { return JSON.stringify(o); } catch (_) { return String(o); }
                }
                return String(o);
            }).catch(() => null)))
                .then(vals => console.log('BROWSER ERROR:', ...vals.map(v => v == null ? text : v)))
                .catch(() => console.log('BROWSER ERROR:', text));
        }
    });
    page.on('pageerror', err => {
        console.log('BROWSER PAGE ERROR:', err && err.message ? err.message : String(err));
    });

    console.log('Loading Strudel...');
    await page.goto('https://strudel.cc', { waitUntil: 'networkidle0' });

    // Wait for Strudel to initialize
    try {
        await page.waitForFunction(() => window.strudelMirror && window.strudelMirror.repl, { timeout: 10000 });
        // console.log('Strudel global object found!');
    } catch (e) {
        console.log('Warning: Timeout waiting for strudelMirror, proceeding anyway...');
    }

    // Try to start the audio engine and resume context
    await page.evaluate(async () => {
        if (window.strudelMirror && window.strudelMirror.repl) {
            // console.log("Starting REPL...");
            window.strudelMirror.repl.start();
        }

        // Force resume AudioContext
        const ctx = window.strudelMirror?.repl?.scheduler?.audioContext || new (window.AudioContext || window.webkitAudioContext)();
        if (ctx.state === 'suspended') {
            // console.log("AudioContext suspended, trying to resume...");
            await ctx.resume();
            // console.log("AudioContext state after resume:", ctx.state);
        } else {
            // console.log("AudioContext state:", ctx.state);
        }
    });

    // Install the visual-effects onTrigger hook ONCE, before any user eval.
    // `all(fn)` registers a transformation that gets applied to every pattern
    // evaluated thereafter — so it must be set before the first user /eval.
    await injectHook(page);

    // Unlock audio context first (a click event is required by browser autoplay
    // policy). Without this, repl.evaluate hangs because the scheduler can't
    // start without audio. Then silence strudel.cc's auto-loaded starter
    // pattern — otherwise its haps keep firing through our hook with locations
    // that don't correspond to the user's buffer, producing phantom highlights
    // when a user eval errors (e.g. an outdated .play() call).
    try {
        const playBtn = await page.$('button[title="play"]');
        if (playBtn) { await playBtn.click(); } else { await page.click('body'); }
        await page.evaluate(() => window.strudelMirror.repl.evaluate('silence'));
    } catch (e) {
        console.error('Failed to silence starter pattern:', e && e.message);
    }

    console.log('Strudel loaded!');

    // Setup UDP Server
    const udp = dgram.createSocket('udp4');

    udp.on('message', async (msg, rinfo) => {
        // Basic OSC parsing for /eval
        let str = msg.toString();
        const addressEnd = str.indexOf('\0');
        const address = str.substring(0, addressEnd);

        // Handle Bridge Control Commands
        if (address === '/bridge/show') {
            // Move window to top-left
            const session = await page.target().createCDPSession();
            const { windowId } = await session.send('Browser.getWindowForTarget');
            await session.send('Browser.setWindowBounds', { windowId, bounds: { left: 0, top: 0, width: 800, height: 600 } });
            console.log('Window shown');
            return;
        }
        if (address === '/bridge/hide') {
            // Move window off-screen
            const session = await page.target().createCDPSession();
            const { windowId } = await session.send('Browser.getWindowForTarget');
            await session.send('Browser.setWindowBounds', { windowId, bounds: { left: -10000, top: 0 } });
            console.log('Window hidden');
            return;
        }

        if (address !== '/eval') return;

        // Parse argument (simplified)
        let typeTagStart = Math.ceil((address.length + 1) / 4) * 4;
        if (msg[typeTagStart] !== 44) { // ','
            typeTagStart = str.indexOf(',', addressEnd);
            if (typeTagStart === -1) return;
        }

        const typeTagStrEnd = str.indexOf('\0', typeTagStart);
        const typeTagStrLen = typeTagStrEnd - typeTagStart;
        const argsStart = typeTagStart + Math.ceil((typeTagStrLen + 1) / 4) * 4;

        let code = str.substring(argsStart);
        code = code.replace(/\0+$/, '');

        console.log('Playing...');

        // Simulate a click on the Play button to ensure audio context is unlocked
        try {
            // Try to find and click the play button
            const playBtn = await page.$('button[title="play"]');
            if (playBtn) {
                await playBtn.click();
                // console.log('Clicked Play button');
            } else {
                // Fallback to body click
                await page.click('body');
                // console.log('Clicked body (Play button not found)');
            }
        } catch (e) {
            // console.log('Click failed:', e.message);
        }

        // Evaluate in browser
        try {
            await page.evaluate((code) => {
                // Force resume AudioContext again just in case
                const ctx = window.strudelMirror?.repl?.scheduler?.audioContext || new (window.AudioContext || window.webkitAudioContext)();
                if (ctx.state === 'suspended') {
                    ctx.resume();
                }

                // Try to find the REPL instance
                if (window.strudelMirror && window.strudelMirror.repl) {
                    window.strudelMirror.repl.evaluate(code);
                } else if (window.repl && typeof window.repl.evaluate === 'function') {
                    window.repl.evaluate(code);
                } else {
                    console.error('Could not find REPL instance');
                }
            }, code);

            await injectHook(page);
        } catch (err) {
            console.error('Eval failed:', err);
        }
    });

    udp.bind(UDP_PORT);
    console.log(`Listening for OSC on UDP ${UDP_PORT}`);

    // Simulate a click to unlock audio context
    try {
        await page.evaluate(() => {
          document.body.click();
        })
    } catch (e) { }

}

if (require.main === module) {
    main().catch((err) => {
        console.error('Headless Strudel failed:', err && err.stack ? err.stack : err);
        process.exitCode = 1;
    });
}

module.exports = {
    main,
    injectHook,
    serializeBridgeEvent,
    // These aliases make the payload helper easy to discover without making
    // callers depend on the bridge's startup function.
    serializeEventPayload: serializeBridgeEvent,
    createBridgeEventPayload: serializeBridgeEvent,
};
