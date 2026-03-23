#!/usr/bin/env node
'use strict';

const puppeteer = require('puppeteer');
const WebSocket = require('ws');
const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

function getArg(name) {
    const idx = process.argv.indexOf(name);
    return idx >= 0 && idx + 1 < process.argv.length ? process.argv[idx + 1] : null;
}

const args = {
    manual: process.argv.includes('--manual'),
    auto: process.argv.includes('--auto'),
    thenManual: process.argv.includes('--then-manual'),
    help: process.argv.includes('--help'),
    concurrency: parseInt(getArg('--concurrency')) || 3,
    sites: getArg('--sites'),
    proxyPort: parseInt(getArg('--proxy-port')) || 8080,
    dashboardPort: parseInt(getArg('--dashboard-port')) || 9090,
};

if (args.help || (!args.manual && !args.auto)) {
    console.log(`Usage: node browser-test.js [OPTIONS]

Options:
  --manual              Open browser for manual browsing
  --auto                Auto-visit sites from sites.json
  --auto --then-manual  Auto-surf then wait for manual browsing
  --concurrency N       Max concurrent tabs (default 3)
  --sites FILE          Custom sites JSON file
  --proxy-port PORT     Proxy port (default 8080)
  --dashboard-port PORT Dashboard port (default 9090)
  --help                Show this help message

Examples:
  node browser-test.js --auto
  node browser-test.js --manual
  node browser-test.js --auto --then-manual --concurrency 5
  node browser-test.js --auto --sites my-sites.json --proxy-port 9999`);
    process.exit(0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function sleep(ms) {
    return new Promise(r => setTimeout(r, ms));
}

// ---------------------------------------------------------------------------
// Visit a single page: navigate, scroll, click same-origin links
// ---------------------------------------------------------------------------

async function visitPage(browser, url) {
    const page = await browser.newPage();
    try {
        // Navigate to the target URL
        await page.goto(url, { waitUntil: 'networkidle2', timeout: 60000 });

        // Stay on page at least 5 seconds — simulate reading + scrolling
        // Scroll 4 times with longer pauses to meet minimum dwell time
        for (let i = 0; i < 4; i++) {
            await page.evaluate(() => window.scrollBy(0, window.innerHeight * 0.7));
            await sleep(1200 + Math.random() * 600);  // ~1.2-1.8s per scroll
        }
        // Extra dwell to ensure ≥5s total on page
        await sleep(1000);

        // Click up to 2 same-origin links to exercise more traffic
        const origin = new URL(url).origin;
        const links = await page.$$eval(
            'a[href]',
            (anchors, pageOrigin) => {
                return anchors
                    .filter(a => {
                        try { return new URL(a.href).origin === pageOrigin; }
                        catch { return false; }
                    })
                    .slice(0, 10)
                    .map(a => a.href);
            },
            origin,
        );

        for (const link of links.slice(0, 2)) {
            try {
                await page.goto(link, { waitUntil: 'networkidle2', timeout: 60000 });
                await page.evaluate(() => window.scrollBy(0, window.innerHeight * 0.5));
                await sleep(2000 + Math.random() * 1000);  // 2-3s on sub-page
            } catch {
                // Individual sub-navigation failures are non-fatal
            }
        }
    } finally {
        await page.close();
    }
}

// ---------------------------------------------------------------------------
// Auto-surf: visit all sites with bounded concurrency
// ---------------------------------------------------------------------------

async function autoSurf(browser, sites, concurrency, pushProgress) {
    const queue = [...sites];
    let completed = 0;
    const total = sites.length;

    const workers = Array(concurrency).fill(null).map(async () => {
        while (queue.length > 0) {
            const url = queue.shift();
            completed++;
            const num = completed;
            console.log(`[${num}/${total}] ${url}`);

            pushProgress({ current: num, total, url, status: 'loading', tabsOpen: concurrency });

            try {
                await visitPage(browser, url);
                pushProgress({ current: num, total, url, status: 'done', tabsOpen: concurrency });
                console.log(`  \u2713 done`);
            } catch (e) {
                pushProgress({ current: num, total, url, status: 'error', tabsOpen: concurrency });
                console.log(`  \u2717 ${e.message.substring(0, 60)}`);
            }
        }
    });

    await Promise.all(workers);
}

// ---------------------------------------------------------------------------
// Retest failed flows via Swift test suite
// ---------------------------------------------------------------------------

async function retestFailed() {
    const projectDir = path.resolve(__dirname, '../..');
    const packageDir = path.join(projectDir, 'native/TunnelServices');

    try {
        console.log('Running failed flow retest...');
        execSync(
            `swift test --package-path "${packageDir}" --filter RetestFailedFlows`,
            { stdio: 'inherit', timeout: 120000, cwd: projectDir },
        );
    } catch (e) {
        console.error('Retest error:', e.message);
    }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
    const PROXY_PORT = args.proxyPort;
    const DASHBOARD_PORT = args.dashboardPort;
    const CONCURRENCY = args.concurrency;

    console.log('=== Knot Browser Test ===');
    console.log(`Proxy: 127.0.0.1:${PROXY_PORT}`);
    console.log(`Dashboard: http://localhost:${DASHBOARD_PORT}`);
    console.log('');

    // Connect to dashboard WebSocket for live progress updates
    let dashWs = null;
    try {
        dashWs = new WebSocket(`ws://localhost:${DASHBOARD_PORT}/ws`);
        dashWs.on('open', () => console.log('Connected to dashboard WebSocket'));
        dashWs.on('error', () => {}); // Ignore dashboard connection errors
    } catch {
        // Dashboard may not be running — that is fine
    }

    function pushProgress(data) {
        if (dashWs && dashWs.readyState === WebSocket.OPEN) {
            dashWs.send(JSON.stringify({ type: 'surf_progress', data }));
        }
    }

    // Launch Chromium through Puppeteer with proxy settings
    const browser = await puppeteer.launch({
        headless: 'new',
        args: [
            `--proxy-server=127.0.0.1:${PROXY_PORT}`,
            '--ignore-certificate-errors',
            '--no-first-run',
            '--disable-default-apps',
            '--disable-extensions',
            '--disable-background-networking',
            '--disable-sync',
            '--disable-component-update',
            '--disable-domain-reliability',
            '--disable-features=OptimizationHints,NetworkService',
            '--no-proxy-server-for=localhost,127.0.0.1',
        ],
        defaultViewport: null,
    });

    if (args.auto) {
        // Auto-surf mode
        const sitesFile = args.sites || path.join(__dirname, 'sites.json');
        const sites = JSON.parse(fs.readFileSync(sitesFile, 'utf8'));
        console.log(`Auto-surfing ${sites.length} sites (concurrency: ${CONCURRENCY})...`);

        await autoSurf(browser, sites, CONCURRENCY, pushProgress);

        console.log('\nAuto-surf complete.');

        if (!args.thenManual) {
            await browser.close();
        } else {
            console.log('Switching to manual mode. Close browser when done.');
            await new Promise(r => browser.on('disconnected', r));
        }
    } else {
        // Manual mode — just keep the browser open
        console.log('Manual mode. Browse freely. Close browser when done.');
        await new Promise(r => browser.on('disconnected', r));
    }

    console.log('\nBrowser closed. Analyzing failed requests...');

    // Clean up dashboard WebSocket
    if (dashWs) dashWs.close();

    // Run retest of failed flows
    await retestFailed();

    console.log('Done.');
}

main().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
});
