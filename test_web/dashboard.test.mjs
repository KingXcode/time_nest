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
const holiday = (year = 2026, days = []) => ({ year, papers: [`https://www.gov.cn/holiday-${year}`], days });
const weather = () => ({
  timezone: 'Asia/Shanghai', utc_offset_seconds: 28800,
  hourly: {
    time: ['2026-10-18T08:00', '2026-10-18T09:00'],
    apparent_temperature: [22.1, 23], precipitation_probability: [0, 40],
    wind_speed_10m: [10, 12], weather_code: [0, 3],
  },
});
const release = (tag = 'v1.0') => ({ tag_name: tag, name: 'Release', published_at: '2026-10-17T10:00:00Z', html_url: `https://github.com/flutter/flutter/releases/tag/${tag}`, body: 'Release notes' });

test('holiday normalization preserves false adjusted workdays, official papers and next-notice overrides', async () => {
  const h = harness(url => url.endsWith('/2026.json')
    ? response(holiday(2026, [
      { date: '2026-10-10', name: '国庆节', isOffDay: false },
      { date: '2026-10-01', name: '国庆节', isOffDay: true },
      { date: '2026-12-31', name: '元旦', isOffDay: true },
    ]), 200, { 'content-type': 'text/plain; charset=utf-8' })
    : response(holiday(2027, [
      { date: '2026-12-31', name: '元旦', isOffDay: false },
      { date: '2027-01-01', name: '元旦', isOffDay: true },
    ])));
  const result = await h.request('holidays', { year: 2026 });
  assert.equal(result.data.known, true);
  assert.equal(result.data.boundaryKnown, true);
  assert.deepEqual(result.data.days.map(d => [d.date, d.isOffDay]), [
    ['2026-10-01', true], ['2026-10-10', false], ['2026-12-31', false],
  ]);
  assert.equal(result.data.papers.length, 2);
  assert.equal(result.fetchedAt, new Date(START).toISOString());
  assert.equal(result.cached, false);
  assert.equal(result.stale, false);
});

test('a missing holiday year is unknown, negatively cached per year without guessing', async () => {
  const h = harness(() => response('404: Not Found', 404, { 'content-type': 'text/plain' }));
  const first = await h.request('holidays', { year: 2099 });
  assert.deepEqual(first.data, { year: 2099, known: false, boundaryKnown: false, days: [], papers: [] });
  const second = await h.request('holidays', { year: 2099 });
  assert.equal(second.cached, true);
  assert.equal(h.calls.length, 1);
  await h.request('holidays', { year: 2098 });
  assert.equal(h.calls.length, 2);
  h.advance(6 * hour + 1);
  await h.request('holidays', { year: 2099 });
  assert.equal(h.calls.length, 3);
});

test('missing following-year notice warns without inventing December adjustments', async () => {
  const h = harness(url => url.endsWith('/2026.json') ? response(holiday(2026)) : response('', 404));
  const result = await h.request('holidays', { year: 2026 });
  assert.equal(result.data.known, true);
  assert.equal(result.data.boundaryKnown, false);
  assert.match(result.warning, /12 月/);
  h.advance(2 * hour);
  assert.equal((await h.request('holidays', { year: 2026 })).cached, true);
  assert.equal(h.calls.length, 2);
});

test('holiday boolean strings and mismatched years are rejected', async () => {
  const h = harness(() => response(holiday(2026, [{ date: '2026-10-10', name: '国庆节', isOffDay: 'false' }])));
  await assert.rejects(h.request('holidays', { year: 2026 }), /格式异常/);
  const other = harness(() => response(holiday(2025)));
  await assert.rejects(other.request('holidays', { year: 2026 }), /格式异常/);
});

test('weather requests 24 city-local hours and normalizes probability, km/h and timezone', async () => {
  const h = harness(() => response(weather()));
  const result = await h.request('weather', { latitude: 31.222222, longitude: 121.45806 });
  assert.deepEqual(result.data, { hours: [
    { time: '2026-10-18T08:00', feels: 22.1, rain: 0, wind: 10, code: 0 },
    { time: '2026-10-18T09:00', feels: 23, rain: 40, wind: 12, code: 3 },
  ], timezone: 'Asia/Shanghai', utcOffsetSeconds: 28800 });
  const url = new URL(h.calls[0].url);
  assert.equal(url.searchParams.get('forecast_hours'), '24');
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

test('Frankfurter v2 latest and 30-day daily history preserve pair and dates', async () => {
  const h = harness(url => response(url.includes('/rate/')
    ? { base: 'USD', quote: 'CNY', rate: 6.68, date: '2026-10-17' }
    : [
      { base: 'USD', quote: 'CNY', rate: 6.7, date: '2026-10-16' },
      { base: 'USD', quote: 'CNY', rate: 6.68, date: '2026-10-17' },
    ]));
  assert.deepEqual((await h.request('fx', { base: 'usd', quote: 'cny' })).data, {
    base: 'USD', quote: 'CNY', rate: 6.68, date: '2026-10-17', history: [
      { date: '2026-10-16', rate: 6.7 }, { date: '2026-10-17', rate: 6.68 },
    ],
  });
  const historyUrl = new URL(h.calls.find(c => c.url.includes('/rates?')).url);
  assert.equal(historyUrl.searchParams.get('from'), '2026-09-19');
  assert.equal(historyUrl.searchParams.get('to'), '2026-10-18');
  assert.equal(historyUrl.searchParams.get('quotes'), 'CNY');
});

test('invalid/unsupported currencies and mismatched response pairs fail honestly', async () => {
  const unsupported = harness(() => response({ message: 'invalid currency' }, 422));
  await assert.rejects(unsupported.request('fx', { base: 'XYZ', quote: 'USD' }), /暂不支持/);
  const mismatch = harness(url => response(url.includes('/rate/') ? { base: 'EUR', quote: 'CNY', rate: 7, date: '2026-10-17' } : []));
  await assert.rejects(mismatch.request('fx', { base: 'USD', quote: 'CNY' }), /格式异常/);
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
    ['holidays', { year: 2026.5 }], ['searchCities', { query: 'a' }],
    ['searchCities', { query: 'a\nb' }], ['fx', { base: 'USD&x=', quote: 'CNY' }],
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
  for (let i = 0; i < 60; i++) {
    await h.request('searchCities', { query: `City ${i}` }); h.advance(1);
  }
  const stored = JSON.parse(shared.getItem(CACHE_KEY));
  assert.ok(Object.keys(stored).length <= 48);
  assert.ok(shared.getItem(CACHE_KEY).length <= 900000);
  assert.equal(Object.hasOwn(stored, 'weather:broken'), false);
});

test('same-currency FX pair uses provider-confirmed identity rates and actual observation dates', async () => {
  const rows = [
    { base: 'USD', quote: 'USD', rate: 1, date: '2026-10-16' },
    { base: 'USD', quote: 'USD', rate: 1, date: '2026-10-17' },
  ];
  const h = harness(url => response(url.includes('/rate/') ? rows[1] : rows));
  const result = await h.request('fx', { base: 'USD', quote: 'USD' });
  assert.equal(result.data.rate, 1);
  assert.equal(result.data.date, '2026-10-17');
  assert.deepEqual(result.data.history, [
    { date: '2026-10-16', rate: 1 }, { date: '2026-10-17', rate: 1 },
  ]);
  assert.equal(h.calls.length, 2);
  assert.ok(h.calls.some(call => call.url.endsWith('/rate/USD/USD')));
});
