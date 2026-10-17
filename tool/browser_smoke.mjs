#!/usr/bin/env node
// Real Chromium checks using CDP and Node built-ins; no browser-test dependency.
// Run after bash tool/build_web.sh. Set CHROME_BIN on non-macOS machines.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, mkdtemp } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { collectBuildFiles, renderServiceWorker } from './generate_sw.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = path.join(root, 'build/verification');
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
  const base = url.pathname.startsWith('/time_nest/') ? '/time_nest/' : '/';
  const name = decodeURIComponent(url.pathname.slice(base.length)) || 'index.html';
  const bytes = bundle(base, version).get(name);
  if (!bytes) { response.writeHead(404); response.end('Not found'); return; }
  response.writeHead(200, { 'Content-Type': types[path.extname(name)] || 'application/octet-stream',
    'Cache-Control': 'no-store' });
  response.end(bytes);
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
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
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
  return p.evaluate(`(${deepQuery})('[aria-label]').map(e => ({role:e.getAttribute('role'), label:e.getAttribute('aria-label'), checked:e.getAttribute('aria-checked')}))`);
}
function passed(name) { checks.push(name); console.log(`PASS ${name}`); }
try {
  port = await waitFor(async () => Number((await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]), 'Chrome debugging endpoint');
  page = await connect();
  await page.navigate(origin + '/');
  await ready(); await offlineReady();
  assert.match(await page.evaluate('document.title'), /此刻/);
  const manifest = await page.evaluate('fetch("manifest.json").then(r=>r.json())');
  assert.equal(manifest.name, '此刻'); assert.equal(manifest.orientation, 'any');
  await page.screenshot('01-first-open.png');
  passed('release app, branding, valid manifest and complete precache');
  await enableSemantics();
  // Persist first-run dismissal using its public bridge and reload to a clean face.
  await page.evaluate('shike.markIntroSeen()');
  await page.send('Page.reload'); await ready(); await enableSemantics();
  await page.screenshot('02-desktop.png');
  await page.send('Emulation.setDeviceMetricsOverride', { width: 736, height: 414, deviceScaleFactor: 1, mobile: false });
  await delay(400); await page.screenshot('03-landscape.png');
  await click(100, 100); await delay(250); await click(690, 36); await delay(500);
  await page.screenshot('04-settings.png');
  await writeFile(path.join(output, 'semantics.json'), JSON.stringify(await labels(), null, 2));
  await page.evaluate(`(${deepQuery})('[role="switch"]').find(e => e.getAttribute('aria-label') === '显示秒').click()`);
  await waitFor(() => page.evaluate('JSON.parse(shike.readSettings()).showSeconds === false'), 'UI setting saved');
  await waitFor(async () => (await labels()).some(item => item.label === '显示秒' && item.checked === 'false'), 'switch semantics updated');
  await page.evaluate(`(${deepQuery})('[role="switch"]').find(e => e.getAttribute('aria-label') === '显示秒').click()`);
  await waitFor(() => page.evaluate('JSON.parse(shike.readSettings()).showSeconds === true'), 'UI setting restored');
  await key('Escape', 'Escape', 27); await delay(400);
  assert.equal((await labels()).some(item => item.role === 'switch'), false, 'Escape closes settings');
  passed('real settings switch persists changes; Escape dismisses the panel');
  await page.send('Emulation.setDeviceMetricsOverride', { width: 414, height: 736, deviceScaleFactor: 1, mobile: false });
  await delay(500); await page.screenshot('05-portrait.png');
  passed('desktop, landscape, portrait and settings screenshots');
  const custom = { version: 1, hourCycle: 'h12', showSeconds: false, showMilliseconds: true,
    textIntensity: .7, nightMode: { enabled: true, start: '22:00', end: '07:00', textIntensity: .25 }, keepAwake: false };
  await page.evaluate(`shike.writeSettings(${JSON.stringify(JSON.stringify(custom))})`);
  await page.send('Network.emulateNetworkConditions', { offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0 });
  await page.send('Page.reload'); await ready(); await offlineReady();
  assert.deepEqual(await page.evaluate('JSON.parse(shike.readSettings())'), custom);
  await page.screenshot('06-offline.png');
  passed('offline reload renders Flutter and retains settings');
  await page.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  // Two documents stay on consistent versions. Neither reloads just for discovery.
  const other = await connect(); await other.navigate(origin + '/'); await ready(other); await offlineReady(other);
  await other.evaluate('window.__sameDocument = true');
  await page.evaluate('window.__sameDocument = true');
  version = 2;
  await page.evaluate('shike.checkForUpdate()');
  await waitFor(() => page.evaluate('JSON.parse(shike.getState()).updateAvailable'), 'waiting update');
  assert.equal(await page.evaluate('window.__sameDocument'), true);
  await page.evaluate('shike.applyUpdate()');
  await waitFor(() => page.evaluate('window.__sameDocument === undefined && Boolean(window.shike)'), 'accepted reload');
  await ready(); await offlineReady();
  assert.equal(await other.evaluate('window.__sameDocument'), true);
  await waitFor(() => other.evaluate('JSON.parse(shike.getState()).updateAvailable'), 'old tab retains update action');
  assert.match(await other.evaluate('fetch("index.html").then(r=>r.text())'), /smoke-version-1/);
  await other.evaluate('shike.applyUpdate()');
  await waitFor(() => other.evaluate('window.__sameDocument === undefined && Boolean(window.shike)'), 'second tab confirmation');
  await ready(other);
  passed('update waits for confirmation; second tab stays old and can confirm later');
  // Partial eviction should recover only hash-matching bytes while online.
  await page.evaluate(`(async()=>{for(const name of await caches.keys()) if(name.includes(':version:')) {
    const cache=await caches.open(name); await cache.delete(new URL('index.html',document.baseURI).href);
  }})()`);
  await page.send('Page.reload'); await ready(); await offlineReady();
  passed('evicted current entry repairs from verified online assets');
  const sub = await connect(); await sub.navigate(origin + '/time_nest/'); await ready(sub); await offlineReady(sub);
  assert.equal(await sub.evaluate('document.baseURI'), origin + '/time_nest/');
  await sub.send('Network.emulateNetworkConditions', { offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0 });
  await sub.send('Page.reload'); await ready(sub); await offlineReady(sub);
  passed('subpath deployment and offline navigation');
  const denied = await connect();
  await denied.send('Page.addScriptToEvaluateOnNewDocument', { source: `Object.defineProperty(window, 'localStorage', { get() { throw new DOMException('blocked', 'SecurityError'); } });` });
  await denied.navigate(origin + '/'); await ready(denied);
  assert.equal(await denied.evaluate('JSON.parse(shike.getState()).storageAvailable'), false);
  assert.equal(await denied.evaluate('shike.writeSettings("test")'), false);
  passed('blocked localStorage still renders the clock and reports unavailable');
  const external = [...requests].filter(url => /^https?:/.test(url) && !url.startsWith(origin + '/'));
  assert.deepEqual(external, [], 'App must not request CDN fonts/renderers');
  assert.deepEqual(errors, [], 'Unexpected JavaScript exceptions');
  passed('no external app requests or JavaScript exceptions');
  await writeFile(path.join(output, 'report.json'), JSON.stringify({ status: 'passed', generatedAt: new Date().toISOString(), releaseFingerprint: renderServiceWorker(files, template).manifest.version, browser: await page.send('Browser.getVersion'), origin, checks, errors, requests: [...requests] }, null, 2));
  console.log(`Verified ${checks.length} scenarios. Screenshots/report: ${output}`);
} catch (error) {
  if (page) {
    try { await page.screenshot('failure.png'); } catch { /* Chrome may have exited */ }
    try { await writeFile(path.join(output, 'failure-dom.json'), JSON.stringify(await labels(), null, 2)); } catch { /* no live page */ }
  }
  await writeFile(path.join(output, 'failure.json'), JSON.stringify({ error: error.stack, checks, errors, browserLog }, null, 2));
  console.error(error.stack);
  process.exitCode = 1;
} finally {
  for (const ws of sockets) ws.close();
  chrome.kill('SIGTERM');
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
