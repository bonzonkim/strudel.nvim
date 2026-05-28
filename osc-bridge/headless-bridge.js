const puppeteer = require('puppeteer');
const dgram = require('dgram');

const UDP_PORT = 9129;

// Install the visual-effects hook by wrapping scheduler.setPattern.
//
// We can't access Strudel's `all()` from `page.evaluate` (it's module-scoped
// inside @strudel/core), and `repl.evaluate(<hook code>)` hangs because the
// transpiler treats the snippet as a pattern. Instead we wrap the scheduler's
// setPattern method: every evaluated pattern flows through it, and we attach
// `.onTrigger(fn, false)` before delegating to the original.
async function injectHook(page) {
    try {
        await page.evaluate(() => {
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
                        pat = pat.onTrigger((hap, dur, cps, t) => {
                            const locs = hap && hap.context && hap.context.locations;
                            if (!locs || !locs.length) return;
                            const v = hap.value || {};
                            let sound;
                            if (v.s != null) sound = String(v.s);
                            else if (v.note != null) sound = 'note:' + v.note;
                            else if (v.n != null) sound = 'n:' + v.n;
                            else sound = 'unknown';
                            console.log('__STRUDEL_EVENT__' + JSON.stringify({
                                locs: locs.map((l) => [l.start, l.end]),
                                s: sound,
                                dur: (hap.duration && cps) ? (hap.duration / cps) : 0.1,
                            }));
                        }, false);  // false = NOT dominant; preserves audio output
                    } catch (e) {
                        console.error('Strudel visual hook wrap failed:', e && e.message);
                    }
                }
                return orig(pat, autostart);
            };
        });
    } catch (err) {
        console.error('injectHook page.evaluate failed:', err && err.message);
    }
}

(async () => {
    console.log('Starting Headless Strudel...');

    // Launch Chrome with autoplay allowed
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

})();
