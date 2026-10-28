import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFile } from 'node:fs/promises';

const source = await readFile(new URL('../web/dashboard.js', import.meta.url), 'utf8');
const START = Date.parse('2026-10-18T00:00:00Z');
const minute = 60_000, hour = 60 * minute, day = 24 * hour;
const CACHE_KEY = 'shike.dashboard.cache.v1';
function response(data, status = 200, headers = {}) {
  return new Response(typeof data === 'string' ? data : JSON.stringify(data), {
    status, headers: { 'content-type': 'application/json', ...headers },
  });
}
function storage(seed = {}) {
  const values = new Map(Object.entries(seed));
  return {
    values,
    getItem: key => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: key => values.delete(key),
  };
}
function harness(fetcher, options = {}) {
  let now = options.now ?? START;
  const calls = [], opened = [];
  const localStorage = options.storage ?? storage();
  class TestDate extends Date {
    constructor(...args) { super(...(args.length ? args : [now])); }
    static now() { return now; }
  }
  const context = {
    URL, URLSearchParams, AbortController, TextDecoder, Date: TestDate, localStorage,
    DOMParser: options.DOMParser,
    setTimeout: options.setTimeout ?? setTimeout,
    clearTimeout: options.clearTimeout ?? clearTimeout,
    open: (...args) => opened.push(args),
    fetch: async (url, init) => { calls.push({ url, init }); return fetcher(url, init); },
  };
  // Explicit test-only compiled-policy override; production source stays deny-all.
  const script = options.newsContentGrants
    ? source.replace('const newsContentGrants = Object.freeze({});', `const newsContentGrants = Object.freeze(${JSON.stringify(options.newsContentGrants)});`)
    : source;
  vm.runInNewContext(script, context);
  return {
    api: context.timeNestDashboard, calls, opened, storage: localStorage,
    advance: ms => { now += ms; },
    request: async (module, args, refresh = false) => JSON.parse(await context.timeNestDashboard.request(module, JSON.stringify(args), refresh)),
  };
}
const weather = () => ({
  timezone: 'Asia/Shanghai', utc_offset_seconds: 28800,
  hourly: {
    time: ['2026-10-18T08:00', '2026-10-18T09:00'],
    temperature_2m: [20, 21], apparent_temperature: [22.1, 23], precipitation_probability: [0, 40],
    wind_speed_10m: [10, 12], weather_code: [0, 3],
  },
});

test('weather requests 24 city-local hours and normalizes probability, km/h and timezone', async () => {
  const h = harness(() => response(weather()));
  const result = await h.request('weather', { latitude: 31.222222, longitude: 121.45806 });
  assert.deepEqual(result.data, { hours: [
    { time: '2026-10-18T08:00', temperature: 20, feels: 22.1, rain: 0, wind: 10, code: 0 },
    { time: '2026-10-18T09:00', temperature: 21, feels: 23, rain: 40, wind: 12, code: 3 },
  ], timezone: 'Asia/Shanghai', utcOffsetSeconds: 28800 });
  const url = new URL(h.calls[0].url);
  assert.equal(url.searchParams.get('forecast_hours'), '24');
  assert.match(url.searchParams.get('hourly'), /temperature_2m/);
  assert.equal(url.searchParams.get('timezone'), 'auto');
  assert.equal(url.searchParams.get('wind_speed_unit'), 'kmh');
  assert.equal(url.searchParams.get('latitude'), '31.2222');
  assert.equal(h.calls[0].init.credentials, 'omit');
  assert.equal(h.calls[0].init.referrerPolicy, 'no-referrer');
});

test('missing weather data stays null; malformed/misaligned arrays cannot look like zero', async () => {
  const nullable = weather(); nullable.hourly.precipitation_probability[1] = null;
  const h = harness(() => response(nullable));
  assert.equal((await h.request('weather', { latitude: 1, longitude: 2 })).data.hours[1].rain, null);
  const malformed = weather(); malformed.hourly.apparent_temperature.pop();
  const bad = harness(() => response(malformed));
  await assert.rejects(bad.request('weather', { latitude: 1, longitude: 2 }), /格式异常/);
});

test('city search encodes Chinese queries and supports empty results', async () => {
  const h = harness(() => response({ results: [{ name: '上海', latitude: 31, longitude: 121, country: '中国', timezone: 'Asia/Shanghai' }] }));
  assert.deepEqual((await h.request('searchCities', { query: '上海' })).data.cities[0], {
    name: '上海', latitude: 31, longitude: 121, country: '中国', admin1: '', timezone: 'Asia/Shanghai',
  });
  assert.equal(new URL(h.calls[0].url).searchParams.get('name'), '上海');
  const empty = harness(() => response({ generationtime_ms: 0.1 }));
  assert.deepEqual((await empty.request('searchCities', { name: 'NoSuchCity' })).data, { cities: [] });
});

test('fresh cache survives reload; expired failures are stale with original fetch time', async () => {
  const shared = storage();
  const first = harness(() => response(weather()), { storage: shared });
  const original = await first.request('weather', { latitude: 1, longitude: 2 });
  const reloaded = harness(() => { throw new Error('offline'); }, { storage: shared, now: START + minute });
  assert.equal((await reloaded.request('weather', { latitude: 1, longitude: 2 })).cached, true);
  assert.equal(reloaded.calls.length, 0);
  reloaded.advance(15 * minute);
  const stale = await reloaded.request('weather', { latitude: 1, longitude: 2 });
  assert.equal(stale.stale, true);
  assert.equal(stale.cached, true);
  assert.equal(stale.fetchedAt, original.fetchedAt);
  assert.match(stale.warning, /上次保存/);
  const again = await reloaded.request('weather', { latitude: 1, longitude: 2 }, true);
  assert.equal(again.stale, true);
  assert.equal(reloaded.calls.length, 1);
});

test('expired stale data beyond retention is not shown as current information', async () => {
  const shared = storage();
  const h = harness(() => response(weather()), { storage: shared });
  await h.request('weather', { latitude: 1, longitude: 2 });
  const later = harness(() => { throw new Error('offline'); }, { storage: shared, now: START + 3 * day });
  await assert.rejects(later.request('weather', { latitude: 1, longitude: 2 }), /加载失败/);
});

test('parallel identical requests deduplicate; repeated refresh cannot bypass throttle', async () => {
  let finish;
  const h = harness(() => new Promise(resolve => { finish = resolve; }));
  const a = h.request('weather', { latitude: 31.222222, longitude: 121.45806 });
  const b = h.request('weather', { latitude: 31.2222, longitude: 121.4581 }, true);
  assert.equal(h.calls.length, 1);
  finish(response(weather()));
  const [one, two] = await Promise.all([a, b]);
  assert.deepEqual(one, two);
  const three = await h.request('weather', { latitude: 31.2222, longitude: 121.4581 }, true);
  assert.equal(three.cached, true);
  assert.match(three.warning, /频繁/);
  assert.equal(h.calls.length, 1);
});

test('Retry-After seconds and dates protect cross-city refreshes and survive reload', async () => {
  for (const retryAfter of ['120', new Date(START + 2 * minute).toUTCString()]) {
    const shared = storage();
    const h = harness(() => response({}, 429, { 'retry-after': retryAfter }), { storage: shared });
    await assert.rejects(h.request('weather', { latitude: 1, longitude: 2 }), /数据服务请求受限/);
    await assert.rejects(h.request('weather', { latitude: 3, longitude: 4 }, true), /数据服务请求受限/);
    assert.equal(h.calls.length, 1);
    const reload = harness(() => response(weather()), { storage: shared });
    await assert.rejects(reload.request('weather', { latitude: 5, longitude: 6 }, true), /数据服务请求受限/);
    assert.equal(reload.calls.length, 0);
    reload.advance(3 * minute);
    assert.equal((await reload.request('weather', { latitude: 5, longitude: 6 }, true)).cached, false);
    assert.equal(reload.calls.length, 1);
  }
});

test('rate-limited refresh retains stale weather with its original fetch time', async () => {
  let limited = false;
  const h = harness(() => limited ? response({}, 429, { 'retry-after': '60' }) : response(weather()));
  const original = await h.request('weather', { latitude: 1, longitude: 2 });
  limited = true; h.advance(15 * minute + 1);
  const result = await h.request('weather', { latitude: 1, longitude: 2 }, true);
  assert.equal(result.stale, true);
  assert.equal(result.fetchedAt, original.fetchedAt);
  assert.deepEqual(result.data, original.data);
  assert.match(result.warning, /数据服务请求受限/);
});

