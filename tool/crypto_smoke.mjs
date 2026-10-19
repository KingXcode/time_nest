#!/usr/bin/env node
// Live Binance market and UI checks in isolated Chrome; requires network access.
// Run after bash tool/build_web.sh. Set CHROME_BIN on non-macOS machines.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, mkdtemp } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { collectBuildFiles, renderServiceWorker } from './generate_sw.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.join(root, 'build/crypto-verification');
await mkdir(output, { recursive: true });
const files = await collectBuildFiles(path.join(root, 'build/web'));
const template = await readFile(path.join(root, 'web/sw.template.js'), 'utf8');
const bundles = new Map();
function bundle(base, version) {
  const key = `${base}:${version}`;
  if (bundles.has(key)) return bundles.get(key);
  const entries = files.map(file => file.path === 'index.html' ? {
    path: file.path,
    bytes: Buffer.from(file.bytes.toString().replace(/<base href="[^"]*">/, `<base href="${base}">`)
      + `\n<!-- smoke-version-${version} -->`),
  } : file);
  const result = new Map(entries.map(file => [file.path, file.bytes]));
  result.set('shike-sw.js', Buffer.from(renderServiceWorker(entries, template).source));
  bundles.set(key, result);
  return result;
}
let version = 1;
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript',
  '.json': 'application/json', '.wasm': 'application/wasm', '.ttf': 'font/ttf', '.png': 'image/png' };
