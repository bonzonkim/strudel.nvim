const puppeteer = require('puppeteer');
const dgram = require('dgram');

const UDP_PORT = 9129;

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

    // Log console messages (only errors)
    page.on('console', msg => {
        if (msg.type() === 'error') {
            console.log('BROWSER ERROR:', msg.text());
        }
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

    // === BEAT EVENT STREAMING TO NEOVIM ===
    const NVIM_PORT = 9130;
    let lastBeat = -1;
    let isPlaying = false;

    // Poll for beat events and send to Neovim
    setInterval(async () => {
        try {
            const beatData = await page.evaluate(() => {
                const s = window.strudelMirror?.repl?.scheduler;
                if (!s || !s.pattern) return null;

                const time = s.getTime();
                const cps = s.cps || 1;
                const beat = Math.floor(time * 4) % 4; // 4 beats per cycle
                const cycle = Math.floor(time);
                const cyclePos = time % 1;

                // Query events happening now
                const events = s.pattern.queryArc(time, time + 0.05);
                const activeNotes = events.map(e => {
                    const val = e.value;
                    return {
                        note: val.note || val.n || '',
                        sound: val.sound || val.s || '',
                    };
                });

                return {
                    time,
                    beat,
                    cycle,
                    cyclePos,
                    cps,
                    activeNotes,
                    playing: s.started || false
                };
            });

            if (beatData && beatData.playing) {
                if (!isPlaying) {
                    isPlaying = true;
                    console.log('Beat sync started');
                }

                // Send beat data to Neovim
                const msg = Buffer.from(JSON.stringify({
                    type: 'beat',
                    ...beatData
                }));
                udp.send(msg, 0, msg.length, NVIM_PORT, '127.0.0.1');

                // Log beat changes
                if (beatData.beat !== lastBeat) {
                    lastBeat = beatData.beat;
                    // console.log(`Beat ${beatData.beat + 1}/4 | Cycle ${beatData.cycle}`);
                }
            } else if (isPlaying && beatData && !beatData.playing) {
                isPlaying = false;
                lastBeat = -1;
                console.log('Beat sync stopped');

                // Notify Neovim that playback stopped
                const msg = Buffer.from(JSON.stringify({ type: 'stop' }));
                udp.send(msg, 0, msg.length, NVIM_PORT, '127.0.0.1');
            }
        } catch (e) {
            // Ignore errors during beat polling
        }
    }, 50); // Poll every 50ms for smooth updates

    console.log('Beat sync enabled (UDP 9130)');

})();