test('removed releases API and cache stay inactive without disturbing active data or settings', async () => {
  const shared = storage();
  const initial = harness(() => response(weather()), { storage: shared });
  const original = await initial.request('weather', { latitude: 1, longitude: 2 });
  const cache = JSON.parse(shared.getItem(CACHE_KEY));
  cache['releases:{"repo":"owner/repo"}'] = {
    at: START,
    data: { repo: 'owner/repo', releases: [], noReleases: true },
  };
  shared.setItem(CACHE_KEY, JSON.stringify(cache));
  const limitKey = 'shike.dashboard.limits.v1';
  const budgetKey = 'shike.dashboard.github-budget.v1';
  shared.setItem(limitKey, JSON.stringify({
    'api.github.com': START + hour,
    'api.coinbase.com': START + minute,
  }));
  shared.setItem(budgetKey, JSON.stringify(Array.from({ length: 40 }, (_, i) => START - i)));
  const preserved = {
    'shike.dashboard.preferences.v1': JSON.stringify({ version: 4, repos: ['owner/repo'], feed: 'show', cryptoSymbol: 'ETHUSDT' }),
    'shike.crypto.rules.v2': JSON.stringify({ retained: 'independent rules cache' }),
    'shike.settings.v1': JSON.stringify({ brightness: .7 }),
    'shike.timer.v1': JSON.stringify({ remaining: 120 }),
  };
  for (const [key, value] of Object.entries(preserved)) shared.setItem(key, value);
  const budgetAccess = [];
  const getItem = shared.getItem, setItem = shared.setItem;
  shared.getItem = key => { if (key === budgetKey) budgetAccess.push('read'); return getItem(key); };
  shared.setItem = (key, value) => { if (key === budgetKey) budgetAccess.push('write'); return setItem(key, value); };
  const h = harness(() => response({}), { storage: shared });
  for (const refresh of [false, true]) {
    await assert.rejects(h.request('releases', { repo: 'owner/repo' }, refresh), /不支持/);
  }
  assert.equal(h.calls.length, 0, 'retired requests must not reach any provider');
  assert.deepEqual(JSON.parse(shared.getItem(limitKey)), { 'api.coinbase.com': START + minute });
  const retained = await h.request('weather', { latitude: 1, longitude: 2 });
  assert.equal(retained.cached, true);
  assert.equal(retained.fetchedAt, original.fetchedAt);
  assert.deepEqual(retained.data, original.data);
  assert.equal(h.calls.length, 0);
  await h.request('searchCities', { query: 'NoSuchCity' });
  const saved = JSON.parse(shared.getItem(CACHE_KEY));
  assert.equal(Object.keys(saved).some(key => key.startsWith('releases:')), false);
  assert.deepEqual(saved['weather:{"latitude":1,"longitude":2}'], cache['weather:{"latitude":1,"longitude":2}']);
  for (const [key, value] of Object.entries(preserved)) assert.equal(shared.getItem(key), value);
  assert.deepEqual(budgetAccess, [], 'retired GitHub budget must no longer be read or written');
  assert.ok(h.calls.every(call => new URL(call.url).hostname !== 'api.github.com'));
});

test('HN news bounds concurrency, maps 12 stories, and safely falls back to discussion URLs', async () => {
  let active = 0, maxActive = 0;
  const h = harness(async url => {
    if (url.endsWith('topstories.json')) return response(Array.from({ length: 20 }, (_, i) => i + 1));
    const id = Number(url.match(/item\/(\d+)/)[1]);
    active++; maxActive = Math.max(active, maxActive);
    await new Promise(resolve => setTimeout(resolve, 2)); active--;
    return response({ id, type: 'story', title: `Story ${id}`, score: 50, descendants: 9, time: 1792281600, by: 'author', url: id === 1 ? 'javascript:alert(1)' : `https://example.com/${id}` });
  });
  const result = await h.request('news', { feed: 'top' });
  assert.equal(result.data.stories.length, 12);
  assert.ok(maxActive <= 4);
  assert.equal(h.calls.length, 13);
  assert.deepEqual(result.data.stories[0], { id: 1, title: 'Story 1', score: 50, comments: 9, time: 1792281600, by: 'author', url: 'https://news.ycombinator.com/item?id=1', discussion: 'https://news.ycombinator.com/item?id=1' });
});

test('HN deleted and missing items are omitted, partial network failures carry warning', async () => {
  const h = harness(url => {
    if (url.endsWith('newstories.json')) return response([1, 2, 3, 4]);
    const id = Number(url.match(/item\/(\d+)/)[1]);
    if (id === 1) return response(null);
    if (id === 2) return response({ id, deleted: true });
    if (id === 3) return response({}, 500);
    return response({ id, type: 'job', title: 'Job', time: 1792281600, by: 'author' });
  });
  const result = await h.request('news', { feed: 'new' });
  assert.equal(result.data.stories.length, 1);
  assert.equal(result.data.stories[0].comments, 0);
  assert.match(result.warning, /1 条资讯/);
});

test('HN item cache is shared across feeds and unknown feed is rejected', async () => {
  const h = harness(url => url.includes('stories.json') ? response([1]) : response({ id: 1, type: 'story', title: 'Story', time: 1792281600 }));
  await h.request('news', { feed: 'top' });
  await h.request('news', { feed: 'show' });
  assert.equal(h.calls.length, 3);
  await assert.rejects(h.request('news', { feed: 'random' }), /资讯分类/);
});

test('input validation rejects arbitrary requests before reaching the network', async () => {
  const h = harness(() => { throw new Error('must not fetch'); });
  for (const [module, args] of [
    ['__proto__', {}], ['constructor', {}], ['weather', { latitude: 91, longitude: 1 }],
    ['weather', { latitude: '31', longitude: 1 }], ['releases', { repo: 'owner/repo' }],
    ['holidays', { year: 2026 }], ['searchCities', { query: 'a' }],
    ['searchCities', { query: 'a\nb' }], ['fx', { base: 'USD', quote: 'CNY' }],
  ]) await assert.rejects(h.request(module, args));
  await assert.rejects(h.api.request('news', '{broken', false), /有效 JSON/);
  assert.equal(h.calls.length, 0);
});

test('HTML, malformed JSON and oversized responses are rejected without cache', async () => {
  for (const res of [
    () => response('<html>blocked</html>', 200, { 'content-type': 'text/html' }),
    () => response('{oops'),
    () => response(' '.repeat(1_000_001)),
  ]) {
    const h = harness(res);
    await assert.rejects(h.request('weather', { latitude: 1, longitude: 2 }), /JSON|响应过大/);
  }
});

test('request timeout aborts fetch and returns an actionable Chinese error', async () => {
  const h = harness((url, init) => new Promise((resolve, reject) => {
    init.signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' })));
  }), { setTimeout: callback => { queueMicrotask(callback); return 1; }, clearTimeout: () => {} });
  await assert.rejects(h.request('weather', { latitude: 1, longitude: 2 }), /超时/);
});

test('storage denial keeps live modules working and preference writes report failure', async () => {
  const blocked = { getItem() { throw new Error('denied'); }, setItem() { throw new Error('denied'); } };
  const h = harness(() => response(weather()), { storage: blocked });
  assert.equal(h.api.readPreferences(), null);
  assert.equal(h.api.writePreferences('{}'), false);
  assert.equal((await h.request('weather', { latitude: 1, longitude: 2 })).cached, false);
  assert.equal((await h.request('weather', { latitude: 1, longitude: 2 })).cached, true);
});

test('preferences only accept bounded JSON objects and external links require safe protocols', () => {
  const h = harness(() => response([]));
  assert.equal(h.api.writePreferences('{"city":"上海"}'), true);
  assert.equal(h.api.readPreferences(), '{"city":"上海"}');
  for (const bad of ['[1]', 'null', 'oops', `{"text":"${'a'.repeat(20000)}"}`]) assert.equal(h.api.writePreferences(bad), false);
  for (const bad of ['javascript:alert(1)', 'data:text/html,test', 'file:///tmp/file', '//example.com', 'https://user:pass@example.com', 'https://example.com\n']) assert.equal(h.api.openUrl(bad), false);
  assert.equal(h.api.openUrl('https://example.com/path'), true);
  assert.deepEqual(h.opened[0], ['https://example.com/path', '_blank', 'noopener,noreferrer']);
});

