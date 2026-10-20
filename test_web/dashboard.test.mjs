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
    URL, URLSearchParams, AbortController, Date: TestDate, localStorage,
    DOMParser: options.DOMParser,
    setTimeout: options.setTimeout ?? setTimeout,
    clearTimeout: options.clearTimeout ?? clearTimeout,
    open: (...args) => opened.push(args),
    fetch: async (url, init) => { calls.push({ url, init }); return fetcher(url, init); },
  };
  vm.runInNewContext(source, context);
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
const release = (tag = 'v1.0') => ({ tag_name: tag, name: 'Release', published_at: '2026-10-17T10:00:00Z', html_url: `https://github.com/flutter/flutter/releases/tag/${tag}`, body: 'Release notes' });

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
  const a = h.request('releases', { repo: 'Flutter/Flutter' });
  const b = h.request('releases', { repo: 'flutter/flutter' }, true);
  assert.equal(h.calls.length, 1);
  finish(response([release()]));
  const [one, two] = await Promise.all([a, b]);
  assert.deepEqual(one, two);
  const three = await h.request('releases', { repo: 'flutter/flutter' }, true);
  assert.equal(three.cached, true);
  assert.match(three.warning, /频繁/);
  assert.equal(h.calls.length, 1);
});

test('GitHub release contracts distinguish no releases from missing repo', async () => {
  const h = harness(() => response([release()]));
  const data = (await h.request('releases', { repo: 'flutter/flutter' })).data;
  assert.deepEqual(data, { repo: 'flutter/flutter', noReleases: false, releases: [{ name: 'Release', tag: 'v1.0', publishedAt: '2026-10-17T10:00:00Z', url: 'https://github.com/flutter/flutter/releases/tag/v1.0', body: 'Release notes' }] });
  const empty = harness(() => response([]));
  assert.deepEqual((await empty.request('releases', { repo: 'owner/repo' })).data, { repo: 'owner/repo', releases: [], noReleases: true });
  const missing = harness(() => response({ message: 'Not Found' }, 404));
  await assert.rejects(missing.request('releases', { repo: 'owner/repo' }), /找不到公开仓库/);
});

test('GitHub rate limits use reset and Retry-After; cross-repo refresh and reload honor backoff', async () => {
  const shared = storage();
  const h = harness(() => response({}, 403, { 'x-ratelimit-remaining': '0', 'x-ratelimit-reset': String((START + 10 * minute) / 1000), 'retry-after': '120' }), { storage: shared });
  await assert.rejects(h.request('releases', { repo: 'a/b' }), /GitHub请求受限/);
  await assert.rejects(h.request('releases', { repo: 'c/d' }, true), /GitHub请求受限/);
  assert.equal(h.calls.length, 1);
  const reload = harness(() => response([]), { storage: shared });
  await assert.rejects(reload.request('releases', { repo: 'e/f' }, true), /GitHub请求受限/);
  assert.equal(reload.calls.length, 0);
  reload.advance(11 * minute);
  assert.equal((await reload.request('releases', { repo: 'e/f' }, true)).data.noReleases, true);
});

test('rate-limited refresh returns stale GitHub data instead of hiding saved release', async () => {
  let limited = false;
  const h = harness(() => limited ? response({}, 429, { 'retry-after': '60' }) : response([release()]));
  await h.request('releases', { repo: 'flutter/flutter' });
  limited = true; h.advance(hour + 1);
  const result = await h.request('releases', { repo: 'flutter/flutter' }, true);
  assert.equal(result.stale, true);
  assert.equal(result.data.releases[0].tag, 'v1.0');
  assert.match(result.warning, /GitHub请求受限/);
});

test('a successful GitHub response with zero remaining prevents the next request', async () => {
  const h = harness(() => response([], 200, { 'x-ratelimit-remaining': '0', 'x-ratelimit-reset': String((START + hour) / 1000) }));
  assert.equal((await h.request('releases', { repo: 'a/b' })).data.noReleases, true);
  await assert.rejects(h.request('releases', { repo: 'c/d' }), /GitHub请求受限/);
  assert.equal(h.calls.length, 1);
});

test('anonymous GitHub rolling budget stays below the public quota', async () => {
  const h = harness(() => response([]));
  for (let i = 0; i < 40; i++) {
    await h.request('releases', { repo: `owner/repo-${i}` });
    h.advance(1);
  }
  await assert.rejects(h.request('releases', { repo: 'owner/next' }), /GitHub请求受限/);
  assert.equal(h.calls.length, 40);
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
    ['weather', { latitude: '31', longitude: 1 }], ['releases', { repo: 'a/../../b' }],
    ['releases', { repo: 'https://github.com/a/b' }], ['releases', { repo: 'a/..' }],
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
    await assert.rejects(h.request('releases', { repo: 'a/b' }), /JSON|响应过大/);
  }
});

test('request timeout aborts fetch and returns an actionable Chinese error', async () => {
  const h = harness((url, init) => new Promise((resolve, reject) => {
    init.signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' })));
  }), { setTimeout: callback => { queueMicrotask(callback); return 1; }, clearTimeout: () => {} });
  await assert.rejects(h.request('releases', { repo: 'a/b' }), /超时/);
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
