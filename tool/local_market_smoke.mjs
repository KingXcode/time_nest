// Real Chrome verification against the running localhost service; no fixtures.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const origin = new URL(process.argv[2] || 'http://127.0.0.1:8787').origin;
assert.equal(new URL(origin).hostname, '127.0.0.1');
const output = path.resolve(process.argv[3] || path.join(root, '../local_market_evidence'));
assert(!output.startsWith(root), 'Keep real-data evidence outside the Git checkout');
await mkdir(output, { recursive: true });
const profile = await mkdtemp(path.join(output, 'chrome-profile-'));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=0',
  `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
  '--disable-background-networking', '--disable-component-update', '--disable-sync',
  '--window-size=1280,1000', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let browserLog = '', launchError;
chrome.stderr.on('data', chunk => { browserLog += chunk; });
chrome.on('error', error => { launchError = error; });
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(check, label, timeout = 45000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (launchError) throw launchError;
    if (await check()) return;
    await delay(100);
  }
  throw new Error(`Timed out: ${label}`);
}
const checks = [], requests = [], errors = [], series = {};
function passed(value) { checks.push(value); console.log(`PASS: ${value}`); }
let ws, send, evaluate;
const deepQuery = `(selector) => {
  const result = [];
  function walk(root) {
    result.push(...root.querySelectorAll(selector));
    for (const element of root.querySelectorAll('*')) if(element.shadowRoot) walk(element.shadowRoot);
  }
  walk(document); return result;
}`;
async function labels() {
  return evaluate(`(${deepQuery})('[aria-label],flt-semantics').flatMap(e => [e.getAttribute('aria-label') || '',e.textContent || '']).join(String.fromCharCode(10))`);
}
async function findLabel(label) {
  return evaluate(`(() => {
    const nodes = (${deepQuery})('[aria-label],flt-semantics');
    const element = nodes.filter(e => [e.getAttribute('aria-label') || '',e.textContent || ''].some(text => text.trim() === ${JSON.stringify(label)} || text.split(String.fromCharCode(10)).includes(${JSON.stringify(label)})))
      .filter(e => e.getBoundingClientRect().width > 0)
      .sort((a,b) => a.getBoundingClientRect().width * a.getBoundingClientRect().height - b.getBoundingClientRect().width * b.getBoundingClientRect().height)[0];
    if (!element) return null;
    const r = element.getBoundingClientRect();
    return {x:r.x, y:r.y, width:r.width, height:r.height, viewport:window.innerHeight};
  })()`);
}
async function click(x, y) {
  await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
}
async function wheel(deltaY) {
  const dimensions = await evaluate('({width:innerWidth,height:innerHeight})');
  await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: dimensions.width / 2,
    y: dimensions.height / 2, deltaX: 0, deltaY });
  await delay(180);
}
async function visible(label) {
  for (let attempt = 0; attempt < 12; attempt++) {
    const r = await findLabel(label);
    if (r && r.width > 0 && r.y >= 0 && r.y + r.height <= r.viewport - 5) return r;
    await wheel(r ? r.y - r.viewport / 2 : 320);
  }
  throw new Error(`Cannot reveal ${label}; labels: ${await labels()}`);
}
async function activate(label) {
  const r = await visible(label);
  await click(r.x + r.width / 2, r.y + r.height / 2);
  await delay(200);
}
async function screenshot(name) {
  const result = await send('Page.captureScreenshot', { format: 'png' });
  await writeFile(path.join(output, name), Buffer.from(result.data, 'base64'));
}
const selectedText = row => `${row.date} · 收盘 ${row.close.toFixed(2)} 点`;

try {
  for (const id of ['shanghai', 'csi300', 'shenzhen']) {
    const response = await fetch(`${origin}/api/market-history?index=${id}`);
    assert.equal(response.status, 200);
    const data = await response.json();
    assert(data.rows.length > 1, 'Real series required; never substitute fixtures');
    assert.equal(data.indexId, id);
    assert.equal(data.freshness, 'unverified');
    series[id] = data;
  }
  passed('Three real index series returned by the local BaoStock service');
  await waitFor(async () => {
    try { await readFile(path.join(profile, 'DevToolsActivePort')); return true; } catch { return false; }
  }, 'Chrome debug port');
  const port = Number((await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]);
  const target = await (await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: 'PUT' })).json();
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, { once: true }); ws.addEventListener('error', reject, { once: true }); });
  const pending = new Map(); let next = 0;
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id) {
      const item = pending.get(message.id);
      if (!item) return;
      pending.delete(message.id); clearTimeout(item.timer);
      if (message.error) item.reject(new Error(JSON.stringify(message.error))); else item.resolve(message.result);
    } else if (message.method === 'Runtime.exceptionThrown') {
      errors.push(message.params.exceptionDetails.exception?.description || message.params.exceptionDetails.text);
    } else if (message.method === 'Network.requestWillBeSent') requests.push(message.params.request.url);
  });
  send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++next;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout ${method}`)); }, 20000);
    pending.set(id, { resolve, reject, timer });
    ws.send(JSON.stringify({ id, method, params }));
  });
  evaluate = async expression => {
    const result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
    return result.result.value;
  };
  await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1280, height: 1000, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: origin + '/' });
  await waitFor(() => evaluate('Boolean(window.shike && !document.getElementById("loading") && document.querySelector("flutter-view,flt-glass-pane"))'), 'Flutter rendered');
  await evaluate(`(${deepQuery})('flt-semantics-placeholder').forEach(e => e.click())`);
  await delay(250);
  // The initial clock exposes this fixed top-right icon visually; the tooltip
  // is not yet an aria-label until the first pointer interaction.
  await click(1240, 32);
  await delay(300);
  await activate('A股行情');
  await waitFor(async () => (await labels()).includes(selectedText(series.shanghai.rows.at(-1))), 'real Shanghai close rendered');
  assert.equal(await evaluate('document.querySelectorAll("iframe").length'), 0);
  passed('Live market route renders the Flutter chart with real dated values, without iframe');
  await screenshot('desktop-shanghai.png');

  const beforeSelection = requests.filter(url => url.includes('/api/market-history')).length;
  const plotLabel = `${series.shanghai.rows.length} 个交易日的收盘走势，详细值可用下方日期选择器查看。`;
  const plot = await visible(plotLabel);
  await click(plot.x + 8, plot.y + plot.height / 2);
  await waitFor(async () => (await labels()).includes(selectedText(series.shanghai.rows[0])), 'chart date selection', 5000);
  const slider = await evaluate(`(() => {
    const e=(${deepQuery})('[role="slider"]')[0];if(!e)return null;
    const ancestors=[];for(let p=e;p&&ancestors.length<5;p=p.parentElement){const r=p.getBoundingClientRect();ancestors.push({tag:p.tagName,role:p.getAttribute('role'),x:r.x,y:r.y,width:r.width,height:r.height});}
    return {html:e.outerHTML,ancestors};
  })()`);
  assert(slider);
  console.log('Slider geometry: ' + JSON.stringify(slider));
  const bounds = slider.ancestors.find(r => r.width > 100 && r.height >= 24 && r.height <= 100);
  assert(bounds, 'Slider widget bounds must be present');
  await click(bounds.x + bounds.width - 24, bounds.y + bounds.height / 2);
  await waitFor(async () => (await labels()).includes(selectedText(series.shanghai.rows.at(-1))), 'pointer slider date selection', 5000);
  assert.equal(requests.filter(url => url.includes('/api/market-history')).length, beforeSelection);
  passed('Chart touch and date slider change the displayed close without new API requests');

  for (const [id, label] of [['csi300', '沪深300'], ['shenzhen', '深证成指']]) {
    await activate(label);
    await waitFor(async () => (await labels()).includes(selectedText(series[id].rows.at(-1))), `switch ${id}`);
  }
  passed('Switching CSI300 and Shenzhen shows each matching real series');
  await screenshot('desktop-shenzhen.png');
  await activate('重新获取');
  await waitFor(async () => (await labels()).includes('重新获取'), 'refresh completes');
  assert(requests.some(url => url.includes('refresh=1')));
  passed('Refresh uses the local API and preserves the actual closing date');

  await send('Network.setBlockedURLs', { urls: [`${origin}/api/market-history*`] });
  await activate('重新获取');
  await waitFor(async () => (await labels()).includes('暂时无法获取收盘历史，请稍后重试。'), 'explicit request failure');
  assert((await labels()).includes('保留上次获取结果，可能已过时。'));
  assert((await labels()).includes(selectedText(series.shenzhen.rows.at(-1))));
  await screenshot('refresh-failure-retains-data.png');
  await send('Network.setBlockedURLs', { urls: [] });
  await activate('重新获取');
  await waitFor(async () => !(await labels()).includes('暂时无法获取收盘历史，请稍后重试。') && (await labels()).includes('重新获取'), 'retry recovers');
  passed('Blocked API refresh retains the old dated chart with a warning; retry recovers');

  await send('Emulation.setDeviceMetricsOverride', { width: 320, height: 950, deviceScaleFactor: 1, mobile: false });
  await wheel(-2500);
  await screenshot('mobile-320-top.png');
  await visible(selectedText(series.shenzhen.rows.at(-1)));
  await screenshot('mobile-320-details.png');
  assert((await labels()).includes('仅供个人研究，不构成投资建议。数据可能延迟或缺失；获取时间不代表交易日期，也不保证数据已经更新至最新交易日。'));
  passed('320px viewport remains scrollable with chart, date and personal-research notice');
  assert.deepEqual(requests.filter(url => /^https?:/.test(url) && !url.startsWith(origin + '/')), []);
  assert.deepEqual(errors, []);
  passed('Browser makes no external HTTP requests and has no JavaScript exceptions');
  await writeFile(path.join(output, 'report.json'), JSON.stringify({ status: 'passed', generatedAt: new Date().toISOString(),
    origin, browser: await send('Browser.getVersion'), checks, requests, errors,
    indices: Object.fromEntries(Object.entries(series).map(([id, value]) => [id, {
      rows: value.rows.length, asOf: value.rows.at(-1).date, close: value.rows.at(-1).close, fetchedAt: value.fetchedAt,
    }])),
  }, null, 2));
  console.log(`Evidence: ${output}`);
} catch (error) {
  if (send) {
    try { await screenshot('failure.png'); await writeFile(path.join(output, 'failure-labels.txt'), await labels()); } catch { /* Browser may have exited. */ }
  }
  await writeFile(path.join(output, 'failure.json'), JSON.stringify({ error: error.stack, checks, errors, browserLog }, null, 2));
  console.error(error.stack); process.exitCode = 1;
} finally {
  if (ws) ws.close();
  chrome.kill('SIGTERM');
  await Promise.race([new Promise(resolve => chrome.once('exit', resolve)), delay(3000)]);
}