test('cache retention is bounded and malformed cache entries are ignored', async () => {
  const shared = storage({ [CACHE_KEY]: '{"weather:broken":{"at":1,"data":{}}}' });
  const h = harness(() => response({}), { storage: shared });
  for (let i = 0; i < 100; i++) {
    await h.request('searchCities', { query: `City ${i}` }); h.advance(1);
  }
  const stored = JSON.parse(shared.getItem(CACHE_KEY));
  assert.ok(Object.keys(stored).length <= 80);
  assert.ok(shared.getItem(CACHE_KEY).length <= 900000);
  assert.equal(Object.hasOwn(stored, 'weather:broken'), false);
});

// The DOM implementation belongs to the browser. These parsed-document fixtures
// exercise the adapter contract; actual XML parsing is also checked in Chromium.
function rssParser(items, { broken = false, channel = true } = {}) {
  return class {
    parseFromString(raw, mime) {
      assert.equal(mime, 'application/xml');
      assert.match(raw, /rss/);
      return {
        querySelector: selector => selector === 'parsererror' ? broken : channel,
        querySelectorAll: () => items.map(item => ({
          querySelector: key => Object.hasOwn(item, key) ? { textContent: item[key] } : null,
        })),
      };
    }
  };
}
const rssItem = (id, extra = {}) => ({ title: `中文资讯 ${id} & 科技`, link: `https://sspai.com/post/${id}`, pubDate: 'Sat, 17 Oct 2026 14:58:04 +0800', description: '<script>unsafe()</script>', ...extra });
const xmlResponse = (xml = '<rss/>') => response(xml, 200, { 'content-type': 'application/xml; charset=UTF-8' });

test('Chinese RSS uses direct official feed, keeps title/link/time only, deduplicates and bounds items', async () => {
  const items = [rssItem(1), rssItem(1), ...Array.from({ length: 20 }, (_, i) => rssItem(i + 2))];
  const h = harness(() => xmlResponse(), { DOMParser: rssParser(items) });
  const result = await h.request('news', { feed: 'sspai' });
  assert.equal(h.calls[0].url, 'https://sspai.com/feed');
  assert.equal(h.calls[0].init.credentials, 'omit');
  assert.equal(result.data.stories.length, 10);
  assert.deepEqual(result.data.stories[0], { title: '中文资讯 1 & 科技', url: 'https://sspai.com/post/1', time: 1792220284, source: '少数派' });
  assert.equal('score' in result.data.stories[0], false);
  assert.equal('description' in result.data.stories[0], false);
  await h.request('news', { feed: 'sspai' });
  assert.equal(h.calls.length, 1);
});

test('Chinese RSS rejects unsafe/off-site links, invalid dates and missing titles without fabricating stories', async () => {
  const items = [rssItem(1), rssItem(2, { link: 'javascript:alert(1)' }), rssItem(3, { link: 'https://evil.test/post/3' }), rssItem(4, { pubDate: 'not a date' }), rssItem(5, { title: ' ' }), rssItem(6, { link: 'https://sspai.com:1234/post/6' })];
  const h = harness(() => xmlResponse(), { DOMParser: rssParser(items) });
  const result = await h.request('news', { feed: 'sspai' });
  assert.equal(result.data.stories.length, 1);
  assert.match(result.warning, /5 条/);
});

test('RSS failures preserve stale cache and original fetched timestamp', async () => {
  let fail = false;
  const h = harness(() => fail ? response('unavailable', 502) : xmlResponse(), { DOMParser: rssParser([rssItem(1)]) });
  const first = await h.request('news', { feed: 'sspai' });
  h.advance(11 * minute); fail = true;
  const stale = await h.request('news', { feed: 'sspai' });
  assert.equal(stale.stale, true);
  assert.equal(stale.fetchedAt, first.fetchedAt);
  assert.equal(stale.data.stories[0].title, first.data.stories[0].title);
  assert.match(stale.warning, /上次保存/);
});

test('RSS rejects malformed XML, HTML, DOCTYPE and all-invalid items; empty channel remains explicit', async () => {
  for (const options of [{ broken: true }, { channel: false }]) {
    const h = harness(() => xmlResponse(), { DOMParser: rssParser([], options) });
    await assert.rejects(h.request('news', { feed: 'sspai' }), /RSS 格式/);
  }
  const doctype = harness(() => xmlResponse('<!DOCTYPE rss><rss/>'));
  await assert.rejects(doctype.request('news', { feed: 'sspai' }), /XML 格式/);
  const html = harness(() => response('<html/>', 200, { 'content-type': 'text/html' }));
  await assert.rejects(html.request('news', { feed: 'sspai' }), /有效 RSS/);
  const invalid = harness(() => xmlResponse(), { DOMParser: rssParser([rssItem(1, { link: 'data:bad' })]) });
  await assert.rejects(invalid.request('news', { feed: 'sspai' }), /无法读取/);
  const empty = harness(() => xmlResponse(), { DOMParser: rssParser([]) });
  assert.deepEqual((await empty.request('news', { feed: 'sspai' })).data.stories, []);
});


test('corrupted Chinese cache cannot serve future dates or a mismatched English feed', async () => {
  const story = { title: '缓存中文', url: 'https://sspai.com/post/1', time: 1792220284, source: '少数派' };
  for (const data of [{ feed: 'sspai', stories: [{ ...story, time: 16725225600 }] }, { feed: 'top', stories: [] }]) {
    const seed = { [CACHE_KEY]: JSON.stringify({ 'news:{"feed":"sspai"}': { at: START, data } }) };
    const h = harness(() => xmlResponse(), { storage: storage(seed), DOMParser: rssParser([rssItem(2)]) });
    const result = await h.request('news', { feed: 'sspai' });
    assert.equal(result.cached, false);
    assert.equal(result.data.stories[0].url, 'https://sspai.com/post/2');
  }
});


test('removed holiday module is rejected and old holiday cache cannot remain active', async () => {
  const seed = { [CACHE_KEY]: JSON.stringify({ 'holidays:{"year":2026}': { at: START, data: { year: 2026, known: true, papers: [], days: [] } } }) };
  const h = harness(() => response({}), { storage: storage(seed) });
  await assert.rejects(h.request('holidays', { year: 2026 }), /不支持/);
  assert.equal(h.calls.length, 0);
  await h.request('searchCities', { query: 'NoSuchCity' });
  assert.equal(Object.keys(JSON.parse(h.storage.getItem(CACHE_KEY))).some(key => key.startsWith('holidays:')), false);
});

test('older weather cache remains honest without invented actual temperature', async () => {
  const shared = storage();
  const h = harness(() => response(weather()), { storage: shared });
  await h.request('weather', { latitude: 1, longitude: 2 });
  const saved = JSON.parse(shared.getItem(CACHE_KEY));
  for (const row of Object.values(saved)[0].data.hours) delete row.temperature;
  shared.setItem(CACHE_KEY, JSON.stringify(saved));
  const reload = harness(() => { throw new Error('must use cache'); }, { storage: shared });
  const result = await reload.request('weather', { latitude: 1, longitude: 2 });
  assert.equal(result.cached, true);
  assert.equal(result.data.hours[0].temperature, undefined);
  assert.equal(result.data.hours[0].feels, 22.1);
});

// Synthetic Binance contracts; live-provider verification is separate.
const symbols = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT'];
const binanceQuotes = () => symbols.map(symbol => ({ symbol, lastPrice: '100.25',
  priceChangePercent: '-2.5', highPrice: '110', lowPrice: '90', volume: '123',
  quoteVolume: '12330.75', openTime: START - day, closeTime: START }));
const binanceCandles = () => [0, 1, 2].map(i => [START - (3 - i) * hour,
  '100', '110', '90', '101', '12', START - (2 - i) * hour - 1, '1212', 10, '6', '606', '0']);

