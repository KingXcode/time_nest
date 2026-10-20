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
assert.ok(!files.some(file => /^market_chart\.(html|js)$/.test(file.path)), 'retired A-share assets must not ship');
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
const requestEvents = [];
const streamFrames = [], streamConnections = [], streamClosed = [];
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
    } else if (message.method === 'Network.webSocketCreated') {
      streamConnections.push({requestId:message.params.requestId,url:message.params.url});
    } else if (message.method === 'Network.webSocketClosed') {
      streamClosed.push(message.params.requestId);
    } else if (message.method === 'Network.webSocketFrameReceived') {
      try { streamFrames.push({id:message.params.requestId, ...JSON.parse(message.params.response.payloadData)}); } catch { /* control frames */ }
    } else if (message.method === 'Network.requestWillBeSent') {
      requests.add(message.params.request.url);
      requestEvents.push(message.params.request.url);
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
async function doubleClick(x,y) {
  await click(x,y); await delay(60); await click(x,y); await delay(350);
}
async function selectPrice(from,to,shift=true) {
  const r=await page.evaluate(`(() => {
    const e=(${deepQuery})('flt-semantics, [aria-label]').find(e=>(e.getAttribute('aria-label')||e.textContent||'').startsWith('K 线主图，'));
    const b=e.getBoundingClientRect();return {x:b.x,y:b.y,width:b.width,height:b.height};
  })()`);
  const left=r.x+4, width=r.width-80, y=r.y+r.height*.75;
  if(shift) await page.send('Input.dispatchKeyEvent',{type:'keyDown',key:'Shift',code:'ShiftLeft',windowsVirtualKeyCode:16,modifiers:8});
  await page.send('Input.dispatchMouseEvent',{type:'mousePressed',x:left+width*from,y,button:'left',buttons:1,clickCount:1,modifiers:shift?8:0});
  for(let i=1;i<=12;i++) {
    await page.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:left+width*(from+(to-from)*i/12),y,button:'left',buttons:1,modifiers:shift?8:0});
    await delay(20);
  }
  await page.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:left+width*to,y,button:'left',buttons:0,clickCount:1,modifiers:shift?8:0});
  if(shift) await page.send('Input.dispatchKeyEvent',{type:'keyUp',key:'Shift',code:'ShiftLeft',windowsVirtualKeyCode:16,modifiers:0});
  await delay(350);
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
  const locate = () => p.evaluate(`(() => {
    const nodes = (${deepQuery})('[role="button"], [role="menuitem"], [role="menuitemcheckbox"], [role="checkbox"], [role="switch"], [role="group"]');
    const element = nodes.find(e => (e.getAttribute('aria-label') || e.textContent).trim().split('\\n').includes(${JSON.stringify(label)}));
    if (!element) throw new Error('Missing control: ' + ${JSON.stringify(label)} + ' available=' + nodes.map(e=>e.getAttribute('aria-label') || e.textContent).join('|'));
    const box = element.getBoundingClientRect(); return {x: box.x + box.width/2, y: box.y + box.height/2, viewport: innerHeight};
  })()`);
  let point=await locate();
  for(let i=0;i<4 && (point.y<0 || point.y>point.viewport);i++) {
    await p.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:point.viewport/2,deltaX:0,deltaY:point.y-point.viewport/2});
    await delay(400);point=await locate();
  }
  assert.ok(point.y>=0 && point.y<=point.viewport,`Control not visible: ${label}`);
  await click(point.x, point.y, p); await delay(350);
}
async function showToolbar(p = page) { await click(5, 5, p); await delay(250); }
function passed(name) { checks.push(name); console.log(`PASS ${name}`); }
async function visibleRange() {
  return (await labels()).find(item => item.label?.startsWith('显示区间：'))?.label;
}
async function dragPrice(older = true, touch = false) {
  async function bounds() {
    return page.evaluate(`(() => {
      const e=(${deepQuery})('flt-semantics, [aria-label]').find(e=>(e.getAttribute('aria-label')||e.textContent||'').startsWith('K 线主图，'));
      if(!e) throw new Error('Price plot semantics missing');
      const r=e.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};
    })()`);
  }
  let rect=await bounds();
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:500,deltaX:0,deltaY:rect.y-150});
  await delay(400); rect=await bounds();
  const left=rect.x+20, right=rect.x+rect.width-90, y=rect.y+rect.height/2;
  const from=older?left:right, to=older?right:left;
  if(touch) await page.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{x:from,y}]});
  else await page.send('Input.dispatchMouseEvent',{type:'mousePressed',x:from,y,button:'left',buttons:1,clickCount:1});
  for(let i=1;i<=12;i++) {
    const x=from+(to-from)*i/12;
    if(touch) await page.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{x,y}]});
    else await page.send('Input.dispatchMouseEvent',{type:'mouseMoved',x,y,button:'left',buttons:1});
    await delay(20);
  }
  if(touch) await page.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  else await page.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:to,y,button:'left',buttons:0,clickCount:1});
  await delay(400);
}
try {
  port = await waitFor(async () => Number((await readFile(path.join(profile, 'DevToolsActivePort'), 'utf8')).split('\n')[0]), 'Chrome debugging endpoint');
  page = await connect();
  await page.send('Page.addScriptToEvaluateOnNewDocument', { source: `localStorage.setItem('shike.intro.v1','1');const OriginalSocket=window.WebSocket;window.__cryptoSockets=[];window.WebSocket=class extends OriginalSocket {constructor(...args){super(...args);window.__cryptoSockets.push(this);}};` });
  await page.navigate(origin + '/'); await ready(); await enableSemantics();
  await page.evaluate(`timeNestDashboard.writePreferences(JSON.stringify({version:4,city:{name:'上海',latitude:31.23,longitude:121.47},order:['market','crypto','weather','news','releases'],favorites:['market','weather'],marketIndex:'shenzhen',marketInterval:'W',cryptoSymbol:'BTCUSDT',cryptoInterval:'1h'}))`);
  await activate('每日看板');
  await waitFor(async()=>!(await labels()).some(item=>item.label==='正在获取最新数据…'),'overview snapshots settled');
  assert.ok((await labels()).some(item=>item.label==='数据总览'));
  assert.ok([...requests].some(url=>url.includes('/ticker/24hr')));
  assert.ok(![...requests].some(url=>url.includes('/klines')));
  assert.equal(streamConnections.length,0,'overview has snapshots, no live chart subscriptions');
  assert.ok(!(await labels()).some(item => /A\s*股/.test(item.label || '')), 'retired A-share navigation is absent');
  await activate('调整入口顺序');
  assert.ok(!(await labels()).some(item => /A\s*股/.test(item.label || '')), 'organizer has no retired entry');
  await activate('保存');
  const migrated = await page.evaluate('JSON.parse(timeNestDashboard.readPreferences())');
  assert.deepEqual(migrated.order, ['crypto','weather','news','releases']);
  assert.deepEqual(migrated.favorites, ['weather']);
  assert.equal(migrated.cryptoSymbol, 'BTCUSDT');
  assert.equal(migrated.cryptoInterval, '1h');
  assert.equal(migrated.city.name, '上海');
  assert.ok(!('marketIndex' in migrated) && !('marketInterval' in migrated));
  assert.ok(![...requests].some(url => /market_chart|tradingview(?:-widget)?\.com|baostock\.com|api\/market-history/.test(url)));
  passed('legacy A-share navigation and saved fields retire safely; city and crypto preferences remain');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1440,height:900,deviceScaleFactor:1,mobile:false});
  await delay(500); await page.screenshot('11-dashboard-desktop.png');
  await page.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
  await delay(500); await page.screenshot('12-dashboard-mobile.png');
  await activate('已收藏 1');
  assert.ok(!(await labels()).some(item=>item.label==='币安现货快照 / USDT / 滚动 24h'));
  await activate('全部功能');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1280,height:1280,deviceScaleFactor:1,mobile:false});
  await delay(500);
  passed('compact overview shows real multi-source snapshots and responsive layout; favorites filter has no chart subscriptions');
  await activate('数字货币行情');
  await waitFor(async () => (await labels()).some(item => item.label?.includes('报价截至')), 'live UI quote timestamp');
  await waitFor(async () => (await labels()).some(item => item.label?.includes('左键平移')), 'live UI candles');
  assert.ok([...requests].some(url => url.includes('data-api.binance.vision/api/v3/ticker/24hr')));
  assert.ok([...requests].some(url => url.includes('data-api.binance.vision/api/v3/klines')));
  // Read through the production bridge, including browser CORS and validation.
  const quotes = await page.evaluate(`timeNestDashboard.request('cryptoQuotes','{}').then(JSON.parse)`);
  assert.equal(quotes.stale, false); assert.equal(quotes.data.quotes.length, 6);
  assert.ok(quotes.data.quotes.some(q => q.symbol === 'BTCUSDT' && q.price > 0));
  assert.ok(quotes.data.quotes.some(q => q.symbol === 'ETHUSDT' && q.price > 0));
  const btc = await page.evaluate(`timeNestDashboard.request('cryptoCandles',JSON.stringify({symbol:'BTCUSDT',interval:'1h'})).then(JSON.parse)`);
  assert.equal(btc.stale, false); assert.equal(btc.data.candles.length, 500);
  passed('actual Binance browser requests return six spot quotes and 500 BTC candles without credentials');
  await waitFor(async () => (await labels()).some(item => item.label?.includes('● 币安实时推送')), 'live stream status');
  await waitFor(() => streamFrames.filter(f=>f.data?.e==='kline' && f.data?.s==='BTCUSDT').length>=2, 'multiple actual BTC pushed candles');
  assert.ok(streamConnections.some(s=>s.url.startsWith('wss://data-stream.binance.vision/stream?streams=')));
  assert.ok(streamFrames.some(f=>f.data?.e==='24hrTicker'));
  const streamStart=streamFrames.length;
  await delay(2200);
  assert.ok(streamFrames.length>streamStart, 'pushes continue without a manual refresh');
  passed('actual WebSocket ticker and kline pushes continue and Flutter reports live');
  await waitFor(()=>streamFrames.filter(f=>f.stream?.endsWith('@depth') && Number.isSafeInteger(f.data?.U) && Number.isSafeInteger(f.data?.u)).length>=2,'multiple real incremental depth events');
  await waitFor(async()=>(await labels()).some(item=>item.label?.includes('实时 · 20档')),'live depth UI');
  assert.ok(streamConnections.some(s=>s.url.includes('btcusdt@depth')));
  assert.ok([...requests].some(raw=>{try{const url=new URL(raw);return url.hostname==='data-api.binance.vision' && url.pathname==='/api/v3/depth' && url.searchParams.get('symbol')==='BTCUSDT' && url.searchParams.get('limit')==='5000';}catch{return false;}}),'local book bootstraps with a real REST snapshot');
  passed('actual Binance diff stream and REST snapshot bootstrap a synchronized local order book on the shared socket');
  await waitFor(()=>streamFrames.some(f=>f.stream==='btcusdt@trade' && f.data?.e==='trade'),'actual raw market trade frames');
  const tapeRows=()=>labels().then(nodes=>nodes.filter(e=>/^(?:\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC\+8\n)?成交 \d+，/.test(e.label||'') && (e.label.match(/成交 \d+，/g)||[]).length===1));
  await waitFor(async()=>(await tapeRows()).length>=10,'raw trades render in the live tape');
  assert.ok(requestEvents.some(url=>url.includes('/api/v3/trades?symbol=BTCUSDT') && url.includes('limit=100')));
  const initialFills=await tapeRows(), fillIds=initialFills.map(e=>Number(e.label.match(/成交 (\d+)，/)[1]));
  assert.equal(new Set(fillIds).size,fillIds.length,'displayed fills never duplicate trade IDs');
  assert.ok(fillIds.every((id,i)=>i===0 || id<fillIds[i-1]),'newest executions appear first');
  assert.ok(initialFills.every(e=>/数量 [\d,]+\.\d{5}，金额 [\d.]+ USDT，时间 \d{2}:\d{2}:\d{2}/.test(e.label)),'BTC quantities use exchange precision and UTC+8 times');
  const matched=initialFills.map(row=>({row,frame:streamFrames.find(f=>f.data?.e==='trade' && f.data.t===Number(row.label.match(/成交 (\d+)，/)[1]))})).filter(item=>item.frame);
  assert.ok(matched.length>0,'displayed IDs match the actual raw stream');
  for(const {row,frame} of matched) assert.ok(row.label.includes(frame.data.m?'主动卖出':'主动买入'));
  passed('recent public fills bootstrap from REST and raw same-socket trades render newest-first with unique IDs, exchange precision and correct aggressor direction');
  const tradeRules=await page.evaluate(`timeNestDashboard.request('cryptoBookRules','{}').then(JSON.parse)`);
  const amountDigits=tradeRules.data.rules.find(r=>r.symbol==='BTCUSDT').quoteAssetPrecision;
  for(const {row,frame} of matched) {
    const displayed=row.label.match(/，金额 ([\d.]+) USDT，/)[1];
    assert.equal(displayed,(Number(frame.data.p)*Number(frame.data.q)).toFixed(amountDigits),'trade amount uses raw execution price and size with the cached quote precision');
  }
  const amountColumns=await page.evaluate(`(() => {
    const nodes=(${deepQuery})('flt-semantics, [aria-label]'), label=e=>e.getAttribute('aria-label')||e.textContent||'';
    const panel=nodes.find(e=>label(e)==='最新成交面板').getBoundingClientRect();
    return ['价格(USDT)','数量(BTC)','金额(USDT)','时间'].map(name=>{
      const e=nodes.find(e=>{const r=e.getBoundingClientRect();return label(e)===name && r.x>=panel.x && r.right<=panel.right;});
      if(!e)throw new Error('Trade column missing: '+name);return e.getBoundingClientRect().x;
    });
  })()`);
  assert.ok(amountColumns.every((x,i)=>i===0 || x>amountColumns[i-1]),'price, quantity, USDT amount and time are four visible ordered columns');
  passed('latest executions show a separate USDT amount column whose full precision matches actual raw price times quantity');
  const conversion = await page.evaluate(`timeNestDashboard.request('cryptoConversion','{}').then(JSON.parse)`);
  assert.equal(conversion.stale, false);
  assert.equal(conversion.data.base, 'USDT');
  assert.ok(conversion.data.USD > 0 && conversion.data.CNY > 0);
  await waitFor(async()=>(await labels()).some(item=>item.label?.includes('≈ $') && item.label?.includes('USD')),'live USD conversion');
  const beforeCurrencySocketCount=streamConnections.length;
  await activate('切换折算货币'); await activate('人民币 CNY');
  await waitFor(async()=>(await labels()).some(item=>item.label?.includes('≈ ¥') && item.label?.includes('CNY')),'live CNY conversion');
  assert.equal(JSON.parse(await page.evaluate('timeNestDashboard.readPreferences()')).cryptoCurrency,'CNY');
  assert.equal(streamConnections.length,beforeCurrencySocketCount,'currency switch keeps Binance feed connected');
  passed('real browser USDT rates load through CORS; USD/CNY switching stores device preference without restarting the market feed');
  const bootstrapRequests=requestEvents.filter(url=>url.includes('/api/v3/depth?')).length;
  const beforeDepthFault=streamConnections.length;
  await page.evaluate(`(() => {
    const originalFetch=window.fetch;
    window.__holdBookSnapshot=true;
    window.fetch=(...args)=>{
      if(window.__holdBookSnapshot && String(args[0]).includes('/api/v3/depth?')) {
        window.__bookRefetchWaiting=true;
        return new Promise((resolve,reject)=>{
          window.__releaseBookSnapshot=()=>originalFetch(...args).then(resolve,reject);
          args[1]?.signal?.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')),{once:true});
        });
      }
      return originalFetch(...args);
    };
    const socket=window.__cryptoSockets.find(s=>s.readyState===WebSocket.OPEN && s.url.includes('btcusdt@depth'));
    if(!socket) throw new Error('Missing live depth socket');
    const handler=socket.onmessage;
    socket.onmessage=event=>{
      const envelope=JSON.parse(event.data);
      if(envelope.stream==='btcusdt@depth') { socket.onmessage=handler;window.__droppedDepth=envelope.data;return; }
      handler.call(socket,event);
    };
  })()`);
  await waitFor(()=>page.evaluate('window.__bookRefetchWaiting===true'),'a dropped real diff triggers REST rebootstrap');
  await waitFor(async()=>(await labels()).some(item=>item.label?.includes('同步中 · 旧快照')),'gap labels the frozen copy after Flutter paints the pending REST state');
  assert.ok((await labels()).some(item=>item.label?.includes('● 币安实时推送')),'price/candle connection remains live during book rebootstrap');
  await page.screenshot('22-orderbook-resynchronizing.png');
  await page.evaluate('window.__holdBookSnapshot=false;window.__releaseBookSnapshot()');
  await waitFor(async()=>(await labels()).some(item=>item.label?.includes('实时 · 20档')),'local copy recovers after missing a real event');
  assert.ok(requestEvents.filter(url=>url.includes('/api/v3/depth?')).length>bootstrapRequests);
  assert.equal(streamConnections.length,beforeDepthFault,'book gap recovery does not reconnect the ticker/kline socket');
  passed('dropping a real diff freezes the old book, refetches a snapshot and resumes without interrupting live prices/candles');

  async function bookGeometry() {
    return page.evaluate(`(() => {
      const nodes=(${deepQuery})('flt-semantics, [aria-label]');
      const rect=prefix=>{const e=nodes.find(e=>(e.getAttribute('aria-label')||e.textContent||'').startsWith(prefix));if(!e)throw new Error('Missing geometry '+prefix);const r=e.getBoundingClientRect();return {x:r.x,y:r.y,right:r.right,bottom:r.bottom,width:r.width,height:r.height};};
      return {plot:rect('K 线主图，'),frame:rect('K 线图表区域'),book:rect('订单簿面板'),lastPane:rect('RSI 相对强弱 副图，'),assessment:rect('技术指标 · 买入参考'),trades:rect('最新成交面板')};
    })()`);
  }
  let bookBoxes=await bookGeometry();
  assert.ok(bookBoxes.book.x>=bookBoxes.plot.right,'desktop book is to the right of the chart');
  assert.ok(Math.abs(bookBoxes.book.y-bookBoxes.frame.y)<1,'desktop order book and chart frame share a top border');
  assert.ok(bookBoxes.trades.x>=bookBoxes.book.right,'latest trades are the far-right desktop column');
  assert.ok(Math.abs(bookBoxes.trades.y-bookBoxes.frame.y)<1,'all three desktop panels share a top border');
  await page.screenshot('33-latest-trades-desktop.png');
  await page.screenshot('19-orderbook-desktop.png');
  await page.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});await delay(500);
  bookBoxes=await bookGeometry();
  assert.ok(bookBoxes.book.y>bookBoxes.lastPane.bottom && bookBoxes.book.y<bookBoxes.assessment.y,'portrait book is below subcharts and above assessment');
  assert.ok(bookBoxes.trades.y>bookBoxes.book.bottom,'portrait latest trades follow the order book');
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:400,deltaX:0,deltaY:bookBoxes.book.y-100});await delay(500);
  await page.screenshot('20-orderbook-portrait.png');
  await page.send('Emulation.setDeviceMetricsOverride',{width:844,height:390,deviceScaleFactor:1,mobile:false});await delay(500);
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:200,deltaX:0,deltaY:-10000});await delay(500);
  bookBoxes=await bookGeometry();assert.ok(bookBoxes.book.x>=bookBoxes.plot.right,'phone landscape book is to the right');
  assert.ok(Math.abs(bookBoxes.book.y-bookBoxes.frame.y)<1,'landscape order book and chart frame share a top border');
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:200,deltaX:0,deltaY:bookBoxes.plot.y-150});await delay(500);
  await page.screenshot('21-orderbook-landscape.png');
  await activate('只看买盘');
  assert.ok(!(await labels()).some(e=>e.label?.startsWith('卖盘 ')),'single bid view hides asks');
  await activate('显示买卖盘');await activate('显示档位');await activate('20 档');
  assert.ok((await labels()).some(e=>e.label?.startsWith('卖盘 20 档')),'twenty levels can be shown in landscape');
  async function changeBookStep(step, menuOpen=false, rangeBefore) {
    const depthBefore=requestEvents.filter(url=>url.includes('/api/v3/depth?')).length;
    const socketBefore=streamConnections.length;
    const candlesBefore=requestEvents.filter(url=>url.includes('/klines')).length;
    rangeBefore ??= await visibleRange();
    assert.ok(rangeBefore,'chart range is available before opening the step menu');
    await page.evaluate(`(() => {
      if(!window.__stepResetHarness) {
        window.__stepResetHarness=true;
        const originalFetch=window.fetch;
        window.fetch=(...args)=>{
          if(window.__holdStepSnapshot && String(args[0]).includes('/api/v3/depth?')) {
            window.__stepSnapshotWaiting=true;
            return new Promise((resolve,reject)=>{
              window.__releaseStepSnapshot=()=>originalFetch(...args).then(resolve,reject);
              args[1]?.signal?.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')),{once:true});
            });
          }
          return originalFetch(...args);
        };
      }
      window.__stepSnapshotWaiting=false;window.__holdStepSnapshot=true;
    })()`);
    if(!menuOpen) await activate('价格档位');
    await activate(String(step));
    await waitFor(()=>page.evaluate('window.__stepSnapshotWaiting === true'),'price-step reset requests a fresh snapshot');
    const empty=await labels();
    assert.ok(empty.some(e=>e.label?.includes('等待币安订单簿快照')),'reset clears the old book while waiting');
    assert.ok(!empty.some(e=>/^买盘 \d+ 档|^卖盘 \d+ 档/.test(e.label||'')),'neither old book side survives the reset');
    if(step===0.1) await page.screenshot('28-orderbook-step-reset.png');
    await page.evaluate('window.__holdStepSnapshot=false;window.__releaseStepSnapshot()');
    await waitFor(async()=>(await labels()).some(e=>/实时 · (5|20)档/.test(e.label||'')),'new price-step book completes snapshot and incremental synchronization');
    assert.ok(requestEvents.filter(url=>url.includes('/api/v3/depth?')).length>depthBefore);
    assert.equal(streamConnections.length,socketBefore,'price-step reset keeps the existing socket');
    assert.equal(requestEvents.filter(url=>url.includes('/klines')).length,candlesBefore,'price-step reset does not reload candles');
    assert.equal(await visibleRange(),rangeBefore,'price-step reset preserves chart viewport');
  }
  const bookRules=await page.evaluate(`timeNestDashboard.request('cryptoBookRules','{}').then(JSON.parse)`);
  assert.equal(bookRules.stale,false);
  assert.equal(bookRules.data.rules.find(r=>r.symbol==='BTCUSDT').tickSize,'0.01000000');
  await activate('显示档位');await activate('5 档');
  const initialStepRange=await visibleRange();
  await activate('价格档位');
  await waitFor(async()=>{const menu=await labels();return ['0.01','0.1','1','10','100'].every(step=>menu.some(e=>e.label===step));},'all five BTC price steps appear in the menu');
  await page.screenshot('23-orderbook-price-steps.png');
  await changeBookStep(10,true,initialStepRange);
  await activate('显示档位');await activate('20 档');
  await waitFor(async()=>{const rows=await labels();return rows.some(e=>e.label?.startsWith('买盘 20 档')) && rows.some(e=>e.label?.startsWith('卖盘 20 档'));},'10 USDT aggregation fills twenty rows on both sides');
  assert.ok((await labels()).some(e=>{const m=e.label?.match(/买(\d+)\/卖(\d+)价位/);return m && Number(m[1])>1000 && Number(m[2])>1000;}),'the UI receives deep data instead of only the raw top twenty');
  await page.screenshot('24-orderbook-deep-10.png');
  await changeBookStep(100);
  await waitFor(async()=>{
    const rows=await labels();
    const bid=rows.find(e=>e.label?.match(/^买盘 \d+ 档/)),ask=rows.find(e=>e.label?.match(/^卖盘 \d+ 档/));
    if(!bid || !ask)return false;
    const b=Number(bid.label.match(/\d+/)[0]),a=Number(ask.label.match(/\d+/)[0]);
    return b>=2 && a>=2 && (b===20 && a===20 || rows.some(e=>e.label?.includes('已达每侧5000价位上限')));
  },'100 USDT aggregation uses available full buckets and explains any snapshot limit');
  await page.screenshot('25-orderbook-deep-100.png');
  for(const step of [0.1,1,0.01,10]) await changeBookStep(step);
  passed('every BTC price step clears both sides, requests fresh depth and rejects the old display while preserving the chart and live socket');
  await activate('显示档位');await activate('5 档');
  passed('5000-level live depth fills twenty rows at 10 USDT and keeps complete buckets with an explicit limit at 100 USDT');
  const savedBook=JSON.parse(await page.evaluate('timeNestDashboard.readPreferences()'));
  assert.equal(savedBook.cryptoBookSteps.BTCUSDT,10);assert.equal(savedBook.cryptoBookLevels,5);
  passed('order-book side filters and level menu work in the live landscape browser');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1280,height:1280,deviceScaleFactor:1,mobile:false});await delay(500);
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:400,deltaX:0,deltaY:-10000});await delay(500);
  assert.ok((await labels()).some(e=>e.label?.includes('实时 · 5档')),'explicit five-level choice survives desktop orientation');
  passed('order book sits right on desktop and landscape phones and below charts in portrait');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1440,height:900,deviceScaleFactor:1,mobile:false});
  await delay(500);
  const chartGeometry=await page.evaluate(`(() => {
    const nodes=(${deepQuery})('flt-semantics, [aria-label]');
    const rect=prefix=>{const e=nodes.find(e=>(e.getAttribute('aria-label')||e.textContent||'').startsWith(prefix));if(!e)throw new Error('Missing plot '+prefix);const r=e.getBoundingClientRect();return {y:r.y,height:r.height,bottom:r.bottom};};
    return {main:rect('K 线主图，'),volume:rect('VOL 成交量 副图，'),timeline:rect('历史时间轴')};
  })()`);
  assert.equal(chartGeometry.main.height,320,'main price plot retains 320px');
  assert.equal(chartGeometry.volume.height,150,'volume pane retains 150px');
  assert.ok(chartGeometry.timeline.y>chartGeometry.main.bottom && chartGeometry.timeline.bottom<chartGeometry.volume.y,'timeline sits between main chart and first subchart');
  assert.ok(chartGeometry.volume.y-chartGeometry.main.bottom<140,'timeline and connected plots stay compact');
  assert.ok(chartGeometry.main.y>=46 && chartGeometry.main.bottom<=900,'full main plot fits desktop first screen');
  assert.ok(chartGeometry.volume.bottom<=900,'first subchart fits desktop first screen');
  await page.screenshot('13-crypto-detail-desktop.png');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1440,height:1440,deviceScaleFactor:1,mobile:false});await delay(400);
  const integrated=await page.evaluate(`(() => {
    const nodes=(${deepQuery})('flt-semantics, [aria-label]');
    const label=e=>e.getAttribute('aria-label')||e.textContent||'';
    const rect=match=>{const e=nodes.find(match);if(!e)throw new Error('Missing integrated control');const r=e.getBoundingClientRect();return {x:r.x,y:r.y,right:r.right,bottom:r.bottom};};
    const button=text=>e=>['button','checkbox'].includes(e.getAttribute('role')) && label(e).trim().split('\\n').includes(text);
    return {frame:rect(e=>label(e)==='K 线图表区域'),period:rect(button('日线')),gear:rect(button('图表设置')),info:rect(e=>label(e)==='BTC / USDT'),count:rect(e=>/^已加载 \\d+ 根$/.test(label(e))),indicator:rect(button('指标设置')),lastPane:rect(e=>label(e).startsWith('RSI 相对强弱 副图，'))};
  })()`);
  for(const control of [integrated.period,integrated.gear,integrated.info,integrated.indicator]) {
    assert.ok(control.x>=integrated.frame.x && control.right<=integrated.frame.right+.1,'chart controls stay inside its own horizontal border');
    assert.ok(control.y>=integrated.frame.y && control.bottom<=integrated.frame.bottom+.1,JSON.stringify({control,frame:integrated.frame}));
  }
  assert.ok(integrated.period.bottom<=integrated.info.y && integrated.info.bottom<=chartGeometry.main.y,'periods and thin market summary sit above the price plot');
  assert.ok(integrated.count.bottom<=chartGeometry.main.y,'loaded count belongs in the chart summary');
  assert.ok(integrated.indicator.y>integrated.lastPane.bottom,'indicator selection sits below all subcharts');
  const shortcutsRange=await visibleRange(),shortcutsConnections=streamConnections.length;
  await activate('EMA');
  assert.ok(JSON.parse(await page.evaluate('timeNestDashboard.readPreferences()')).cryptoOverlays.includes('ema'));
  await activate('EMA');
  await activate('RSI');
  assert.ok(!JSON.parse(await page.evaluate('timeNestDashboard.readPreferences()')).cryptoPanes.includes('rsi'));
  await activate('RSI');
  assert.ok(JSON.parse(await page.evaluate('timeNestDashboard.readPreferences()')).cryptoPanes.includes('rsi'));
  assert.equal(await visibleRange(),shortcutsRange,'shortcut changes preserve the chart range');
  assert.equal(streamConnections.length,shortcutsConnections,'shortcuts never reconnect the shared feed');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1440,height:1440,deviceScaleFactor:1,mobile:false});await delay(400);
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:400,deltaX:0,deltaY:-10000});await delay(400);
  await page.screenshot('37-chart-integrated-desktop.png');
  passed('chart contains top period/navigation controls and market summary plus bottom indicator shortcuts; selections persist without reconnecting or shifting the historical view');
  await activate('指标设置'); await page.screenshot('14-crypto-indicators-dialog.png'); await activate('完成');
  await page.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
  await delay(500); await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:400,deltaX:0,deltaY:-10000});await delay(400);await page.screenshot('15-crypto-detail-mobile.png');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1280,height:1280,deviceScaleFactor:1,mobile:false});
  await delay(500);
  passed('compact crypto detail keeps a full 320px main plot and 150px first pane within desktop viewport; indicator dialog and mobile layout render');
  await page.screenshot('01-crypto-desktop.png');
  const latestRange=await visibleRange();
  assert.ok(latestRange);
  await dragPrice();
  assert.notEqual(await visibleRange(),latestRange,'mouse drag changes the visible time window');
  for(let i=0;i<5;i++) await dragPrice();
  assert.ok(![...requests].some(url=>url.includes('/klines') && url.includes('endTime=')), 'left edge must not load automatically');
  const loadedCount=async()=>Number((await labels()).find(item=>/^已加载 \d+ 根$/.test(item.label))?.label.match(/\d+/)[0]);
  const beforeOlder=await loadedCount();
  await activate('加载更多历史');
  await waitFor(async()=>await loadedCount()>=beforeOlder+500,'manual timeline button loads another 500 bars');
  assert.ok(await loadedCount()<=beforeOlder+501,'pagination adds exactly 500 historical bars, plus at most one live hourly rollover');
  const historyUrl=new URL([...requests].find(url=>url.includes('/klines') && url.includes('endTime=')));
  assert.equal(Number(historyUrl.searchParams.get('endTime')),btc.data.candles[0].time-1);
  const olderPage=await page.evaluate(`timeNestDashboard.request('cryptoCandles',JSON.stringify({symbol:'BTCUSDT',interval:'1h',endTime:${btc.data.candles[0].time-1}})).then(JSON.parse)`);
  assert.equal(olderPage.data.candles.length,500);
  assert.equal(olderPage.data.candles.at(-1).closeTime+1,btc.data.candles[0].time);
  const pinned=await visibleRange(); await delay(2200);
  assert.equal(await visibleRange(),pinned,'live pushes preserve historical viewport');
  await page.screenshot('09-crypto-history-desktop.png');
  await page.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});
  await page.send('Emulation.setTouchEmulationEnabled',{enabled:true});
  await delay(500);
  const narrowRange=await visibleRange(); await dragPrice(false,true);
  assert.notEqual(await visibleRange(),narrowRange,'touch drag pans the narrow chart');
  await page.screenshot('10-crypto-history-mobile.png');
  await page.send('Emulation.setTouchEmulationEnabled',{enabled:false});
  await page.send('Emulation.setDeviceMetricsOverride',{width:1280,height:1280,deviceScaleFactor:1,mobile:false});
  await delay(600);
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:500,deltaX:0,deltaY:-10000}); await delay(500);
  await activate('回到最新');
  const latestEnd=range=>range.match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/g).at(-1);
  assert.ok(latestEnd(await visibleRange())>=latestEnd(latestRange),'latest view follows a live hourly rollover too');
  const pinchRect=await page.evaluate(`(() => {
    const e=(${deepQuery})('flt-semantics, [aria-label]').find(e=>(e.getAttribute('aria-label')||e.textContent||'').startsWith('K 线主图，'));
    const r=e.getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height*.75};
  })()`);
  assert.ok(!(await labels()).some(e=>e.label==='关闭十字线'),'information and crosshair start hidden');
  await click(pinchRect.x,pinchRect.y);await delay(350);
  assert.ok(!(await labels()).some(e=>e.label==='关闭十字线'),'single mouse click does not enter tracking');
  await doubleClick(pinchRect.x,pinchRect.y);
  assert.ok((await labels()).some(e=>e.label==='关闭十字线'),'double click opens tracking and its close button');
  await doubleClick(pinchRect.x,pinchRect.y);
  assert.ok(!(await labels()).some(e=>e.label==='关闭十字线'),'second double click closes information too');
  const beforeSelection=await visibleRange();
  await selectPrice(.25,.55);
  const selectionSpan=r=>{const dates=r.match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/g);return Date.parse(dates[1].replace(' ','T')+'+08:00')-Date.parse(dates[0].replace(' ','T')+'+08:00');};
  assert.ok(selectionSpan(await visibleRange())<selectionSpan(beforeSelection),'Shift drag zooms the selected bars');
  await page.screenshot('29-chart-box-selection.png');
  await activate('恢复上次视图');assert.equal(await visibleRange(),beforeSelection);
  await activate('框选放大（至少 10 根，Shift + 拖动）');
  await selectPrice(.7,.4,false);
  assert.ok(selectionSpan(await visibleRange())<selectionSpan(beforeSelection),'button selection works right-to-left');
  await activate('恢复上次视图');assert.equal(await visibleRange(),beforeSelection);
  passed('desktop single click stays hidden; double click toggles tracking; Shift and compact tool select ranges and undo restores the viewport');
  await doubleClick(pinchRect.x,pinchRect.y);
  async function verifyInfoPosition(touch) {
    const plot=await page.evaluate(`(() => {
      const e=(${deepQuery})('flt-semantics, [aria-label]').find(e=>(e.getAttribute('aria-label')||e.textContent||'').startsWith('K 线主图，'));
      const r=e.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};
    })()`);
    const point=fraction=>({x:plot.x+4+(plot.width-80)*fraction,y:plot.y+plot.height*.85});
    if(touch) {
      await page.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,...point(.2)}]});
      await delay(450);
    }
    for(const fraction of [.2,.75]) {
      const position=point(fraction);
      await page.send(touch?'Input.dispatchTouchEvent':'Input.dispatchMouseEvent',touch
        ? {type:'touchMove',touchPoints:[{id:1,...position}]}
        : {type:'mouseMoved',...position});
      await delay(200);
      const window=await page.evaluate(`(() => {
        const e=(${deepQuery})('flt-semantics, [aria-label]').find(e=>e.getAttribute('aria-label')==='K 线信息窗口');
        if(!e)throw new Error('Information window missing');const r=e.getBoundingClientRect();return {left:r.left,right:r.right};
      })()`);
      assert.ok(window.left>=plot.x && window.right<=plot.x+plot.width,'information stays inside the plot');
      assert.ok(fraction<.5 ? window.left>position.x : window.right<position.x,'information moves to the opposite side of the selected candle');
      if(touch) await page.screenshot(fraction<.5?'31-mobile-info-right.png':'32-mobile-info-left.png');
    }
    if(touch) await page.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});
  }
  await verifyInfoPosition(false);
  const beforeWheel=await visibleRange();
  const rangeSpan=range=>{const dates=range.match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/g);return Date.parse(dates[1].replace(' ','T')+'+08:00')-Date.parse(dates[0].replace(' ','T')+'+08:00');};
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:pinchRect.x,y:pinchRect.y,deltaX:0,deltaY:-120}); await delay(350);
  assert.ok(rangeSpan(await visibleRange())<rangeSpan(beforeWheel),'wheel zooms active main crosshair');
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:pinchRect.x,y:pinchRect.y,deltaX:0,deltaY:120}); await delay(350);
  passed('mouse wheel zooms the main chart with its crosshair active');
  const beforePinch=await visibleRange();
  await page.send('Emulation.setTouchEmulationEnabled',{enabled:true});
  const touches=distance=>[{id:1,x:pinchRect.x-distance,y:pinchRect.y},{id:2,x:pinchRect.x+distance,y:pinchRect.y}];
  await page.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:touches(60)});
  for(let i=1;i<=8;i++) {
    await page.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:touches(60+i*10)}); await delay(40);
  }
  await page.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]}); await delay(350);
  const afterPinch=await visibleRange();
  const span=range=>{const dates=range.match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}/g);return Date.parse(dates[1].replace(' ','T')+'+08:00')-Date.parse(dates[0].replace(' ','T')+'+08:00');};
  assert.ok(span(afterPinch)<span(beforePinch),'two-finger pinch zooms the time window');
  assert.ok((await labels()).some(e=>e.label?.includes('十字线已锁定')),'crosshair persists after fingers lift');
  await page.screenshot('17-crypto-timeline-crosshair.png');
  await activate('关闭十字线');
  assert.ok(!(await labels()).some(e=>e.label?.includes('十字线已锁定')),'close button dismisses crosshair and information');
  const beforeTouchTracking=await visibleRange();
  await page.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,...pinchRect}]});
  await delay(450);
  assert.ok((await labels()).some(e=>e.label?.includes('十字线已锁定')),'long press opens tracking on a desktop-width touch screen too');
  await page.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{id:1,x:pinchRect.x+70,y:pinchRect.y}]});
  await page.send('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]}); await delay(350);
  assert.equal(await visibleRange(),beforeTouchTracking,'long press and slide move the crosshair without panning');
  await page.screenshot('30-chart-touch-tracking.png');
  await activate('关闭十字线');
  await page.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});await delay(400);
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:400,deltaX:0,deltaY:-10000});await delay(350);
  await verifyInfoPosition(true);
  await activate('关闭十字线');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1280,height:1280,deviceScaleFactor:1,mobile:false});await delay(400);
  passed('desktop hover and portrait-phone touch tracking move the information window to the opposite side and keep the inspected candle uncovered');
  assert.ok(!(await labels()).some(e=>e.label?.includes('十字线已锁定')),'explicit close returns to navigation');
  await page.send('Emulation.setTouchEmulationEnabled',{enabled:false});
  const resizePoint=await page.evaluate(`(() => {
    const e=(${deepQuery})('flt-semantics, [aria-label]').find(e=>(e.getAttribute('aria-label')||e.textContent||'').endsWith('调整 VOL 成交量 副图高度'));
    if(!e)throw new Error('Resize handle missing');const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2};
  })()`);
  await page.send('Input.dispatchMouseEvent',{type:'mousePressed',...resizePoint,button:'left',clickCount:1});
  for(let i=1;i<=8;i++) {
    await page.send('Input.dispatchMouseEvent',{type:'mouseMoved',x:resizePoint.x,y:resizePoint.y+i*10,button:'left',buttons:1}); await delay(30);
  }
  await page.send('Input.dispatchMouseEvent',{type:'mouseReleased',x:resizePoint.x,y:resizePoint.y+80,button:'left',clickCount:1}); await delay(350);
  const resized=await page.evaluate(`(() => {
    const nodes=(${deepQuery})('flt-semantics, [aria-label]');
    const height=prefix=>nodes.find(e=>(e.getAttribute('aria-label')||e.textContent||'').startsWith(prefix)).getBoundingClientRect().height;
    return {main:height('K 线主图，'),volume:height('VOL 成交量 副图，'),macd:height('MACD 副图，')};
  })()`);
  assert.equal(resized.main,320);assert.ok(resized.volume>150);assert.equal(resized.macd,150);
  const storedHeight=await page.evaluate('JSON.parse(timeNestDashboard.readPreferences()).cryptoPaneHeights.vol');
  assert.equal(storedHeight,resized.volume,'drag end stores the pane height');
  await page.screenshot('18-crypto-connected-resizable.png');
  passed('dragging a subchart edge resizes only that pane within the connected chart');
  passed('two-finger zoom preserves tracking; long press and slide inspect bars without panning, and the small close button returns to navigation');
  passed('mouse and touch pan real charts; manual button loads contiguous older candles and live pushes keep the viewport');
  // Applying layout settings must retain the historical view and pane sizes.
  const beforeWindowsRange=await visibleRange(), beforeWindowsConnections=streamConnections.length;
  await activate('图表设置');await page.screenshot('34-chart-settings-desktop.png');
  await activate('订单簿');await activate('取消');
  assert.equal(streamConnections.length,beforeWindowsConnections,'cancel never changes subscriptions');
  assert.ok((await labels()).some(e=>e.label==='订单簿面板'));
  await activate('图表设置');
  for(const name of ['订单簿','最新成交','历史时间轴','指标数值','技术参考']) await activate(name);
  await activate('50 条');await activate('100 条');await activate('应用');
  await waitFor(()=>streamConnections.length>beforeWindowsConnections,'hidden data windows resubscribe without depth or raw trades');
  const hiddenSocket=streamConnections.at(-1);
  assert.ok(!hiddenSocket.url.includes('@depth') && !hiddenSocket.url.includes('@trade'));
  await waitFor(async()=>{const nodes=await labels();return !nodes.some(e=>e.label==='订单簿面板' || e.label==='最新成交面板' || e.label==='历史时间轴');},'disabled windows are removed');
  let view=JSON.parse(await page.evaluate('timeNestDashboard.readPreferences()')).cryptoView;
  assert.deepEqual(view,{orderBook:false,trades:false,timeline:false,indicatorValues:false,assessment:false,tradeRows:100});
  await waitFor(()=>streamFrames.some(f=>f.id===hiddenSocket.requestId && f.data?.e==='kline'),'K line continues with both market windows hidden');
  await activate('图表设置');
  for(const name of ['订单簿','最新成交','历史时间轴','指标数值','技术参考']) await activate(name);
  await activate('应用');
  await waitFor(async()=>(await labels()).some(e=>e.label?.includes('实时 · 5档')),'order book returns after settings apply');
  await waitFor(async()=>(await labels()).some(e=>e.label?.includes('100/100 笔')),'restored tape retains the selected hundred recent fills');
  assert.equal(await visibleRange(),beforeWindowsRange,'settings preserve historical chart viewport');
  const beforeFreeze=streamConnections.length;
  await activate('暂停成交列表');const frozen=(await tapeRows()).map(row=>row.label);
  await delay(1000);assert.deepEqual((await tapeRows()).map(row=>row.label),frozen,'freezing the tape makes it readable while pushes continue');
  await activate('继续成交列表');
  await waitFor(async()=>(await tapeRows())[0]?.label!==frozen[0],'continuing the tape shows newer fills');
  assert.equal(streamConnections.length,beforeFreeze,'tape freeze does not restart the market feed');
  await page.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:false});await delay(400);
  await activate('图表设置');await page.screenshot('35-chart-settings-mobile.png');await activate('取消');
  let tapeBox=(await bookGeometry()).trades;
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:400,deltaX:0,deltaY:tapeBox.y-100});await delay(500);
  await page.screenshot('36-latest-trades-mobile.png');
  await page.send('Emulation.setDeviceMetricsOverride',{width:1280,height:1280,deviceScaleFactor:1,mobile:false});await delay(400);
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:400,deltaX:0,deltaY:-10000});await delay(500);
  passed('chart settings cancel/apply preserve the viewport; window switches stop hidden subscriptions, persist on-device, and tape freeze/resume works on the shared feed');
  // Flutter semantics represents the entire card as one tappable node.
  const ethPoint = await page.evaluate(`(() => {
    const node = (${deepQuery})('flt-semantics, [aria-label]').find(e => (e.getAttribute('aria-label') || e.textContent || '').startsWith('ETH · 以太坊'));
    if (!node) throw new Error('ETH card missing'); const r=node.getBoundingClientRect(); return {x:r.x+r.width/2,y:r.y+r.height/2};
  })()`);
  await click(ethPoint.x, ethPoint.y);
  await waitFor(() => page.evaluate(`JSON.parse(timeNestDashboard.readPreferences()).cryptoSymbol === 'ETHUSDT'`), 'ETH choice saved');
  await waitFor(async () => (await labels()).some(item => item.label === 'ETH / USDT'), 'ETH selection rendered');
  await waitFor(() => [...requests].some(url => url.includes('symbol=ETHUSDT') && url.includes('interval=1h')), 'ETH hourly request');
  await waitFor(async()=>(await labels()).some(e=>e.label?.includes('实时 · 5档')),'ETH book inherits saved level count');
  await changeBookStep(1);
  const perSymbolSteps=JSON.parse(await page.evaluate('timeNestDashboard.readPreferences()')).cryptoBookSteps;
  assert.deepEqual(perSymbolSteps,{BTCUSDT:10,ETHUSDT:1});
  await activate('日线');
  await waitFor(() => page.evaluate(`JSON.parse(timeNestDashboard.readPreferences()).cryptoInterval === '1d'`), 'daily period saved');
  await waitFor(() => [...requests].some(url => url.includes('symbol=ETHUSDT') && url.includes('interval=1d')), 'ETH daily request');
  const eth = await page.evaluate(`timeNestDashboard.request('cryptoCandles',JSON.stringify({symbol:'ETHUSDT',interval:'1d'})).then(JSON.parse)`);
  assert.equal(eth.stale, false); assert.equal(eth.data.candles.length, 500);
  await waitFor(() => streamFrames.some(f=>f.data?.s==='ETHUSDT' && f.data?.k?.i==='1d'), 'ETH daily pushed frame');
  await waitFor(async () => (await labels()).some(item=>item.label?.includes('● 币安实时推送')), 'ETH stream live');
  await waitFor(() => streamConnections.slice(0,2).every(s=>streamClosed.includes(s.requestId)), 'superseded sockets fully close');
  await delay(500); await page.screenshot('02-crypto-eth.png');
  passed('ETH card and daily interval select the matching real series and persist');
  await page.send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: false });
  await delay(500); await page.screenshot('03-crypto-mobile.png');
  // Scroll the live Flutter viewport to inspect chart controls on a narrow screen.
  await page.send('Input.dispatchMouseEvent', { type:'mouseWheel', x:2, y:650, deltaX:0, deltaY:900 });
  await delay(600); await page.screenshot('04-crypto-mobile-chart.png');
  // A fresh page restores a demanding 8+8 saved configuration.
  await page.evaluate(`(() => { const p=JSON.parse(timeNestDashboard.readPreferences());p.cryptoOverlays=['ma','ema','wma','boll','donchian','keltner','vwma','hma'];p.cryptoPanes=['vol','amount','macd','rsi','kdj','stoch','cci','adx'];p.cryptoInfoRight=true;p.cryptoBookSteps.ETHUSDT=0.01;timeNestDashboard.writePreferences(JSON.stringify(p)); })()`);
  await page.send('Emulation.setDeviceMetricsOverride', {width:1280,height:1280,deviceScaleFactor:1,mobile:false});
  await page.evaluate(`(() => {
    const key='shike.crypto.rules.v2', entry=JSON.parse(localStorage.getItem(key));
    entry.at=Date.now()-9*3600000;
    const rule=entry.data.rules.find(r=>r.symbol==='ETHUSDT');rule.stepSize='0.00100000';rule.quoteAssetPrecision=6;
    localStorage.setItem(key,JSON.stringify(entry));
  })()`);
  await page.send('Page.addScriptToEvaluateOnNewDocument',{source:`{
    const originalFetch=window.fetch;
    window.fetch=(...args)=>{
      if(String(args[0]).includes('/api/v3/exchangeInfo') && !window.__rulesReleased) {
        window.__rulesHeld=true;
        return new Promise((resolve,reject)=>{
          window.__releaseRules=()=>{window.__rulesReleased=true;originalFetch(...args).then(resolve,reject);};
          args[1]?.signal?.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')),{once:true});
        });
      }
      return originalFetch(...args);
    };
  }`});
  await page.send('Page.reload'); await ready(); await enableSemantics();
  await activate('每日看板');
  // Reopening a route is covered in widget tests at 320 px and 2x text.
  const restored = await page.evaluate(`JSON.parse(timeNestDashboard.readPreferences())`);
  assert.equal(restored.cryptoSymbol, 'ETHUSDT'); assert.equal(restored.cryptoInterval, '1d');
  assert.equal(restored.cryptoBookLevels,5);assert.deepEqual(restored.cryptoBookSteps,{BTCUSDT:10,ETHUSDT:0.01});
  assert.equal(restored.cryptoPaneHeights.vol,storedHeight);
  assert.deepEqual(restored.cryptoView,{orderBook:true,trades:true,timeline:true,indicatorValues:true,assessment:true,tradeRows:100});
  assert.ok(!restored.order?.includes('fx'));
  await activate('数字货币行情');
  await waitFor(()=>page.evaluate('window.__rulesHeld === true'),'expired exchange rules refresh in background');
  await waitFor(async()=>(await labels()).some(e=>e.label?.includes('实时 · 5档')),'cached rules and the restored depth are ready',6500);
  await waitFor(async()=>(await labels()).some(e=>/^数量\(ETH\) [\d,]+\.\d{3}$/.test(e.label||'')),'cached exchange rules render quantity with three decimals',7000);
  await page.screenshot('26-orderbook-cached-rules.png');
  await page.evaluate('window.__releaseRules()');
  await waitFor(async()=>(await labels()).some(e=>/^数量\(ETH\) [\d,]+\.\d{4}$/.test(e.label||'')),'fresh exchange rules automatically reformat to four decimals');
  assert.equal(await page.evaluate("JSON.parse(localStorage.getItem('shike.crypto.rules.v2')).data.rules.find(r=>r.symbol==='ETHUSDT').quoteAssetPrecision"),8);
  await page.screenshot('27-orderbook-fresh-rules.png');
  await changeBookStep(1);
  passed('expired persistent rules render immediately; a held background refresh updates quantity and amount precision without a page reload');
  await waitFor(async()=> (await labels()).some(item=>item.label?.includes('主图 8/8 · 副图 8/8')), '8+8 chart settings restored');
  await waitFor(async()=> (await labels()).some(item=>item.label?.includes('● 币安实时推送')), 'restored stream live');
  await waitFor(async()=>(await labels()).some(e=>e.label?.includes('实时 · 5档')),'five-level book restores on fresh page');
  passed('per-symbol price steps and displayed level count persist across currency, series, orientation and full page reload');
  const restoredHeight=await page.evaluate(`(() => {
    const e=(${deepQuery})('flt-semantics, [aria-label]').find(e=>(e.getAttribute('aria-label')||e.textContent||'').startsWith('VOL 成交量 副图，'));
    return e.getBoundingClientRect().height;
  })()`);
  assert.equal(restoredHeight,storedHeight,'fresh page restores custom height after symbol, interval and indicator changes');
  assert.equal(JSON.parse(await page.evaluate('timeNestDashboard.readPreferences()')).cryptoCurrency,'CNY');
  await waitFor(async()=>(await labels()).some(item=>item.label?.includes('≈ ¥') && item.label?.includes('CNY')),'CNY conversion restores on fresh page');
  passed('device-local subchart heights persist across series changes and full page reload');
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:800,deltaX:0,deltaY:620});await delay(500);await page.screenshot('05-crypto-eight-overlays.png');
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:800,deltaX:0,deltaY:1800});await delay(500);await page.screenshot('06-crypto-eight-panes.png');
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:800,deltaX:0,deltaY:1800});await delay(500);await page.screenshot('07-crypto-assessment.png');
  assert.ok((await labels()).some(item=>item.label?.includes('评分规则：六项')));
  passed('narrow screenshots captured; 8 overlays, 8 panes, automatic info position and closed-bar assessment restore');
  const connectionCount=streamConnections.length, requestCount=requestEvents.length;
  await page.evaluate(`window.__cryptoSockets.at(-1).close(1000,'smoke reconnect')`);
  await waitFor(()=>streamConnections.length>connectionCount,'actual closed connection reconnects');
  const restoredSocket=streamConnections.at(-1).requestId;
  await waitFor(()=>streamFrames.some(f=>f.id===restoredSocket && f.data?.s==='ETHUSDT' && f.data?.k?.i==='1d'),'reconnected ETH daily frames');
  await waitFor(()=>requestEvents.slice(requestCount).some(url=>url.includes('/api/v3/klines')),'reconnection refetches history');
  await waitFor(async()=>(await labels()).some(item=>item.label?.includes('评分规则：六项')),'assessment resumes after resync');
  await page.screenshot('08-crypto-reconnected.png');
  passed('closing a real Binance connection resubscribes, refetches history and restores assessment');
  await page.send('Input.dispatchMouseEvent',{type:'mouseWheel',x:2,y:800,deltaX:0,deltaY:-10000});await delay(500);
  await activate('实时推送已开启');
  await waitFor(async()=>(await labels()).some(item=>item.label?.includes('推送已暂停，当前为暂停前的快照')),'manual pause visible');
  assert.ok(await page.evaluate('window.__cryptoSockets.every(s=>s.readyState!==WebSocket.OPEN)'));
  await delay(2000);
  const pausedLabels=(await labels()).filter(item=>item.label?.startsWith('报价截至'));
  await delay(2200);
  assert.deepEqual((await labels()).filter(item=>item.label?.startsWith('报价截至')),pausedLabels);
  passed('manual pause closes active sockets and stops visible quote updates');
  assert.deepEqual(errors, []);
  await writeFile(path.join(output, 'report.json'), JSON.stringify({status:'passed',
    generatedAt:new Date().toISOString(), releaseFingerprint:renderServiceWorker(files, template).manifest.version,
    checks, quotes: quotes.data, btcCandles: btc.data.candles.length, ethCandles: eth.data.candles.length,
    errors, streamConnections, streamClosed, pushedFrameCount:streamFrames.length, streamSamples:streamFrames.filter(f=>f.data?.e==='kline').slice(-3), requests:[...requests]}, null, 2));
  console.log(`Verified ${checks.length} scenarios. Screenshots/report: ${output}`);
} catch (error) {
  if (page) {
    try { await page.screenshot('failure.png'); } catch { /* browser may have exited */ }
    try { await writeFile(path.join(output,'failure-dom.json'),JSON.stringify(await labels(),null,2)); } catch { /* unavailable */ }
  }
  let preferences;
  try { preferences = await page?.evaluate('timeNestDashboard.readPreferences()'); } catch { /* unavailable */ }
  await writeFile(path.join(output,'failure.json'),JSON.stringify({error:error.stack,checks,errors,streamConnections,streamClosed,streamFrames:streamFrames.slice(-6),requests:[...requests],preferences,browserLog},null,2));
  console.error(error.stack); process.exitCode=1;
} finally {
  for (const ws of sockets) ws.close(); chrome.kill('SIGTERM');
  server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