const server = createServer((request, response) => {
  const url = new URL(request.url, 'http://localhost');
  const base = url.pathname.startsWith('/time_nest/') ? '/time_nest/' : url.pathname.startsWith('/slow/') ? '/slow/' : url.pathname.startsWith('/no-loading/') ? '/no-loading/' : '/';
  const name = decodeURIComponent(url.pathname.slice(base.length)) || 'index.html';
  const bytes = base === '/no-loading/' && name === 'loading.js' ? null : bundle(base, version).get(name);
  if (!bytes) { response.writeHead(404); response.end('Not found'); return; }
  response.writeHead(200, { 'Content-Type': types[path.extname(name)] || 'application/octet-stream',
    'Cache-Control': 'no-store' });
  if (base === '/slow/' && name === 'main.dart.js') setTimeout(() => response.end(bytes), 1800);
  else response.end(bytes);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const profile = await mkdtemp(path.join(output, 'chrome-profile-'));
const chrome = spawn(process.env.CHROME_BIN || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
  '--no-first-run', '--no-default-browser-check', '--disable-background-networking',
  '--disable-component-update', '--disable-sync', '--window-size=1280,720', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let browserLog = '';
chrome.stderr.on('data', data => { browserLog += data; });
let launchError;
chrome.on('error', error => { launchError = error; });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(check, label, timeout = 45000) {
  const end = Date.now() + timeout;
  let last;
  while (Date.now() < end) {
    try { const result = await check(); if (result) return result; } catch (error) { last = error; }
    if (launchError) throw launchError;
    await delay(100);
  }
  throw new Error(`Timed out: ${label}${last ? ` (${last.message})` : ''}`);
}
const sockets = [];
const checks = [];
const errors = [];
const requests = new Set();
let page;
let port;
const deepQuery = `(selector) => {
  const result = [];
  function walk(root) {
    result.push(...root.querySelectorAll(selector));
    for (const element of root.querySelectorAll('*')) if (element.shadowRoot) walk(element.shadowRoot);
  }
  walk(document); return result;
}`;
async function connect(url = 'about:blank') {
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' })).json();
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  sockets.push(ws);
  await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, { once: true }); ws.addEventListener('error', reject, { once: true }); });
  let next = 0;
  const pending = new Map();
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id) {
      const item = pending.get(message.id);
      if (!item) return;
      pending.delete(message.id); clearTimeout(item.timer);
      if (message.error) item.reject(new Error(JSON.stringify(message.error))); else item.resolve(message.result);
    } else if (message.method === 'Runtime.exceptionThrown') {
      errors.push(message.params.exceptionDetails.exception?.description || message.params.exceptionDetails.text);
    } else if (message.method === 'Network.requestWillBeSent') {
      requests.add(message.params.request.url);
    }
  });
  function send(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = ++next;
      const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 20000);
      pending.set(id, { resolve, reject, timer });
      ws.send(JSON.stringify({ id, method, params }));
    });
  }
  async function evaluate(expression) {
    const result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
    return result.result.value;
  }
  await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 1280, deviceScaleFactor: 1, mobile: false });
  return { send, evaluate, target, async navigate(url) { await send('Page.navigate', { url }); },
    async screenshot(name) { const image = await send('Page.captureScreenshot', { format: 'png' }); await writeFile(path.join(output, name), Buffer.from(image.data, 'base64')); },
  };
}
async function ready(p = page) {
  await waitFor(() => p.evaluate('Boolean(window.shike && !document.getElementById("loading") && document.querySelector("flutter-view,flt-glass-pane"))'), 'Flutter rendered');
}
async function offlineReady(p = page) {
  await waitFor(() => p.evaluate('window.shike && JSON.parse(shike.getState()).offlineStatus === "ready"'), 'complete offline cache', 90000);
}
async function click(x, y, p = page) {
  await p.send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await p.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
}
async function key(key, code, virtualKey, p = page) {
  await p.send('Input.dispatchKeyEvent', { type: 'keyDown', key, code, windowsVirtualKeyCode: virtualKey });
  await p.send('Input.dispatchKeyEvent', { type: 'keyUp', key, code, windowsVirtualKeyCode: virtualKey });
}
async function enableSemantics(p = page) {
  await p.evaluate(`(${deepQuery})('flt-semantics-placeholder').forEach(e => e.click())`);
  await delay(250);
}
async function labels(p = page) {
  return p.evaluate(`(${deepQuery})('flt-semantics, [aria-label]').map(e => ({role:e.getAttribute('role'), label:e.getAttribute('aria-label') || e.textContent, checked:e.getAttribute('aria-checked')}))`);
}
async function activate(label, p = page) {
  const point = await p.evaluate(`(() => {
    const nodes = (${deepQuery})('[role="button"], [role="menuitem"], [role="menuitemcheckbox"], [role="checkbox"], [role="group"]');
    const element = nodes.find(e => (e.getAttribute('aria-label') || e.textContent).trim().split('\\n').includes(${JSON.stringify(label)}));
    if (!element) throw new Error('Missing control: ' + ${JSON.stringify(label)} + ' available=' + nodes.map(e=>e.getAttribute('aria-label') || e.textContent).join('|'));
    const box = element.getBoundingClientRect(); return {x: box.x + box.width/2, y: box.y + box.height/2};
  })()`);
  await click(point.x, point.y, p); await delay(350);
}
async function showToolbar(p = page) { await click(5, 5, p); await delay(250); }
function passed(name) { checks.push(name); console.log(`PASS ${name}`); }
try {
  port = await waitFor(async () => Number((await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]), 'Chrome debugging endpoint');
  page = await connect();
  await page.send('Page.addScriptToEvaluateOnNewDocument', { source: `localStorage.setItem('shike.intro.v1','1');` });
  await page.navigate(origin + '/'); await ready(); await enableSemantics();
  await activate('每日看板');
  assert.equal([...requests].filter(url => url.includes('data-api.binance.vision')).length, 0);
  await activate('数字货币行情');
  await waitFor(async () => (await labels()).some(item => item.label?.includes('报价截至')), 'live UI quote timestamp');
  await waitFor(async () => (await labels()).some(item => item.label?.includes('点击图表或拖动滑杆')), 'live UI candles');
  assert.ok([...requests].some(url => url.includes('data-api.binance.vision/api/v3/ticker/24hr')));
  assert.ok([...requests].some(url => url.includes('data-api.binance.vision/api/v3/klines')));
  // Read through the production bridge, including browser CORS and validation.
  const quotes = await page.evaluate(`timeNestDashboard.request('cryptoQuotes','{}').then(JSON.parse)`);
  assert.equal(quotes.stale, false); assert.equal(quotes.data.quotes.length, 6);
  assert.ok(quotes.data.quotes.some(q => q.symbol === 'BTCUSDT' && q.price > 0));
  assert.ok(quotes.data.quotes.some(q => q.symbol === 'ETHUSDT' && q.price > 0));
  const btc = await page.evaluate(`timeNestDashboard.request('cryptoCandles',JSON.stringify({symbol:'BTCUSDT',interval:'1h'})).then(JSON.parse)`);
  assert.equal(btc.stale, false); assert.equal(btc.data.candles.length, 120);
  passed('actual Binance browser requests return six spot quotes and 120 BTC candles without credentials');
  await page.screenshot('01-crypto-desktop.png');
  // Flutter semantics represents the entire card as one tappable node.
  const ethPoint = await page.evaluate(`(() => {
    const node = (${deepQuery})('flt-semantics, [aria-label]').find(e => (e.getAttribute('aria-label') || e.textContent || '').startsWith('ETH · 以太坊'));
    if (!node) throw new Error('ETH card missing'); const r=node.getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2};
  })()`);
  await click(ethPoint.x, ethPoint.y);
  await waitFor(() => page.evaluate(`JSON.parse(timeNestDashboard.readPreferences()).cryptoSymbol === 'ETHUSDT'`), 'ETH choice saved');
  await waitFor(async () => (await labels()).some(item => item.label === 'ETH / USDT'), 'ETH selection rendered');
  await waitFor(() => [...requests].some(url => url.includes('symbol=ETHUSDT') && url.includes('interval=1h')), 'ETH hourly request');
  await activate('日线');
  await waitFor(() => page.evaluate(`JSON.parse(timeNestDashboard.readPreferences()).cryptoInterval === '1d'`), 'daily period saved');
  await waitFor(() => [...requests].some(url => url.includes('symbol=ETHUSDT') && url.includes('interval=1d')), 'ETH daily request');
  const eth = await page.evaluate(`timeNestDashboard.request('cryptoCandles',JSON.stringify({symbol:'ETHUSDT',interval:'1d'})).then(JSON.parse)`);
  assert.equal(eth.stale, false); assert.equal(eth.data.candles.length, 120);
  await delay(500); await page.screenshot('02-crypto-eth.png');
  passed('ETH card and daily interval select the matching real series and persist');
  await page.send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: false });
  await delay(500); await page.screenshot('03-crypto-mobile.png');
  // Scroll the live Flutter viewport to inspect chart controls on a narrow screen.
  await page.send('Input.dispatchMouseEvent', { type:'mouseWheel', x:200, y:650, deltaX:0, deltaY:900 });
  await delay(600); await page.screenshot('04-crypto-mobile-chart.png');
  await page.send('Page.reload'); await ready(); await enableSemantics();
  await activate('每日看板');
  // Reopening a route is covered in widget tests at 320 px and 2x text.
  const restored = await page.evaluate(`JSON.parse(timeNestDashboard.readPreferences())`);
  assert.equal(restored.cryptoSymbol, 'ETHUSDT'); assert.equal(restored.cryptoInterval, '1d');
  assert.ok(!restored.order?.includes('fx'));
  passed('narrow screenshots captured; saved crypto selection survives a real reload');
  assert.deepEqual(errors, []);
  await writeFile(path.join(output, 'report.json'), JSON.stringify({status:'passed',
    generatedAt:new Date().toISOString(), releaseFingerprint:renderServiceWorker(files, template).manifest.version,
    checks, quotes: quotes.data, btcCandles: btc.data.candles.length, ethCandles: eth.data.candles.length,
    errors, requests:[...requests]}, null, 2));
  console.log(`Verified ${checks.length} scenarios. Screenshots/report: ${output}`);
} catch (error) {
  if (page) {
    try { await page.screenshot('failure.png'); } catch { /* browser may have exited */ }
    try { await writeFile(path.join(output,'failure-dom.json'),JSON.stringify(await labels(),null,2)); } catch { /* unavailable */ }
  }
  let preferences;
  try { preferences = await page?.evaluate('timeNestDashboard.readPreferences()'); } catch { /* unavailable */ }
  await writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,requests:[...requests],preferences,browserLog},null,2));
  console.error(error.stack); process.exitCode=1;
} finally {
  for (const ws of sockets) ws.close(); chrome.kill('SIGTERM');
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