test('Binance public quotes and candles preserve values, identity and UTC times', async () => {
  const h = harness(url => response(url.includes('/ticker/') ? binanceQuotes() : binanceCandles()));
  const quotes = await h.request('cryptoQuotes', {});
  assert.equal(quotes.data.quotes.length, 6);
  assert.equal(quotes.data.quotes[0].price, 100.25);
  assert.equal(quotes.data.quotes[0].changePercent, -2.5);
  assert.equal(quotes.data.quotes[0].closeTime, START);
  const result = await h.request('cryptoCandles', { symbol: 'ETHUSDT', interval: '1h' });
  assert.equal(result.data.symbol, 'ETHUSDT');
  assert.equal(result.data.interval, '1h');
  assert.equal(result.data.candles[0].time, START - 3 * hour);
  assert.equal(result.data.candles[0].quoteVolume, 1212);
  const quoteUrl = new URL(h.calls[0].url), candleUrl = new URL(h.calls[1].url);
  assert.deepEqual(JSON.parse(quoteUrl.searchParams.get('symbols')), symbols);
  assert.equal(quoteUrl.hostname, 'data-api.binance.vision');
  assert.equal(candleUrl.searchParams.get('limit'), '500');
  assert.equal(candleUrl.searchParams.get('timeZone'), '0');
  assert.equal(h.calls[0].init.credentials, 'omit');
  assert.equal(Object.keys(h.calls[0].init.headers).some(k => /key|authorization/i.test(k)), false);
});

test('Binance restricts symbols and intervals before making network requests', async () => {
  const h = harness(() => { throw new Error('must not fetch'); });
  for (const args of [{ symbol: 'BTCUSDT', interval: '__proto__' },
    { symbol: 'https://evil.test', interval: '1h' }, { symbol: 'BTCUSDT', interval: '1s' }]) {
    await assert.rejects(h.request('cryptoCandles', args), /请选择/);
  }
  assert.equal(h.calls.length, 0);
});

test('Binance history pages send exclusive cursor, isolate and restore cached pages', async () => {
  const shared = storage(), args = { symbol:'BTCUSDT', interval:'1h' };
  const cursor = START - 3 * hour - 1;
  const h = harness(url => {
    const end = new URL(url).searchParams.get('endTime');
    return response(binanceCandles().map(row => end ? [row[0]-3*hour,...row.slice(1,6),row[6]-3*hour,...row.slice(7)] : row));
  }, { storage:shared });
  const latest = await h.request('cryptoCandles',args);
  const older = await h.request('cryptoCandles',{...args,endTime:cursor});
  assert.equal(new URL(h.calls[1].url).searchParams.get('endTime'),String(cursor));
  assert.equal(older.data.candles.at(-1).closeTime + 1,latest.data.candles[0].time);
  assert.equal(older.data.endTime,cursor);
  const reload = harness(()=>{throw new Error('must use saved page');},{storage:shared});
  assert.deepEqual((await reload.request('cryptoCandles',args)).data,latest.data);
  assert.deepEqual((await reload.request('cryptoCandles',{...args,endTime:cursor})).data,older.data);
  assert.equal(reload.calls.length,0);
});

test('Binance history rejects invalid cursors and out-of-range responses; coalesces identical pages', async () => {
  const args={symbol:'BTCUSDT',interval:'1h'};
  const invalid=harness(()=>{throw new Error('must not fetch');});
  for(const endTime of [null,-1,0,1.5,'123',START,START+hour,8640000000000000])
    await assert.rejects(invalid.request('cryptoCandles',{...args,endTime}),/时间无效/);
  assert.equal(invalid.calls.length,0);
  const out=harness(()=>response(binanceCandles()));
  await assert.rejects(out.request('cryptoCandles',{...args,endTime:START-3*hour-1}),/格式异常/);
  let finish;
  const h=harness(()=>new Promise(resolve=>{finish=resolve;}));
  const page={...args,endTime:START-1};
  const a=h.request('cryptoCandles',page), b=h.request('cryptoCandles',page);
  assert.equal(h.calls.length,1);
  finish(response([]));
  assert.deepEqual((await a).data.candles,[]);
  assert.deepEqual(await a,await b);
});

test('Binance rejects invalid numbers, OHLC, duplicate times and malformed arrays', async () => {
  for (const mutate of [rows => { rows[0][2] = '1'; }, rows => { rows[0][5] = '-1'; },
    rows => { rows[0][4] = 'NaN'; }, rows => { rows[0][1] = ''; },
    rows => { rows[1] = rows[0]; }, rows => { rows[0][6] += 1; }]) {
    const rows = binanceCandles(); mutate(rows);
    const h = harness(() => response(rows));
    await assert.rejects(h.request('cryptoCandles', { symbol: 'BTCUSDT', interval: '1h' }), /格式异常/);
  }
  const quotes = binanceQuotes(); quotes[1].symbol = 'BTCUSDT';
  await assert.rejects(harness(() => response(quotes)).request('cryptoQuotes', {}), /格式异常/);
  const empty = await harness(() => response([])).request('cryptoCandles', { symbol: 'BTCUSDT', interval: '1h' });
  assert.deepEqual(empty.data.candles, []);
});

test('Binance stale fallback preserves original fetch time and expires after ten minutes', async () => {
  let failed = false;
  const h = harness(() => failed ? response({}, 500) : response(binanceQuotes()));
  const first = await h.request('cryptoQuotes', {});
  await h.request('cryptoQuotes', {}); assert.equal(h.calls.length, 1);
  failed = true; h.advance(30000);
  const stale = await h.request('cryptoQuotes', {}, true);
  assert.equal(stale.stale, true); assert.equal(stale.fetchedAt, first.fetchedAt);
  h.advance(11 * minute);
  await assert.rejects(h.request('cryptoQuotes', {}, true), /HTTP 500/);
});

test('Binance rate-limit and ban responses suppress requests across both modules', async () => {
  for (const status of [429, 418]) {
    const shared = storage();
    const h = harness(() => response({}, status, { 'retry-after': '180' }), { storage: shared });
    await assert.rejects(h.request('cryptoQuotes', {}), /币安行情请求受限/);
    await assert.rejects(h.request('cryptoCandles', { symbol: 'BTCUSDT', interval: '1h' }), /币安行情请求受限/);
    assert.equal(h.calls.length, 1);
    const reopened = harness(() => response(binanceQuotes()), { storage: shared, now: START + minute });
    await assert.rejects(reopened.request('cryptoQuotes', {}), /币安行情请求受限/);
    assert.equal(reopened.calls.length, 0);
    reopened.advance(3 * minute);
    assert.equal((await reopened.request('cryptoQuotes', {})).data.quotes.length, 6);
  }
});

test('Binance regional errors are explicit and quote failure does not block candles', async () => {
  const blocked = harness(() => response({}, 451));
  await assert.rejects(blocked.request('cryptoQuotes', {}), /当前网络或地区不可用/);
  const h = harness(url => response(url.includes('/ticker/') ? {} : binanceCandles(), url.includes('/ticker/') ? 500 : 200));
  await assert.rejects(h.request('cryptoQuotes', {}));
  assert.equal((await h.request('cryptoCandles', { symbol: 'BTCUSDT', interval: '1h' })).data.candles.length, 3);
});


test('order-book conversion uses USDT-base live USD/CNY rates, caches and retains dated stale results', async () => {
  const shared = storage();
  const h = harness(() => response({ data: { currency: 'USDT', rates: { USD: '0.9987', CNY: '6.67' } } }), { storage: shared });
  const first = await h.request('cryptoConversion', {});
  assert.deepEqual(first.data, { base: 'USDT', USD: .9987, CNY: 6.67 });
  assert.equal(h.calls[0].url, 'https://api.coinbase.com/v2/exchange-rates?currency=USDT');
  assert.equal(h.calls[0].init.credentials, 'omit');
  assert.equal((await h.request('cryptoConversion', {})).cached, true);
  assert.equal(h.calls.length, 1);
  const offline = harness(() => { throw new Error('offline'); }, { storage: shared, now: START + 6 * minute });
  const stale = await offline.request('cryptoConversion', {});
  assert.equal(stale.stale, true);
  assert.equal(stale.fetchedAt, first.fetchedAt);
  assert.deepEqual(stale.data, first.data);
  const expired = harness(() => { throw new Error('offline'); }, { storage: shared, now: START + day + 1 });
  await assert.rejects(expired.request('cryptoConversion', {}), /加载失败/);
});

test('invalid conversion data never creates an assumed USDT dollar peg, and throttles retries', async () => {
  for (const data of [
    { currency: 'USD', rates: { USD: '1', CNY: '7' } },
    { currency: 'USDT', rates: { USD: '0', CNY: '7' } },
    { currency: 'USDT', rates: { USD: '1' } },
    { currency: 'USDT', rates: { USD: 'NaN', CNY: '7' } },
    { currency: 'USDT', rates: { USD: '1', CNY: '-7' } },
  ]) {
    const h = harness(() => response({ data }));
    await assert.rejects(h.request('cryptoConversion', {}), /格式异常/);
    await assert.rejects(h.request('cryptoConversion', {}, true), /格式异常/);
    assert.equal(h.calls.length, 1);
  }
});

