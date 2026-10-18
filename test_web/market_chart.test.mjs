import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
const js = await readFile(new URL('../web/market_chart.js', import.meta.url), 'utf8');
const html = await readFile(new URL('../web/market_chart.html', import.meta.url), 'utf8');
function run(search = '', options = {}) {
  const source = { firstElementChild: {} }, fallback = {}, status = {}, children = [];
  const stages = [];
  Object.defineProperty(status, 'textContent', {get: () => stages.at(-1), set: value => stages.push(value)});
  const chart = { appendChild: child => { if (options.appendFails) throw new Error('append failed'); children.push(child); } };
  let timeout, pagehide, cleared = false;
  const context = {
    URL, URLSearchParams: options.noQueryParser ? undefined : URLSearchParams, location: {search}, origin: options.origin ?? 'null',
    document: {
      getElementById: id => ({source, fallback, status, widget:chart})[id],
      createElement: tag => { assert.equal(tag, 'iframe'); if (options.createFails) throw new Error('element failed'); return {setAttribute(name, value){this[name] = value;}}; },
    },
    setTimeout: callback => { timeout = callback; return 1; },
    clearTimeout: () => { cleared = true; },
    window: { top: options.top ?? {}, self: options.self ?? {}, addEventListener: (event, callback) => { assert.equal(event, 'pagehide'); pagehide = callback; } },
  };
  vm.createContext(context);
  if (options.noHasOwn) vm.runInContext('Object.hasOwn = undefined;', context);
  vm.runInContext(js, context);
  return {source, fallback, status, stages, script:children[0], config:children[0] ? JSON.parse(decodeURIComponent(new URL(children[0].src).hash.slice(1))) : null, timeout, pagehide, get cleared(){return cleared;}};
}
for (const [id, symbol] of Object.entries({shanghai:'SSE:000001', shenzhen:'SZSE:399001', csi300:'SSE:000300', chinext:'SZSE:399006', star50:'SSE:000688', allshare:'SSE:000985'})) {
  test(`official fixed symbol ${id}`, () => {
    const r = run(`?index=${id}&interval=W`);
    assert.equal(r.config.symbol, symbol);
    assert.equal(r.config.interval, 'W');
    assert.equal(r.config.allow_symbol_change, false);
    assert.equal(r.config.hide_top_toolbar, true);
    assert.equal(new URL(r.script.src).origin, 'https://www.tradingview-widget.com');
    assert.equal(new URL(r.script.src).pathname, '/embed-widget/advanced-chart/');
    assert.equal(r.script.sandbox, 'allow-scripts allow-same-origin allow-popups allow-popups-to-escape-sandbox');
    assert.equal(r.source.href, `https://www.tradingview.com/symbols/${symbol.replace(':','-')}/`);
    assert.match(r.source.firstElementChild.textContent, /图表$/);
    assert.equal(r.fallback.href, r.source.href);
    assert.match(r.fallback.textContent, /官方来源$/);
  });
}
test('invalid symbols, prototype names, scripts and intraday values fall back', () => {
  for (const id of ['__proto__','constructor','https://evil.test','<script>alert(1)</script>','']) {
    const r = run(`?index=${encodeURIComponent(id)}&interval=1`);
    assert.equal(r.config.symbol, 'SSE:000001');
    assert.equal(r.config.interval, 'D');
    assert.equal(r.source.href, 'https://www.tradingview.com/symbols/SSE-000001/');
  }
});
test('no success claimed from iframe or script events; error stays actionable', () => {
  const r = run();
  assert.equal(r.script.onload, undefined);
  assert.equal(r.script.onmessage, undefined);
  r.timeout();
  assert.match(r.status.textContent, /未显示图表/);
  const failed = run();
  failed.script.onerror();
  assert.match(failed.status.textContent, /连接失败/);
  assert.equal(failed.cleared, true);
  r.pagehide();
});
test('static wrapper preserves provider attribution and restrictive CSP', () => {
  assert.match(html, /by TradingView/);
  assert.match(html, /rel="noopener nofollow"/);
  assert.match(html, /default-src 'none'/);
  const inline = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  assert.equal(inline, js);
  assert.ok(html.includes(`script-src 'sha256-${createHash('sha256').update(inline).digest('base64')}'`));
  assert.match(html, /base-uri 'none'; form-action 'none'/);
  assert.doesNotMatch(js, /fetch\(|XMLHttpRequest|localStorage|sessionStorage|postMessage|innerHTML|contentWindow/);
});

test('direct wrapper only creates a provider cross-origin iframe, never a remote script', () => {
  const same = {};
  for (const options of [{origin:'https://kingxcode.github.io'}, {origin:'https://kingxcode.github.io',top:same,self:same}, {top:same,self:same}]) {
    const r = run('', options);
    assert.equal(new URL(r.script.src).origin, 'https://www.tradingview-widget.com');
  }
  assert.doesNotMatch(html, /script-src[^;]+https:/);
  assert.match(html, /frame-src https:\/\/www.tradingview-widget.com;/);
});

for (const [id, symbol] of Object.entries({shanghai:'SSE:000001', shenzhen:'SZSE:399001', csi300:'SSE:000300', chinext:'SZSE:399006', allshare:'SSE:000985'})) {
  test(`technical context remains a fixed daily provider widget for ${id}`, () => {
    const r = run(`?kind=technical&index=${id}&interval=M`);
    assert.equal(r.config.symbol, symbol);
    assert.equal(r.config.interval, '1D');
    assert.equal(r.config.showIntervalTabs, false);
    assert.equal(r.config.colorTheme, 'dark');
    assert.equal(new URL(r.script.src).pathname, '/embed-widget/technical-analysis/');
    assert.match(r.source.firstElementChild.textContent, /技术面$/);
    assert.equal(r.script.onload, undefined);
  });
}
test('known unavailable technical rating does not silently substitute another index', () => {
  const r = run('?kind=technical&index=star50');
  assert.equal(r.script, undefined);
  assert.equal(r.config, null);
  assert.match(r.status.textContent, /科创50 技术评级暂缺/);
  assert.match(r.source.href, /SSE-000688/);
});
test('untrusted kind can never select another endpoint or arbitrary URL', () => {
  for (const kind of ['__proto__','https://evil.test','../technical-analysis','technical/']) {
    const r = run(`?kind=${encodeURIComponent(kind)}`);
    assert.equal(new URL(r.script.src).pathname, '/embed-widget/advanced-chart/');
  }
});


test('legacy browsers without Object.hasOwn still initialize whitelisted widgets', () => {
  const r = run('?index=shenzhen&kind=technical', {noHasOwn:true});
  assert.equal(r.config.symbol, 'SZSE:399001');
  assert.equal(r.config.interval, '1D');
  assert.equal(r.stages[0], '正在启动内嵌图表…');
  assert.match(r.status.textContent, /^已请求 TradingView 内容/);
  assert.equal(r.script.onload, undefined, 'requesting a frame never proves data rendered');
});
test('early parsing and iframe startup failures remain actionable and cancel their timer', () => {
  for (const options of [{noQueryParser:true}, {createFails:true}, {appendFails:true}]) {
    const r = run('', options);
    assert.equal(r.script, undefined);
    assert.equal(r.config, null);
    assert.equal(r.stages[0], '正在启动内嵌图表…');
    assert.match(r.status.textContent, /未能启动.*官方来源/);
    assert.equal(typeof r.timeout, 'function', 'timer must exist before risky startup work');
    assert.equal(r.cleared, true);
    r.pagehide();
  }
});
test('static fallback remains useful even if no script runs, with no misleading default index', () => {
  const staticHtml = html.split('<script>')[0];
  assert.match(staticHtml, /id="help"[^>]*>图表空白或无法加载/);
  assert.match(staticHtml, /id="fallback" href="https:\/\/www.tradingview.com\/"/);
  assert.match(staticHtml, /内嵌图表尚未启动/);
  assert.match(staticHtml, /<noscript>/);
  assert.doesNotMatch(staticHtml, /上证指数|SSE-000001/);
  assert.ok(staticHtml.indexOf('id="help"') < staticHtml.indexOf('id="chart"'));
});
test('pagehide clears pending hints and unavailable ratings never retain a timer', () => {
  const r = run();
  r.pagehide();
  assert.equal(r.cleared, true);
  assert.equal(run('?kind=technical&index=star50').cleared, true);
});