test('conversion rate limit persists independently of Binance market requests', async () => {
  const shared = storage();
  const h = harness(() => response({}, 429, { 'retry-after': '120' }), { storage: shared });
  await assert.rejects(h.request('cryptoConversion', {}), /请求受限/);
  const reload = harness(() => { throw new Error('should not fetch'); }, { storage: shared, now: START + minute });
  await assert.rejects(reload.request('cryptoConversion', {}), /请求受限/);
  assert.equal(reload.calls.length, 0);
});


const priceRules = () => ({ symbols: ['BTCUSDT','ETHUSDT','BNBUSDT','SOLUSDT','XRPUSDT','DOGEUSDT'].map(symbol => ({symbol,baseAssetPrecision:8,quoteAssetPrecision:8,filters:[{filterType:'PRICE_FILTER',tickSize:symbol==='XRPUSDT'?'0.00010000':symbol==='DOGEUSDT'?'0.00001000':'0.01000000'},{filterType:'LOT_SIZE',stepSize:symbol==='BTCUSDT'?'0.00001000':symbol==='ETHUSDT'?'0.00010000':symbol==='XRPUSDT'?'0.10000000':symbol==='DOGEUSDT'?'1.00000000':'0.00100000'}]})) });
test('book price increments come from exchangeInfo PRICE_FILTER for each supported symbol', async () => {
  const shared = storage();
  const h = harness(() => response(priceRules()), {storage: shared});
  const result = await h.request('cryptoBookRules',{});
  const url = new URL(h.calls[0].url);
  assert.equal(url.hostname,'data-api.binance.vision');
  assert.equal(url.pathname,'/api/v3/exchangeInfo');
  assert.equal(JSON.parse(url.searchParams.get('symbols')).length,6);
  assert.equal(result.data.rules.find(r=>r.symbol==='BTCUSDT').tickSize,'0.01000000');
  assert.equal(result.data.rules.find(r=>r.symbol==='XRPUSDT').tickSize,'0.00010000');
  assert.equal(result.data.rules.find(r=>r.symbol==='DOGEUSDT').tickSize,'0.00001000');
  const reload = harness(() => {throw new Error('offline');},{storage:shared,now:START+30*minute});
  assert.equal((await reload.request('cryptoBookRules',{})).cached,true);
  assert.equal(reload.calls.length,0);
  reload.advance(8 * hour);
  const stale = await reload.request('cryptoBookRules',{});
  assert.equal(stale.stale,true); assert.equal(stale.fetchedAt,result.fetchedAt);
  const expired = harness(() => {throw new Error('offline');},{storage:shared,now:START+day+1});
  assert.equal((await expired.request('cryptoBookRules',{})).stale,true);
});

test('missing, duplicate or invalid price filters never fabricate grouping rules', async () => {
  const variants = [];
  let r=priceRules();r.symbols.pop();variants.push(r);
  r=priceRules();r.symbols[1].symbol='BTCUSDT';variants.push(r);
  r=priceRules();r.symbols[0].filters=[];variants.push(r);
  for(const tickSize of ['0','-0.01','NaN','1e-2','0.000000001']) {
    r=priceRules();r.symbols[0].filters[0].tickSize=tickSize;variants.push(r);
  }
  for(const raw of variants) {
    const h=harness(()=>response(raw));
    await assert.rejects(h.request('cryptoBookRules',{}),/格式异常/);
  }
});


test('exchange rules cache lasts eight hours, then returns old data immediately while one background refresh notifies views', async () => {
  const shared=storage();
  const first=harness(()=>response(priceRules()),{storage:shared});
  const original=await first.request('cryptoBookRules',{});
  assert.equal(original.data.rules[0].stepSize,'0.00001000');
  assert.equal(original.data.rules[0].quoteAssetPrecision,8);
  assert.ok(shared.values.has('shike.crypto.rules.v2'));
  const fresh=harness(()=>{throw new Error('must use cache');},{storage:shared,now:START+8*hour-1});
  assert.equal((await fresh.request('cryptoBookRules',{})).stale,false);
  assert.equal(fresh.calls.length,0);
  let resolve;
  const expired=harness(()=>new Promise(done=>resolve=done),{storage:shared,now:START+8*hour});
  const updates=[];
  expired.api.subscribeCryptoRules(()=>{throw new Error('closed view');});
  const id=expired.api.subscribeCryptoRules(raw=>updates.push(JSON.parse(raw)));
  const cached=await expired.request('cryptoBookRules',{});
  assert.equal(cached.stale,true);assert.equal(cached.fetchedAt,original.fetchedAt);
  assert.deepEqual(cached.data,original.data);assert.equal(expired.calls.length,1);
  await expired.request('cryptoBookRules',{});
  const waiting=expired.request('cryptoBookRules',{},true);
  assert.equal(expired.calls.length,1,'concurrent refreshes share the pending fetch');
  const changed=priceRules();changed.symbols[0].filters[0].tickSize='0.10000000';changed.symbols[0].filters[1].stepSize='0.00100000';changed.symbols[0].quoteAssetPrecision=6;
  resolve(response(changed));const updated=await waiting;
  assert.equal(updated.stale,false);assert.equal(updates.length,1);
  assert.equal(updates[0].data.rules[0].tickSize,'0.10000000');
  assert.equal(updates[0].data.rules[0].stepSize,'0.00100000');assert.equal(updates[0].data.rules[0].quoteAssetPrecision,6);
  assert.equal((await expired.request('cryptoBookRules',{})).data.rules[0].stepSize,'0.00100000');
  expired.api.unsubscribeCryptoRules(id);
  const reopened=harness(()=>{throw new Error('no refetch');},{storage:shared,now:START+9*hour});
  assert.equal((await reopened.request('cryptoBookRules',{})).data.rules[0].quoteAssetPrecision,6);
  assert.equal(reopened.calls.length,0);
});

test('old exchange rules survive failures and cache eviction without changing their original time', async () => {
  const shared=storage();
  const initial=harness(()=>response(priceRules()),{storage:shared});
  const original=await initial.request('cryptoBookRules',{});
  shared.removeItem(CACHE_KEY);
  const offline=harness(()=>{throw new Error('offline');},{storage:shared,now:START+60*day});
  const old=await offline.request('cryptoBookRules',{});
  assert.equal(old.stale,true);assert.deepEqual(old.data,original.data);
  const failed=await offline.request('cryptoBookRules',{},true);
  assert.equal(failed.fetchedAt,original.fetchedAt);assert.equal(offline.calls.length,1);
  const invalid=priceRules();delete invalid.symbols[0].quoteAssetPrecision;
  offline.advance(minute);
  // Invalid cached input is never admitted as a new successful specification.
  const bad=harness(()=>response(invalid),{storage:shared,now:START+61*day});
  const result=await bad.request('cryptoBookRules',{},true);
  assert.equal(result.stale,true);assert.equal(result.fetchedAt,original.fetchedAt);
  assert.deepEqual(result.data,original.data);
});

const PAIRS_KEY = 'shike.crypto.pairs.v1';
function spotPair(baseAsset, quoteAsset, extra = {}) {
  return { symbol: baseAsset + quoteAsset, baseAsset, quoteAsset,
    status: 'TRADING', isSpotTradingAllowed: true, permissions: [], permissionSets: [['SPOT', 'MARGIN']],
    baseAssetPrecision: 8, quoteAssetPrecision: 8,
    filters: [{ filterType: 'PRICE_FILTER', tickSize: '0.00001000' }, { filterType: 'LOT_SIZE', stepSize: '0.00100000' }], ...extra };
}
const spotCatalog = () => ({ symbols: [
  ...symbols.map(symbol => spotPair(symbol.slice(0, -4), 'USDT')),
  spotPair('ETH', 'BTC'), spotPair('BTC', 'USDC'), spotPair('ETH', 'FDUSD'),
] });
const selectedQuote = (symbol, price = '100.25') => ({ ...binanceQuotes()[0], symbol, lastPrice: price });
const settleCatalog = async () => { for (let i = 0; i < 8; i++) await new Promise(setImmediate); };

test('pair catalog admits only real trading Spot pairs using modern or legacy permissions', async () => {
  const catalog = spotCatalog();
  catalog.symbols.push(spotPair('LTC', 'BTC', { permissions: ['SPOT'], permissionSets: undefined, isSpotTradingAllowed: undefined }),
    spotPair('HALT', 'USDT', { status: 'HALT' }), spotPair('BREAK', 'USDC', { status: 'BREAK' }),
    spotPair('MARGIN', 'USDT', { permissionSets: [['MARGIN']] }),
    spotPair('NO', 'BTC', { isSpotTradingAllowed: false }), spotPair('EMPTY', 'BTC', { permissionSets: [] }));
  const h = harness(() => response(catalog));
  const result = await h.request('cryptoPairs', {});
  const url = new URL(h.calls[0].url);
  assert.equal(url.hostname, 'data-api.binance.vision');
  assert.equal(url.pathname, '/api/v3/exchangeInfo');
  assert.equal(url.searchParams.get('permissions'), 'SPOT');
  assert.equal(url.searchParams.get('symbolStatus'), 'TRADING');
  assert.equal(url.searchParams.get('showPermissionSets'), 'true');
  assert.equal(result.data.pairs.length, 10);
  assert.deepEqual(result.data.pairs.find(pair => pair.symbol === 'ETHBTC'), { symbol: 'ETHBTC', baseAsset: 'ETH', quoteAsset: 'BTC' });
  assert.ok(result.data.pairs.some(pair => pair.symbol === 'LTCBTC'));
  assert.ok(!result.data.pairs.some(pair => /HALT|BREAK|MARGIN|NO|EMPTY/.test(pair.symbol)));
  assert.ok(h.storage.getItem(PAIRS_KEY).length <= 3_000_000);
  assert.equal(h.storage.getItem(CACHE_KEY), null, 'metadata is not duplicated into the evictable market cache');
});

test('catalog count, duplicate identity, asset syntax and base/quote composition are validated', async () => {
  for (const raw of [
    { symbols: [] }, { symbols: Array.from({ length: 8001 }, () => spotPair('ETH', 'BTC')) },
    { symbols: [spotPair('ETH', 'BTC'), spotPair('ETH', 'BTC')] },
    { symbols: [spotPair('ETH', 'BTC', { symbol: 'ETHUSDT' })] },
    { symbols: [spotPair('ETH', 'ETH')] },
    { symbols: [spotPair('https://bad', 'USDT')] },
    { symbols: [spotPair('A'.repeat(21), 'BTC')] },
    { symbols: [spotPair('ETH', 'BTC', { status: 'BREAK' })] },
  ]) {
    const h = harness(() => response(raw));
    await assert.rejects(h.request('cryptoPairs', {}), /格式异常/);
    assert.equal(h.storage.getItem(PAIRS_KEY), null);
  }
});

test('catalog response byte bounds abort excessive payloads before parsing or saving', async () => {
  const declared = harness(() => response({}, 200, { 'content-length': '16000001' }));
  await assert.rejects(declared.request('cryptoPairs', {}), /响应过大/);
  assert.equal(declared.calls[0].init.signal.aborted, true);
  const streamed = harness(() => response(' '.repeat(16_000_001)));
  await assert.rejects(streamed.request('cryptoPairs', {}), /响应过大/);
  assert.equal(streamed.calls[0].init.signal.aborted, true);
  assert.equal(streamed.storage.getItem(PAIRS_KEY), null);
});

test('catalog fetches deduplicate, cache for eight hours, and expose dated stale fallback for at most seven days', async () => {
  let finish;
  const shared = storage(), h = harness(() => new Promise(resolve => { finish = resolve; }), { storage: shared });
  const first = h.request('cryptoPairs', {}), second = h.request('cryptoPairs', {}, true);
  assert.equal(h.calls.length, 1); finish(response(spotCatalog()));
  const original = await first;
  assert.deepEqual(await second, original);
  assert.equal((await h.request('cryptoPairs', {}, true)).cached, true);
  assert.equal(h.calls.length, 1);
  const fresh = harness(() => { throw new Error('offline'); }, { storage: shared, now: START + 8 * hour - 1 });
  assert.equal((await fresh.request('cryptoPairs', {})).stale, false); assert.equal(fresh.calls.length, 0);
  fresh.advance(1);
  const stale = await fresh.request('cryptoPairs', {});
  assert.equal(stale.stale, true); assert.equal(stale.fetchedAt, original.fetchedAt);
  await settleCatalog();
  assert.equal((await fresh.request('cryptoPairs', {}, true)).stale, true); assert.equal(fresh.calls.length, 1);
  const expired = harness(() => response({}, 500), { storage: shared, now: START + 7 * day + 1 });
  await assert.rejects(expired.request('cryptoPairs', {}), /HTTP 500/);
});

test('selected quote, candles and rules resolve a non-USDT catalog pair without downloading other tickers', async () => {
  const h = harness(url => response(url.includes('exchangeInfo') ? spotCatalog()
    : url.includes('/ticker/') ? selectedQuote(new URL(url).searchParams.get('symbol')) : binanceCandles()));
  const quotes = await h.request('cryptoQuotes', { symbol: 'ETHBTC' });
  assert.deepEqual(quotes.data.quotes.map(row => row.symbol), ['ETHBTC']);
  assert.equal(quotes.warning, undefined);
  const quoteUrl = new URL(h.calls[1].url);
  assert.equal(quoteUrl.searchParams.get('symbol'), 'ETHBTC');
  assert.equal(quoteUrl.searchParams.has('symbols'), false);
  const candles = await h.request('cryptoCandles', { symbol: 'ETHBTC', interval: '1h' });
  assert.equal(candles.data.symbol, 'ETHBTC');
  const rules = await h.request('cryptoBookRules', { symbol: 'ETHBTC' });
  assert.equal(rules.data.rules.length, 1); assert.equal(rules.data.rules[0].symbol, 'ETHBTC');
  assert.equal(h.calls.filter(call => call.url.includes('exchangeInfo')).length, 1);
  assert.equal(h.calls.length, 3);
  const unknown = h.request('cryptoQuotes', { symbol: 'ETHUSDC' });
  await assert.rejects(unknown, /不在当前/);
  assert.equal(h.calls.length, 3, 'never synthesize ETHUSDC merely because ETH and USDC were seen separately');
});

test('selected default quotes remain single-symbol before catalog bootstrap and overview keeps its six defaults', async () => {
  const h = harness(url => response(new URL(url).searchParams.has('symbol') ? selectedQuote('BTCUSDT') : binanceQuotes()));
  const selected = await h.request('cryptoQuotes', { symbol: 'BTCUSDT' });
  assert.equal(selected.data.quotes.length, 1);
  const overview = await h.request('cryptoQuotes', {});
  assert.equal(overview.data.quotes.length, 6);
  assert.equal(h.calls.length, 2); assert.ok(h.calls.every(call => call.url.includes('/ticker/')));
  assert.equal((await h.request('cryptoQuotes', { symbol: 'BTCUSDT' })).data.quotes.length, 1);
});

test('selected quotes reject a foreign response and mismatched cached identities', async () => {
  const wrong = harness(() => response(selectedQuote('ETHUSDT')));
  await assert.rejects(wrong.request('cryptoQuotes', { symbol: 'BTCUSDT' }), /格式异常/);
  const shared = storage(), valid = harness(() => response(selectedQuote('ETHUSDT')), { storage: shared });
  await valid.request('cryptoQuotes', { symbol: 'ETHUSDT' });
  const cache = JSON.parse(shared.getItem(CACHE_KEY));
  cache['cryptoQuotes:{"symbol":"BTCUSDT"}'] = cache['cryptoQuotes:{"symbol":"ETHUSDT"}'];
  shared.setItem(CACHE_KEY, JSON.stringify(cache));
  const reload = harness(() => response(selectedQuote('BTCUSDT')), { storage: shared });
  assert.equal((await reload.request('cryptoQuotes', { symbol: 'BTCUSDT' })).cached, false);
  assert.equal(reload.calls.length, 1);
});

test('missing catalog price filters remain explicitly unavailable, without fabricated grouping increments', async () => {
  const catalog = { symbols: [spotPair('ETH', 'BTC', { filters: [] })] };
  const h = harness(() => response(catalog));
  assert.equal((await h.request('cryptoPairs', {})).data.pairs.length, 1);
  await assert.rejects(h.request('cryptoBookRules', { symbol: 'ETHBTC' }), /未提供有效/);
  assert.equal(h.calls.length, 1);
});

test('non-USDT conversion sends the actual quote currency and never reuses another base or assumes parity', async () => {
  const h = harness(url => {
    const base = new URL(url).searchParams.get('currency');
    return response({ data: { currency: base, rates: { USD: base === 'BTC' ? '67000.12' : '1.0002', CNY: base === 'BTC' ? '480000.25' : '7.0003' } } });
  });
  const btc = await h.request('cryptoConversion', { base: 'BTC' });
  assert.deepEqual(btc.data, { base: 'BTC', USD: 67000.12, CNY: 480000.25 });
  const usdc = await h.request('cryptoConversion', { base: 'USDC' });
  assert.equal(usdc.data.USD, 1.0002); assert.equal(h.calls.length, 2);
  assert.equal((await h.request('cryptoConversion', { base: 'BTC' })).cached, true);
  const unsupported = harness(() => response({ data: { currency: 'USD', rates: { USD: '1', CNY: '7' } } }));
  await assert.rejects(unsupported.request('cryptoConversion', { base: 'FDUSD' }), /格式异常/);
  for (const base of [null, '', 'a&b', 'https://bad']) await assert.rejects(unsupported.request('cryptoConversion', { base }), /有效的计价币/);
});

test('cancelling selected REST aborts every interval and quote, but not overview or another symbol', async () => {
  const pending = [];
  const h = harness((url, init) => new Promise(resolve => { pending.push({ url, init, resolve }); }));
  const a = h.request('cryptoQuotes', { symbol: 'BTCUSDT' });
  const b = h.request('cryptoCandles', { symbol: 'BTCUSDT', interval: '1h' });
  const c = h.request('cryptoQuotes', { symbol: 'ETHUSDT' });
  const d = h.request('cryptoQuotes', {});
  const rejectA = assert.rejects(a, /取消/), rejectB = assert.rejects(b, /取消/);
  h.api.cancelCryptoRequests('BTCUSDT');
  assert.deepEqual(pending.map(row => row.init.signal.aborted), [true, true, false, false]);
  pending[0].resolve(response(selectedQuote('BTCUSDT'))); pending[1].resolve(response(binanceCandles()));
  pending[2].resolve(response(selectedQuote('ETHUSDT'))); pending[3].resolve(response(binanceQuotes()));
  await Promise.all([rejectA, rejectB, c, d]);
  const keys = Object.keys(JSON.parse(h.storage.getItem(CACHE_KEY)));
  assert.equal(keys.some(key => key.includes('BTCUSDT')), false);
});

test('immediate reselection gets a new REST request and late cancelled data cannot clear or overwrite it', async () => {
  const pending = [], h = harness(() => new Promise(resolve => pending.push(resolve)));
  const first = h.request('cryptoQuotes', { symbol: 'BTCUSDT' });
  const rejected = assert.rejects(first, /取消/);
  h.api.cancelCryptoRequests('BTCUSDT');
  const second = h.request('cryptoQuotes', { symbol: 'BTCUSDT' });
  assert.equal(h.calls.length, 2);
  pending[0](response(selectedQuote('BTCUSDT', '99'))); await rejected;
  const third = h.request('cryptoQuotes', { symbol: 'BTCUSDT' });
  assert.equal(h.calls.length, 2, 'late finally must not remove the replacement inflight entry');
  pending[1](response(selectedQuote('BTCUSDT', '102')));
  assert.deepEqual(await third, await second);
  assert.equal((await h.request('cryptoQuotes', { symbol: 'BTCUSDT' })).data.quotes[0].price, 102);
});

test('cancelling during shared catalog bootstrap prevents the obsolete market fetch without aborting metadata', async () => {
  let finish;
  const h = harness(url => url.includes('exchangeInfo') ? new Promise(resolve => { finish = resolve; }) : response(selectedQuote('BTCUSDC')));
  const old = h.request('cryptoQuotes', { symbol: 'ETHBTC' }), rejected = assert.rejects(old, /取消/);
  h.api.cancelCryptoRequests('ETHBTC');
  const next = h.request('cryptoQuotes', { symbol: 'BTCUSDC' });
  assert.equal(h.calls.length, 1); assert.equal(h.calls[0].init.signal.aborted, false);
  finish(response(spotCatalog())); await rejected;
  assert.equal((await next).data.quotes[0].symbol, 'BTCUSDC');
  assert.equal(h.calls.length, 2);
  assert.equal(new URL(h.calls[1].url).searchParams.get('symbol'), 'BTCUSDC');
});

test('visiting many catalog pairs keeps quote caches bounded rather than one durable store per symbol', async () => {
  const catalog = { symbols: Array.from({ length: 120 }, (_, i) => spotPair(`COIN${i}`, 'BTC')) };
  const shared = storage(), h = harness(url => response(url.includes('exchangeInfo') ? catalog : selectedQuote(new URL(url).searchParams.get('symbol'))), { storage: shared });
  await h.request('cryptoPairs', {});
  for (const pair of catalog.symbols) { await h.request('cryptoQuotes', { symbol: pair.symbol }); h.advance(1); }
  assert.ok(Object.keys(JSON.parse(shared.getItem(CACHE_KEY))).length <= 80);
  assert.ok(shared.getItem(CACHE_KEY).length <= 900000);
  assert.ok(shared.values.size <= 3, 'one market cache, one catalog and one host-limits store only');
});

test('unsupported punctuation cannot poison or be relabeled within an otherwise valid catalog', async () => {
  const h = harness(() => response({ symbols: [spotPair('ETH', 'BTC'), spotPair('BAD/NAME', 'USDT')] }));
  const result = await h.request('cryptoPairs', {});
  assert.deepEqual(result.data.pairs, [{ symbol: 'ETHBTC', baseAsset: 'ETH', quoteAsset: 'BTC' }]);
  assert.match(result.warning, /1 个交易对名称暂不支持/);
  assert.match((await h.request('cryptoPairs', {})).warning, /1 个交易对名称暂不支持/);
});

test('a fresh verified catalog removes delisted symbols even when their market data is still cached', async () => {
  let catalog = spotCatalog();
  const h = harness(url => response(url.includes('exchangeInfo') ? catalog : selectedQuote('ETHBTC')));
  await h.request('cryptoQuotes', { symbol: 'ETHBTC' });
  h.advance(minute);
  catalog = { symbols: [spotPair('BTC', 'USDC')] };
  await h.request('cryptoPairs', {}, true);
  const count = h.calls.length;
  await assert.rejects(h.request('cryptoQuotes', { symbol: 'ETHBTC' }), /不在当前/);
  assert.equal(h.calls.length, count);
});

test('UTF-8 catalog symbols preserve exact assets in selected REST calls, rules and persisted cache', async () => {
  const shared = storage(), symbol = '币安人生USDT';
  const h = harness(url => {
    const parsed = new URL(url);
    if (url.includes('exchangeInfo')) return response({ symbols: [spotPair('币安人生', 'USDT')] });
    assert.equal(parsed.searchParams.get('symbol'), symbol);
    assert.ok(!url.includes('币安人生'), 'request URLs percent-encode UTF-8 names');
    return response(url.includes('/ticker/') ? selectedQuote(symbol) : binanceCandles());
  }, { storage: shared });
  const catalog = await h.request('cryptoPairs', {});
  assert.deepEqual(catalog.data.pairs, [{ symbol, baseAsset: '币安人生', quoteAsset: 'USDT' }]);
  assert.equal(catalog.warning, undefined);
  const quotes = await h.request('cryptoQuotes', { symbol });
  assert.equal(quotes.data.quotes[0].symbol, symbol);
  const candles = await h.request('cryptoCandles', { symbol, interval: '1h' });
  assert.equal(candles.data.symbol, symbol);
  assert.equal((await h.request('cryptoBookRules', { symbol })).data.rules[0].symbol, symbol);
  const reload = harness(() => { throw new Error('must use cache'); }, { storage: shared });
  assert.equal((await reload.request('cryptoQuotes', { symbol })).cached, true);
  assert.equal((await reload.request('cryptoCandles', { symbol, interval: '1h' })).cached, true);
  assert.equal(reload.calls.length, 0);
});

function chineseSnapshot() {
  return {schemaVersion: 1, generatedAt: new Date(START).toISOString(), sources: [
    {id:'sspai',name:'少数派',status:'ok',fetchedAt:new Date(START).toISOString()},
    {id:'ithome',name:'IT之家',status:'unavailable',fetchedAt:null},
    {id:'solidot',name:'Solidot',status:'cached',fetchedAt:new Date(START-hour).toISOString()},
  ], stories: [
    {title:'未知',url:'https://sspai.com/post/1',sourceId:'sspai',source:'少数派',time:null},
    {title:'旧文',url:'https://www.solidot.org/story?sid=2',sourceId:'solidot',source:'Solidot',time:START/1000-100},
    {title:'新文',url:'https://sspai.com/post/3',sourceId:'sspai',source:'少数派',time:START/1000},
    {title:'新文',url:'https://sspai.com/post/3',sourceId:'sspai',source:'少数派',time:START/1000},
  ]};
}
test('Chinese aggregation uses same-origin snapshot, publication sort, dedup, unknown last and partial status', async () => {
  const h=harness(()=>response(chineseSnapshot()));
  const r=await h.request('news',{feed:'zh'});
  assert.deepEqual(r.data.stories.map(s=>s.title),['新文','旧文','未知']);
  assert.match(r.warning,/IT之家暂不可用/); assert.match(r.warning,/Solidot暂不可用，显示缓存/);
  assert.match(h.calls[0].url,/time_nest\/news.json$/); assert.equal(h.calls[0].init.cache,'no-store');
});
test('Chinese snapshot stale label and invalid source URL rejection', async () => {
  const stale=chineseSnapshot();stale.generatedAt=new Date(START-day).toISOString();
  assert.match((await harness(()=>response(stale)).request('news',{feed:'zh'})).warning,/快照较旧/);
  const bad=chineseSnapshot();bad.stories[0].url='https://evil.example/post/1';
  await assert.rejects(harness(()=>response(bad)).request('news',{feed:'zh'}),/暂不可用/);
});
test('corrupted Chinese snapshot source cannot prevent API startup', async () => {
  const bad = {...chineseSnapshot(), feed:'zh', sources:[null,{},{}]};
  const h = harness(()=>response(chineseSnapshot()), {storage:storage({[CACHE_KEY]:JSON.stringify({['news:'+JSON.stringify({feed:'zh'})]:{data:bad,fetchedAt:START}})})});
  assert.ok(h.api);
  assert.equal((await h.request('news',{feed:'zh'})).data.stories.length,3);
});
test('same-origin news snapshot respects Retry-After without NaN', async () => {
  const h=harness(()=>response({},429,{'retry-after':'120'}));
  await assert.rejects(h.request('news',{feed:'zh'}), /2 分钟/);
  await assert.rejects(h.request('news',{feed:'zh'},true), /2 分钟/);
  assert.equal(h.calls.length,1);
});

test('news bodies need code-side permission: forged RSS/full/HTML fields never reach reader or cache', async () => {
  const payload = chineseSnapshot();
  payload.html = '<script>run()</script>';
  for (const story of payload.stories) Object.assign(story, {
    body: '<iframe src="https://tracking.test"></iframe>', summary: 'Not permitted',
    content: {kind:'full',format:'plain_text',text:'Not permitted',licenseUrl:'https://example.test/license'},
  });
  const h = harness(() => response(payload));
  const r = await h.request('news', {feed:'zh'});
  assert.equal(h.calls.length,1);
  assert.equal(h.opened.length,0);
  assert.equal(r.data.html,undefined);
  for (const story of r.data.stories) {
    assert.deepEqual(story.content,{kind:'unavailable',reason:'permission_required'});
    assert.equal(story.body,undefined); assert.equal(story.summary,undefined);
  }
  const persisted = h.storage.getItem(CACHE_KEY);
  assert.doesNotMatch(persisted,/Not permitted|tracking.test|iframe|run\(\)/);
});

test('schema1 metadata snapshots and old cached body claims migrate without losing timestamps or offline data', async () => {
  const data = {...chineseSnapshot(),feed:'zh'};
  for (const story of data.stories) story.content = {kind:'full',format:'plain_text',text:'Forged cached body',licenseUrl:'https://example.test/license'};
  const store = storage({[CACHE_KEY]:JSON.stringify({['news:'+JSON.stringify({feed:'zh'})]:{at:START,data}})});
  const h = harness(() => {throw new Error('offline');}, {storage:store});
  const result = await h.request('news',{feed:'zh'});
  assert.equal(result.cached,true); assert.equal(result.fetchedAt,new Date(START).toISOString());
  assert.equal(h.calls.length,0);
  assert.ok(result.data.stories.every(s=>s.content.kind === 'unavailable' && !s.content.text));
  assert.doesNotMatch(store.getItem(CACHE_KEY),/Forged cached body/);
  h.advance(11*minute);
  const stale = await h.request('news',{feed:'zh'});
  assert.equal(stale.stale,true); assert.equal(stale.fetchedAt,result.fetchedAt);
  assert.doesNotMatch(JSON.stringify(stale),/Forged cached body/);
});

test('legacy HN and direct RSS cache unknown body fields are stripped too', async () => {
  const stories = [
    {feed:'sspai',stories:[{title:'Synthetic RSS',url:'https://sspai.com/post/1',source:'少数派',time:START/1000,body:'bad',content:{kind:'full',text:'bad'}}]},
    {feed:'top',stories:[{id:1,title:'Synthetic HN',url:'https://example.test/post',discussion:'https://news.ycombinator.com/item?id=1',score:1,comments:0,time:START/1000,by:'test',body:'bad',content:{kind:'full',text:'bad'}}]},
  ];
  for (const data of stories) {
    const store = storage({[CACHE_KEY]:JSON.stringify({['news:'+JSON.stringify({feed:data.feed})]:{at:START,data}})});
    const h = harness(()=>{throw new Error('offline');},{storage:store});
    const result = await h.request('news',{feed:data.feed});
    assert.equal(result.cached,true); assert.equal(h.calls.length,0);
    assert.equal(result.data.stories[0].body,undefined); assert.equal(result.data.stories[0].content,undefined);
  }
});


test('reviewed synthetic grants accept only exact plain-text mode and license, bounded by Unicode characters', async () => {
  assert.match(source,/const newsContentGrants = Object.freeze\(\{\}\);/);
  for (const mode of ['excerpt','full']) {
    const limit = mode === 'full' ? 24000 : 280;
    const newsContentGrants = {sspai:{mode,licenseUrl:'https://example.test/license'}};
    const base = {kind:mode,format:'plain_text',text:'🧪'.repeat(limit),licenseUrl:'https://example.test/license'};
    const make = content => {
      const data = chineseSnapshot();
      data.stories[2].content = content;
      return data;
    };
    const good = await harness(()=>response(make(base)),{newsContentGrants}).request('news',{feed:'zh'});
    assert.deepEqual(good.data.stories[0].content,base);
    for (const changed of [
      {kind:mode === 'full' ? 'excerpt' : 'full'}, {format:'html'},
      {licenseUrl:'javascript:alert(1)'}, {licenseUrl:'https://other.test/license'},
      {text:'🧪'.repeat(limit+1)}, {text:'unsafe\u0000control'}, {text:'unsafe\u202econtrol'},
      {text:[]}, {text:' '},
    ]) {
      const h = harness(()=>response(make({...base,...changed})),{newsContentGrants});
      const result = await h.request('news',{feed:'zh'});
      assert.deepEqual(result.data.stories[0].content,{kind:'unavailable',reason:'invalid_content'});
      assert.equal(h.calls.length,1); assert.equal(h.opened.length,0);
    }
    const missing = await harness(()=>response(make(null)),{newsContentGrants}).request('news',{feed:'zh'});
    assert.equal(missing.data.stories[0].content.reason,'not_provided');
    const malformed = await harness(()=>response(make({kind:'unavailable',reason:'<script>'})),{newsContentGrants}).request('news',{feed:'zh'});
    assert.equal(malformed.data.stories[0].content.reason,'not_provided');
  }
});

test('denied cache writes do not expose old body claims or prevent cached news reading', async () => {
  const data = {...chineseSnapshot(),feed:'zh'};
  data.stories[0].content = {kind:'full',format:'plain_text',text:'Old forbidden body',licenseUrl:'https://example.test/license'};
  const store = storage({[CACHE_KEY]:JSON.stringify({['news:'+JSON.stringify({feed:'zh'})]:{at:START,data}})});
  store.setItem = () => {throw new Error('storage denied');};
  const h = harness(()=>{throw new Error('offline');},{storage:store});
  const result = await h.request('news',{feed:'zh'});
  assert.equal(result.cached,true); assert.equal(h.calls.length,0);
  assert.doesNotMatch(JSON.stringify(result),/Old forbidden body/);
});
