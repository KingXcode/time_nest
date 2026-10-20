// Public read-only APIs. No credentials, location permission or tracking.
// Provider documentation: open-meteo.com/en/docs,
// developers.binance.com/docs/binance-spot-api-docs/faqs/market_data_only,
// github.com/HackerNews/API,
// docs.github.com/en/rest/releases/releases, sspai.com/post/24194 (official RSS).
(() => {
  'use strict';
  const MINUTE = 60_000, HOUR = 60 * MINUTE, DAY = 24 * HOUR;
  const CACHE_KEY = 'shike.dashboard.cache.v1';
  const LIMIT_KEY = 'shike.dashboard.limits.v1';
  const PREF_KEY = 'shike.dashboard.preferences.v1';
  const MAX_CACHE_ENTRIES = 80, MAX_CACHE_BYTES = 900_000;
  const cryptoSymbols = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT'];
  const cryptoIntervals = { '15m': 900000, '1h': 3600000, '4h': 14400000, '1d': 86400000, '1w': 604800000 };
  const binanceHost = 'data-api.binance.vision';
  const settings = {
    searchCities: { ttl: DAY, retain: 30 * DAY, gap: 1000, label: '城市搜索' },
    weather: { ttl: 15 * MINUTE, retain: 2 * DAY, gap: 10_000, label: '天气' },
    releases: { ttl: HOUR, retain: 14 * DAY, gap: MINUTE, label: 'GitHub 发布' },
    cryptoQuotes: { ttl: 15_000, retain: 10 * MINUTE, gap: 5000, label: '数字货币报价' },
    cryptoCandles: { ttl: 15_000, retain: 10 * MINUTE, gap: 5000, label: '数字货币 K 线' },
    news: { ttl: 10 * MINUTE, retain: 2 * DAY, gap: 10_000, label: '科技资讯' },
  };
  const inflight = new Map(), attempts = new Map(), itemCache = new Map();
  let cache = readObject(CACHE_KEY), limits = readObject(LIMIT_KEY);

  function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
  function readObject(key) {
    try {
      const raw = localStorage.getItem(key);
      if (!raw || raw.length > MAX_CACHE_BYTES) return {};
      const value = JSON.parse(raw);
      return object(value) ? value : {};
    } catch (_) { return {}; }
  }
  function saveObject(key, value) {
    try { localStorage.setItem(key, JSON.stringify(value)); return true; } catch (_) { return false; }
  }
  function requireValue(condition, message = '数据服务返回格式异常，请稍后重试。') {
    if (!condition) throw new Error(message);
  }
  function finite(value) { return typeof value === 'number' && Number.isFinite(value); }
  function text(value, max = 500) { return typeof value === 'string' ? value.slice(0, max) : ''; }
  function decimal(value) {
    requireValue(typeof value === 'string' && /^[+-]?(?:\d+\.?\d*|\.\d+)$/.test(value));
    const number = Number(value); requireValue(finite(number)); return number;
  }
  function timestamp(value) { return Number.isSafeInteger(value) && value > 0 && value < 8640000000000000; }
  function validQuote(q) {
    return object(q) && cryptoSymbols.includes(q.symbol) && ['price', 'high', 'low'].every(k => finite(q[k]) && q[k] > 0)
      && q.high >= q.price && q.low <= q.price && finite(q.changePercent) && q.changePercent >= -100
      && ['volume', 'quoteVolume'].every(k => finite(q[k]) && q[k] >= 0)
      && timestamp(q.openTime) && timestamp(q.closeTime) && q.closeTime > q.openTime && q.closeTime <= Date.now() + MINUTE;
  }
  function validCandle(c) {
    return object(c) && timestamp(c.time) && timestamp(c.closeTime) && c.closeTime >= c.time && c.time <= Date.now() + MINUTE
      && ['open', 'high', 'low', 'close'].every(k => finite(c[k]) && c[k] > 0)
      && c.high >= Math.max(c.open, c.close) && c.low <= Math.min(c.open, c.close)
      && ['volume', 'quoteVolume'].every(k => finite(c[k]) && c[k] >= 0);
  }
  function safeUrl(value) {
    if (typeof value !== 'string' || value.length > 4096 || /[\u0000-\u001f\u007f]/.test(value)) return '';
    try {
      const url = new URL(value);
      return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password ? url.href : '';
    } catch (_) { return ''; }
  }
  function sspaiUrl(value) {
    const safe = safeUrl(value);
    if (!safe) return '';
    const url = new URL(safe);
    return url.protocol === 'https:' && url.hostname === 'sspai.com' && !url.port && /^\/post\/\d+\/?$/.test(url.pathname) && !url.search && !url.hash ? url.href : '';
  }
  function normalizeArgs(module, args) {
    requireValue(Object.hasOwn(settings, module), '不支持的看板模块。');
    requireValue(object(args), '看板参数格式不正确。');
    switch (module) {
      case 'searchCities': {
        const query = text(args.query ?? args.name, 101).trim();
        requireValue(query.length >= 2 && query.length <= 100 && !/[\u0000-\u001f\u007f]/.test(query), '请输入 2～100 个字符的城市名称。');
        return { query };
      }
      case 'weather':
        requireValue(finite(args.latitude) && Math.abs(args.latitude) <= 90 && finite(args.longitude) && Math.abs(args.longitude) <= 180, '城市坐标无效，请重新选择城市。');
        return { latitude: Math.round(args.latitude * 10000) / 10000, longitude: Math.round(args.longitude * 10000) / 10000 };
      case 'releases': {
        const repo = text(args.repo, 201).trim();
        requireValue(/^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?\/[a-zA-Z0-9_.-]{1,100}$/.test(repo) && !['.', '..'].includes(repo.split('/')[1]), '仓库格式应为 owner/repo，例如 flutter/flutter。');
        return { repo: repo.toLowerCase() };
      }
      case 'cryptoQuotes': return {};
      case 'cryptoCandles':
        requireValue(cryptoSymbols.includes(args.symbol) && Object.hasOwn(cryptoIntervals, args.interval), '请选择支持的交易对与 K 线周期。');
        requireValue(args.endTime === undefined || (timestamp(args.endTime) && args.endTime < Date.now()), '历史 K 线时间无效。');
        return { symbol: args.symbol, interval: args.interval, ...(args.endTime === undefined ? {} : { endTime: args.endTime }) };
      case 'news':
        requireValue(['sspai', 'top', 'new', 'show'].includes(args.feed), '请选择中文或 HN 资讯分类。');
        return { feed: args.feed };
    }
  }
  function validData(module, data) {
    if (!object(data)) return false;
    switch (module) {
      case 'searchCities': return Array.isArray(data.cities) && data.cities.length <= 10 && data.cities.every(c => object(c) && typeof c.name === 'string' && finite(c.latitude) && Math.abs(c.latitude) <= 90 && finite(c.longitude) && Math.abs(c.longitude) <= 180);
      case 'weather': return typeof data.timezone === 'string' && finite(data.utcOffsetSeconds) && Array.isArray(data.hours) && data.hours.length > 0 && data.hours.length <= 48 && data.hours.every(h => object(h) && typeof h.time === 'string' && Number.isFinite(Date.parse(h.time)) && (h.temperature === undefined || h.temperature === null || finite(h.temperature)) && ['feels', 'rain', 'wind', 'code'].every(k => h[k] === null || finite(h[k])));
      case 'releases': return typeof data.repo === 'string' && typeof data.noReleases === 'boolean' && Array.isArray(data.releases) && data.releases.length <= 5 && data.noReleases === (data.releases.length === 0) && data.releases.every(r => object(r) && typeof r.name === 'string' && typeof r.tag === 'string' && typeof r.body === 'string' && Number.isFinite(Date.parse(r.publishedAt)) && !!safeUrl(r.url));
      case 'cryptoQuotes': return Array.isArray(data.quotes) && data.quotes.length > 0 && data.quotes.length <= cryptoSymbols.length && new Set(data.quotes.map(q => q.symbol)).size === data.quotes.length && data.quotes.every(validQuote);
      case 'cryptoCandles': return cryptoSymbols.includes(data.symbol) && Object.hasOwn(cryptoIntervals, data.interval) && (data.endTime === undefined || (timestamp(data.endTime) && data.endTime < Date.now())) && Array.isArray(data.candles) && data.candles.length <= 500 && data.candles.every((c, i, rows) => validCandle(c) && (data.endTime === undefined || c.closeTime <= data.endTime) && c.closeTime - c.time + 1 === cryptoIntervals[data.interval] && (i === 0 || c.time === rows[i - 1].closeTime + 1));
      case 'news':
        if (data.feed === 'sspai') return Array.isArray(data.stories) && data.stories.length <= 10 && data.stories.every(s => object(s) && typeof s.title === 'string' && s.title.length > 0 && s.title.length <= 500 && s.source === '少数派' && finite(s.time) && s.time > 0 && s.time * 1000 <= Date.now() + DAY && !!sspaiUrl(s.url));
        return ['top', 'new', 'show'].includes(data.feed) && Array.isArray(data.stories) && data.stories.length <= 12 && data.stories.every(s => object(s) && Number.isSafeInteger(s.id) && s.id > 0 && typeof s.title === 'string' && finite(s.score) && finite(s.comments) && finite(s.time) && typeof s.by === 'string' && !!safeUrl(s.url) && s.discussion === `https://news.ycombinator.com/item?id=${s.id}`);
      default: return false;
    }
  }
  function cleanCache() {
    const now = Date.now();
    const entries = Object.entries(cache).filter(([key, entry]) => {
      const module = key.split(':', 1)[0], config = settings[module];
      return config && object(entry) && finite(entry.at) && entry.at <= now + 5 * MINUTE && now - entry.at <= config.retain && validData(module, entry.data) && (module !== 'news' || key === `news:${JSON.stringify({ feed: entry.data.feed })}`) && (module !== 'cryptoCandles' || key === `cryptoCandles:${JSON.stringify({ symbol: entry.data.symbol, interval: entry.data.interval, ...(entry.data.endTime === undefined ? {} : { endTime: entry.data.endTime }) })}`);
    }).sort((a, b) => b[1].at - a[1].at).slice(0, MAX_CACHE_ENTRIES);
    cache = Object.fromEntries(entries);
    while (JSON.stringify(cache).length > MAX_CACHE_BYTES && entries.length) {
      delete cache[entries.pop()[0]];
    }
    for (const [key, attempt] of attempts) if (now - attempt.at > HOUR) attempts.delete(key);
  }
  function putCache(key, data, warning) {
    const entry = { at: Date.now(), data, ...(warning ? { warning } : {}) };
    cache[key] = entry;
    cleanCache();
    saveObject(CACHE_KEY, cache);
    return entry;
  }
  function envelope(entry, cached, stale = false, warning) {
    return { data: entry.data, fetchedAt: new Date(entry.at).toISOString(), cached, stale, ...(warning || entry.warning ? { warning: warning || entry.warning } : {}) };
  }
  function ttl(module, entry) {
    if (module === 'news' && entry.warning) return MINUTE;
    return settings[module].ttl;
  }
  function cleanLimits() {
    const now = Date.now();
    limits = Object.fromEntries(Object.entries(limits).filter(([key, value]) => ['api.github.com', 'api.open-meteo.com', 'geocoding-api.open-meteo.com', 'hacker-news.firebaseio.com', 'sspai.com', binanceHost].includes(key) && finite(value) && value > now && value <= now + (key === binanceHost ? 3 : 2) * DAY));
    saveObject(LIMIT_KEY, limits);
  }
  function blockedMessage(host, until) {
    const minutes = Math.max(1, Math.ceil((until - Date.now()) / MINUTE));
    return `${host === 'api.github.com' ? 'GitHub' : host === binanceHost ? '币安行情' : '数据服务'}请求受限，请约 ${minutes} 分钟后重试。`;
  }
  function blockHost(host, response) {
    let until = Date.now() + (host === binanceHost && response.status === 418 && !response.headers.get('retry-after') ? 3 * DAY : MINUTE);
    const retry = response.headers.get('retry-after');
    if (retry) {
      const seconds = Number(retry);
      const target = finite(seconds) ? Date.now() + seconds * 1000 : Date.parse(retry);
      if (finite(target)) until = Math.max(until, target);
    }
    const reset = Number(response.headers.get('x-ratelimit-reset'));
    if (finite(reset) && reset > 0) until = Math.max(until, reset * 1000 + 1000);
    else if (!retry && host === 'api.github.com') until = Date.now() + 15 * MINUTE;
    limits[host] = Math.min(until, Date.now() + (host === binanceHost ? 3 : 1) * DAY);
    cleanLimits();
    return new Error(blockedMessage(host, limits[host]));
  }
  // Persist a conservative anonymous GitHub budget across refreshes/tabs.
  function reserveGithubRequest() {
    const key = 'shike.dashboard.github-budget.v1', now = Date.now();
    let recent = [];
    try { recent = JSON.parse(localStorage.getItem(key) || '[]'); } catch (_) { /* memory fallback below */ }
    if (!Array.isArray(recent)) recent = [];
    recent = recent.filter(t => finite(t) && t > now - HOUR && t <= now);
    githubBudget = [...new Set([...recent, ...githubBudget.filter(t => t > now - HOUR)])].sort((a, b) => a - b);
    if (githubBudget.length >= 40) {
      limits['api.github.com'] = githubBudget[0] + HOUR;
      cleanLimits();
      throw new Error(blockedMessage('api.github.com', limits['api.github.com']));
    }
    // Keep equal timestamps as distinct requests in this runtime.
    githubBudget.push(now + (githubBudget.includes(now) ? 0.001 * githubBudget.length : 0));
    try { localStorage.setItem(key, JSON.stringify(githubBudget)); } catch (_) { /* still protected in memory */ }
  }
  let githubBudget = [];
  async function jsonFetch(url, { xml = false, signal } = {}) {
    const host = new URL(url).host;
    const persisted = readObject(LIMIT_KEY);
    if (finite(persisted[host])) limits[host] = Math.max(limits[host] || 0, persisted[host]);
    cleanLimits();
    if (limits[host] > Date.now()) throw new Error(blockedMessage(host, limits[host]));
    if (host === 'api.github.com') reserveGithubRequest();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10_000);
    const cancel = () => { clearTimeout(timer); controller.abort(); };
    if (signal?.aborted) cancel();
    else signal?.addEventListener('abort', cancel, { once: true });
    try {
      const response = await fetch(url, { signal: controller.signal, credentials: 'omit', referrerPolicy: 'no-referrer', cache: 'no-store', headers: { Accept: host === 'api.github.com' ? 'application/vnd.github+json' : xml ? 'application/rss+xml, application/xml, text/xml' : 'application/json' } });
      if (response.status === 429 || (host === binanceHost && response.status === 418) || (host === 'api.github.com' && response.status === 403)) throw blockHost(host, response);
      if (!response.ok) {
        if (host === binanceHost && [403, 451].includes(response.status)) {
          limits[host] = Date.now() + 10 * MINUTE; cleanLimits();
          throw new Error('币安行情在当前网络或地区不可用，请稍后重试或打开官方来源。');
        }
        if (host === 'api.github.com' && response.status === 404) throw new Error('找不到公开仓库，请检查 owner/repo；私有仓库不受支持。');
        throw new Error(`数据服务暂时不可用（HTTP ${response.status}），请稍后重试。`);
      }
      if (host === 'api.github.com' && response.headers.get('x-ratelimit-remaining') === '0') blockHost(host, response);
      const type = (response.headers.get('content-type') || '').split(';', 1)[0].trim().toLowerCase();
      requireValue(xml
        ? ['application/rss+xml', 'application/xml', 'text/xml'].includes(type)
        : type === 'application/json' || type.endsWith('+json'),
      xml ? '资讯源没有返回有效 RSS，请稍后重试。' : '数据服务没有返回 JSON，请检查网络后重试。');
      const raw = await response.text();
      requireValue(raw.length <= 1_000_000, '数据响应过大，请稍后重试。');
      if (xml) return raw;
      try { return JSON.parse(raw); } catch (_) { throw new Error('数据服务返回了无效 JSON，请稍后重试。'); }
    } catch (error) {
      if (error?.name === 'AbortError') throw new Error('连接数据服务超时，请检查网络后重试。');
      if (error instanceof TypeError) throw new Error('无法连接数据服务，请检查网络或稍后重试。');
      throw error;
    } finally { clearTimeout(timer); signal?.removeEventListener('abort', cancel); }
  }
  async function mapLimit(values, concurrency, fn) {
    const result = new Array(values.length);
    let next = 0;
    await Promise.all(Array.from({ length: Math.min(concurrency, values.length) }, async () => {
      while (next < values.length) { const index = next++; result[index] = await fn(values[index], index); }
    }));
    return result;
  }
  async function loadSource(module, args) {
    switch (module) {
      case 'cryptoQuotes': {
        const url = new URL(`https://${binanceHost}/api/v3/ticker/24hr`);
        url.search = new URLSearchParams({ symbols: JSON.stringify(cryptoSymbols), type: 'FULL' });
        const rows = await jsonFetch(url.href);
        requireValue(Array.isArray(rows) && rows.length > 0 && rows.length <= cryptoSymbols.length);
        const quotes = rows.map(r => {
          requireValue(object(r));
          return { symbol: r.symbol, price: decimal(r.lastPrice), changePercent: decimal(r.priceChangePercent),
            high: decimal(r.highPrice), low: decimal(r.lowPrice), volume: decimal(r.volume), quoteVolume: decimal(r.quoteVolume),
            openTime: r.openTime, closeTime: r.closeTime };
        });
        quotes.sort((a, b) => cryptoSymbols.indexOf(a.symbol) - cryptoSymbols.indexOf(b.symbol));
        return { data: { quotes }, ...(quotes.length < cryptoSymbols.length ? { warning: '部分交易对暂未返回报价。' } : {}) };
      }
      case 'cryptoCandles': {
        const url = new URL(`https://${binanceHost}/api/v3/klines`);
        url.search = new URLSearchParams({ symbol: args.symbol, interval: args.interval, limit: '500', timeZone: '0' });
        if (args.endTime !== undefined) url.searchParams.set('endTime', String(args.endTime));
        const rows = await jsonFetch(url.href);
        requireValue(Array.isArray(rows) && rows.length <= 500);
        const candles = rows.map(r => {
          requireValue(Array.isArray(r) && r.length === 12);
          return { time: r[0], open: decimal(r[1]), high: decimal(r[2]), low: decimal(r[3]), close: decimal(r[4]),
            volume: decimal(r[5]), closeTime: r[6], quoteVolume: decimal(r[7]) };
        });
        return { data: { ...args, candles } };
      }
      case 'searchCities': {
        const url = new URL('https://geocoding-api.open-meteo.com/v1/search');
        url.search = new URLSearchParams({ name: args.query, count: '8', language: 'zh', format: 'json' });
        const raw = await jsonFetch(url.href);
        requireValue(object(raw) && raw.error !== true && (raw.results === undefined || Array.isArray(raw.results)));
        const cities = (raw.results || []).slice(0, 8).map(c => {
          requireValue(object(c) && typeof c.name === 'string' && finite(c.latitude) && finite(c.longitude));
          return { name: text(c.name, 150), latitude: c.latitude, longitude: c.longitude, country: text(c.country, 100), admin1: text(c.admin1, 100), timezone: text(c.timezone, 100) };
        });
        return { data: { cities } };
      }
      case 'weather': {
        const url = new URL('https://api.open-meteo.com/v1/forecast');
        url.search = new URLSearchParams({ latitude: String(args.latitude), longitude: String(args.longitude), hourly: 'temperature_2m,apparent_temperature,precipitation_probability,wind_speed_10m,weather_code', timezone: 'auto', forecast_hours: '24', temperature_unit: 'celsius', wind_speed_unit: 'kmh' });
        const raw = await jsonFetch(url.href), h = raw?.hourly;
        requireValue(object(raw) && object(h) && Array.isArray(h.time) && h.time.length > 0 && h.time.length <= 48);
        const columns = ['temperature_2m', 'apparent_temperature', 'precipitation_probability', 'wind_speed_10m', 'weather_code'];
        requireValue(columns.every(k => Array.isArray(h[k]) && h[k].length === h.time.length));
        const hours = h.time.map((time, i) => ({ time, temperature: h.temperature_2m[i], feels: h.apparent_temperature[i], rain: h.precipitation_probability[i], wind: h.wind_speed_10m[i], code: h.weather_code[i] }));
        requireValue(hours.some(row => finite(row.feels)), '天气服务暂未提供有效预报，请稍后重试。');
        return { data: { hours, timezone: raw.timezone, utcOffsetSeconds: raw.utc_offset_seconds } };
      }
      case 'releases': {
        const raw = await jsonFetch(`https://api.github.com/repos/${args.repo}/releases?per_page=1`);
        requireValue(Array.isArray(raw));
        const releases = raw.slice(0, 1).map(r => {
          requireValue(object(r) && typeof r.tag_name === 'string' && typeof r.published_at === 'string' && Number.isFinite(Date.parse(r.published_at)) && !!safeUrl(r.html_url));
          return { name: text(r.name, 240) || text(r.tag_name, 240), tag: text(r.tag_name, 240), publishedAt: r.published_at, url: safeUrl(r.html_url), body: text(r.body, 6000), ...(r.prerelease === true ? { prerelease: true } : {}) };
        });
        return { data: { repo: args.repo, releases, noReleases: releases.length === 0 } };
      }
      case 'news': {
        if (args.feed === 'sspai') {
          const xml = await jsonFetch('https://sspai.com/feed', { xml: true });
          requireValue(!/<!DOCTYPE|<!ENTITY/i.test(xml), '资讯源 XML 格式不受支持。');
          const document = new DOMParser().parseFromString(xml, 'application/xml');
          requireValue(!document.querySelector('parsererror') && !!document.querySelector('rss > channel'), '资讯源 RSS 格式异常，请稍后重试。');
          const items = [...document.querySelectorAll('channel > item')].slice(0, 30);
          const seen = new Set(), stories = [];
          let failures = 0;
          for (const item of items) {
            const field = name => item.querySelector(name)?.textContent?.trim() || '';
            const title = text(field('title'), 500).replace(/\s+/g, ' ');
            const url = sspaiUrl(field('link'));
            const time = Date.parse(field('pubDate')) / 1000;
            if (!title || !url || !finite(time) || time <= 0 || time * 1000 > Date.now() + DAY) { failures++; continue; }
            if (seen.has(url)) continue;
            seen.add(url);
            stories.push({ title, url, time, source: '少数派' });
            if (stories.length === 10) break;
          }
          requireValue(items.length === 0 || stories.length > 0, '少数派内容暂时无法读取，请稍后重试。');
          return { data: { feed: args.feed, stories }, ...(failures ? { warning: `${failures} 条资讯格式异常，当前显示已验证内容。` } : {}) };
        }
        const root = 'https://hacker-news.firebaseio.com/v0';
        const ids = await jsonFetch(`${root}/${args.feed}stories.json`);
        requireValue(Array.isArray(ids) && ids.every(id => Number.isSafeInteger(id) && id > 0));
        let failures = 0;
        const stories = await mapLimit([...new Set(ids)].slice(0, 12), 4, async id => {
          try {
            const cached = itemCache.get(id);
            let r;
            if (cached && Date.now() - cached.at < 10 * MINUTE) r = cached.data;
            else {
              r = await jsonFetch(`${root}/item/${id}.json`);
              if (object(r)) itemCache.set(id, { at: Date.now(), data: r });
              while (itemCache.size > 48) itemCache.delete(itemCache.keys().next().value);
            }
            if (r === null || r?.deleted || r?.dead) return null;
            requireValue(object(r) && r.id === id && ['story', 'job'].includes(r.type) && typeof r.title === 'string' && finite(r.time));
            const discussion = `https://news.ycombinator.com/item?id=${id}`;
            return { id, title: text(r.title, 500), score: finite(r.score) ? Math.max(0, r.score) : 0, comments: finite(r.descendants) ? Math.max(0, r.descendants) : 0, url: safeUrl(r.url) || discussion, discussion, time: r.time, by: text(r.by, 100) };
          } catch (_) { failures++; return null; }
        });
        const visible = stories.filter(Boolean);
        requireValue(!failures || visible.length > 0, 'Hacker News 内容暂时无法读取，请稍后重试。');
        return { data: { feed: args.feed, stories: visible }, ...(failures ? { warning: `${failures} 条资讯暂时无法读取，当前显示已获取内容。` } : {}) };
      }
    }
  }
  async function requestData(module, rawArgs, refresh) {
    let args;
    try { args = typeof rawArgs === 'string' ? JSON.parse(rawArgs) : rawArgs; }
    catch (_) { throw new Error('看板参数不是有效 JSON。'); }
    args = normalizeArgs(module, args);
    const key = `${module}:${JSON.stringify(args)}`, now = Date.now();
    cleanCache();
    const old = cache[key];
    if (!refresh && old && now - old.at < ttl(module, old)) return envelope(old, true);
    if (inflight.has(key)) return inflight.get(key);
    const previous = attempts.get(key);
    if (previous && now - previous.at < settings[module].gap) {
      if (old) return envelope(old, true, now - old.at >= ttl(module, old) || !!previous.error, previous.error ? `${previous.error} 正在显示上次保存的数据。` : (refresh ? '刷新过于频繁，正在使用最近获取的数据。' : undefined));
      throw new Error(previous.error || '请求过于频繁，请稍后重试。');
    }
    attempts.set(key, { at: now });
    const pending = (async () => {
      try {
        const { data, warning } = await loadSource(module, args);
        requireValue(validData(module, data));
        return envelope(putCache(key, data, warning), false);
      } catch (error) {
        const message = error instanceof Error ? error.message : `${settings[module].label}加载失败，请稍后重试。`;
        attempts.set(key, { at: Date.now(), error: message });
        if (old) return envelope(old, true, true, `${message} 正在显示上次保存的数据。`);
        throw new Error(message);
      } finally { inflight.delete(key); }
    })();
    inflight.set(key, pending);
    return pending;
  }
  // Spot protocol: buffer diff events before REST, then bridge lastUpdateId with
  // U/u. Futures uses a different pu chain; never apply that rule to Spot data.
  // https://github.com/binance/binance-spot-api-docs/blob/master/web-socket-streams.md#how-to-manage-a-local-order-book-correctly
  const bookSnapshotLimit = 1000;
  function bookLevels(rows, { zero = false, bid } = {}) {
    requireValue(Array.isArray(rows) && rows.length <= (zero ? 10000 : bookSnapshotLimit));
    let digits = 0;
    const levels = rows.map((row, index) => {
      requireValue(Array.isArray(row) && row.length === 2);
      const price = decimal(row[0]), quantity = decimal(row[1]);
      requireValue(price > 0 && (zero ? quantity >= 0 : quantity > 0) && finite(price * quantity));
      if (bid !== undefined && index) requireValue(bid ? price < decimal(rows[index-1][0]) : price > decimal(rows[index-1][0]));
      digits = Math.max(digits, (row[0].replace(/0+$/, '').split('.')[1] || '').length);
      return [price, quantity];
    });
    requireValue(digits <= 8);
    return { levels, digits };
  }
  function maintainSpotBook(symbol, emit, current) {
    let local = null, buffer = [], bufferedLevels = 0, pending = null, timer = null;
    let serial = 0, closed = false, failures = 0, lastAttempt = -Infinity, status;
    const valid = () => !closed && current();
    const state = value => {
      if (valid() && status !== value) { status = value; emit({type:'depthStatus',symbol,status:value}); }
    };
    function cancelRequest() {
      serial++;
      pending?.abort(); pending = null;
      clearTimeout(timer); timer = null;
    }
    function visibleBook() {
      requireValue(local.bids.size <= 5000 && local.asks.size <= 5000);
      const bids = [...local.bids].sort((a,b) => b[0]-a[0]).slice(0,20);
      const asks = [...local.asks].sort((a,b) => a[0]-b[0]).slice(0,20);
      // Updates outside the initial snapshot cannot describe all intervening
      // levels. Rebootstrap before such unknown ranges could enter the UI.
      if (local.bidFloor !== null) requireValue(bids.length === 20 && bids.at(-1)[0] >= local.bidFloor);
      if (local.askCeiling !== null) requireValue(asks.length === 20 && asks.at(-1)[0] <= local.askCeiling);
      requireValue(!bids.length || !asks.length || bids[0][0] < asks[0][0]);
      const side = rows => rows.map(([price,quantity]) => ({price,quantity}));
      return {lastUpdateId:local.id,bids:side(bids),asks:side(asks),priceDecimals:local.digits};
    }
    function apply(event) {
      if (event.u <= local.id) return false;
      requireValue(event.U <= local.id + 1); // A gap invalidates the WHOLE copy.
      for (const [side, rows] of [[local.bids,event.b], [local.asks,event.a]]) {
        for (const [price,quantity] of rows) {
          if (quantity === 0) side.delete(price); // Removing an absent price is harmless.
          else side.set(price,quantity); // Absolute quantity, never an increment.
        }
      }
      local.id = event.u; local.digits = Math.max(local.digits,event.digits);
      visibleBook(); // Validate both sides atomically before any UI emission.
      return true;
    }
    function publish() {
      emit({type:'depth',symbol,eventTime:Date.now(),book:visibleBook()});
      failures = 0; state('live');
    }
    function schedule(delay = 0) {
      if (!valid() || pending || timer !== null || !buffer.length) return;
      const wait = Math.max(delay, lastAttempt + 1000 - Date.now(), (limits[binanceHost] || 0) - Date.now());
      if (wait > 0) timer = setTimeout(() => { timer = null; snapshot(); }, wait);
      else snapshot();
    }
    function reset(event, retrying = false) {
      cancelRequest(); local = null;
      buffer = event ? [event] : [];
      bufferedLevels = event ? event.b.length + event.a.length : 0;
      state(retrying ? 'retrying' : 'syncing');
      schedule();
    }
    async function snapshot() {
      if (!valid() || pending || !buffer.length) return;
      const token = serial, controller = new AbortController();
      pending = controller; lastAttempt = Date.now();
      try {
        const value = await jsonFetch(`https://${binanceHost}/api/v3/depth?symbol=${symbol}&limit=${bookSnapshotLimit}`, {signal:controller.signal});
        if (!valid() || token !== serial) return;
        requireValue(object(value) && Number.isSafeInteger(value.lastUpdateId) && value.lastUpdateId >= 0);
        const bids = bookLevels(value.bids,{bid:true}), asks = bookLevels(value.asks,{bid:false});
        requireValue(value.lastUpdateId >= buffer[0].U); // Snapshot older than buffered stream: refetch.
        local = {id:value.lastUpdateId,bids:new Map(bids.levels),asks:new Map(asks.levels),digits:Math.max(bids.digits,asks.digits),
          bidFloor:bids.levels.length === bookSnapshotLimit ? bids.levels.at(-1)[0] : null,
          askCeiling:asks.levels.length === bookSnapshotLimit ? asks.levels.at(-1)[0] : null};
        visibleBook();
        let advanced = false;
        for (const event of buffer) advanced = apply(event) || advanced;
        buffer = []; bufferedLevels = 0;
        // A snapshot alone does not prove the stream was bridged. Wait for an
        // applicable diff before calling the locally maintained copy live.
        if (advanced) publish();
      } catch (_) {
        if (!valid() || token !== serial) return;
        local = null; state('retrying');
        const delay = Math.min(30000, 1000 * 2 ** Math.min(failures++,5));
        pending = null; schedule(delay);
      } finally { if (token === serial && pending === controller) pending = null; }
    }
    state('syncing');
    return {
      push(data) {
        if (!valid()) return false;
        let event;
        try {
          requireValue(object(data) && data.e === 'depthUpdate' && data.s === symbol
            && timestamp(data.E) && data.E <= Date.now() + MINUTE && Date.now() - data.E < MINUTE
            && Number.isSafeInteger(data.U) && data.U >= 0 && Number.isSafeInteger(data.u) && data.u >= data.U);
          const bids = bookLevels(data.b,{zero:true}), asks = bookLevels(data.a,{zero:true});
          event = {U:data.U,u:data.u,b:bids.levels,a:asks.levels,digits:Math.max(bids.digits,asks.digits)};
        } catch (_) { reset(null,true); return false; }
        if (local) {
          try { if (apply(event)) publish(); }
          catch (_) { reset(event); }
        } else {
          buffer.push(event); bufferedLevels += event.b.length + event.a.length;
          if (buffer.length > 1000 || bufferedLevels > 20000) reset(event);
          else schedule();
        }
        return true;
      },
      stop() { closed = true; cancelRequest(); local = null; buffer = []; },
    };
  }
  // Public market-only streams. Browsers handle WebSocket protocol ping/pong.
  const cryptoSessions = new Map();
  let cryptoSessionId = 0;
  function subscribeCrypto(raw, callback) {
    const args = normalizeArgs('cryptoCandles', JSON.parse(raw));
    requireValue(typeof callback === 'function');
    const id = String(++cryptoSessionId);
    let socket, retryTimer, watchdog, rotation, stopped = false, generation = 0, failures = 0;
    let opened = false, localDepth;
    const selected = args.symbol.toLowerCase();
    const streams = [...cryptoSymbols.map(s => `${s.toLowerCase()}@ticker`), `${selected}@depth`, `${selected}@kline_${args.interval}`];
    const emit = event => { if (!stopped) callback(JSON.stringify(event)); };
    function clear() {
      generation++;
      localDepth?.stop(); localDepth = null;
      clearTimeout(retryTimer); clearTimeout(watchdog); clearTimeout(rotation);
      if (socket) { socket.onopen = socket.onmessage = socket.onerror = socket.onclose = null; socket.close(); socket = null; }
    }
    function retry() {
      if (stopped) return;
      clear();
      const delay = Math.min(30000, 1000 * 2 ** Math.min(failures++, 5));
      emit({ type:'status', status:'reconnecting', message:'推送中断，正在重连；当前价格可能已过时。' });
      retryTimer = setTimeout(connect, delay);
    }
    function connect() {
      if (stopped) return;
      if (globalThis.document?.hidden) { emit({type:'status',status:'paused'}); return; }
      clear();
      const epoch = generation, received = new Map(), times = new Map();
      let live = false;
      emit({type:'status',status:'connecting'});
      try { socket = new WebSocket(`wss://data-stream.binance.vision/stream?streams=${streams.join('/')}`); }
      catch (_) { retry(); return; }
      const valid = () => !stopped && epoch === generation;
      localDepth = maintainSpotBook(args.symbol,emit,valid);
      function check() {
        if (!valid()) return;
        const now = Date.now();
        if ([`${selected}@ticker`, `${selected}@kline_${args.interval}`, `${selected}@depth`].some(key => now - (received.get(key) || start) > 15000)) { retry(); return; }
        watchdog = setTimeout(check, 5000);
      }
      const start = Date.now();
      watchdog = setTimeout(check, 5000);
      socket.onopen = () => {
        if (!valid()) return;
        emit({type:'status',status:'connected',resync:opened}); opened = true;
        rotation = setTimeout(retry, 23 * HOUR + 50 * MINUTE);
      };
      socket.onmessage = message => {
        if (!valid()) return;
        try {
          const envelope = JSON.parse(message.data), data = envelope.data;
          if (data?.e === 'serverShutdown' || envelope.e === 'serverShutdown') { retry(); return; }
          if (envelope.stream === `${selected}@depth`) {
            if (localDepth.push(data)) received.set(envelope.stream,Date.now());
            return;
          }
          requireValue(streams.includes(envelope.stream) && object(data) && timestamp(data.E) && data.E <= Date.now() + MINUTE && Date.now() - data.E < MINUTE);
          if (data.E <= (times.get(envelope.stream) || 0)) return;
          let event;
          if (data.e === '24hrTicker' && envelope.stream === `${data.s?.toLowerCase()}@ticker`) {
            const quote = { symbol:data.s, price:decimal(data.c), changePercent:decimal(data.P), high:decimal(data.h), low:decimal(data.l), volume:decimal(data.v), quoteVolume:decimal(data.q), openTime:data.O, closeTime:data.C };
            requireValue(validQuote(quote));
            event = {type:'quote',quote,eventTime:data.E};
          } else if (data.e === 'kline' && data.s === args.symbol && data.k?.s === args.symbol && data.k.i === args.interval && envelope.stream === `${selected}@kline_${args.interval}`) {
            const k = data.k, candle = {time:k.t,closeTime:k.T,open:decimal(k.o),high:decimal(k.h),low:decimal(k.l),close:decimal(k.c),volume:decimal(k.v),quoteVolume:decimal(k.q)};
            requireValue(validCandle(candle) && candle.closeTime - candle.time + 1 === cryptoIntervals[args.interval] && typeof k.x === 'boolean');
            event = {type:'candle',candle,symbol:args.symbol,interval:args.interval,eventTime:data.E,closed:k.x};
          } else return;
          times.set(envelope.stream, data.E); received.set(envelope.stream, Date.now());
          emit(event);
          if (!live && received.has(`${selected}@ticker`) && received.has(`${selected}@kline_${args.interval}`)) {
            live = true; failures = 0; emit({type:'status',status:'live'});
          }
        } catch (_) { /* Invalid/foreign frames never mutate market state. Watchdog recovers a broken stream. */ }
      };
      socket.onclose = socket.onerror = () => { if (valid()) retry(); };
    }
    const visibility = () => {
      if (globalThis.document?.hidden) { clear(); emit({type:'status',status:'paused'}); }
      else connect();
    };
    globalThis.document?.addEventListener('visibilitychange', visibility);
    cryptoSessions.set(id, () => {
      stopped = true; clear(); globalThis.document?.removeEventListener('visibilitychange', visibility);
    });
    connect();
    return id;
  }
  function unsubscribeCrypto(id) { cryptoSessions.get(id)?.(); cryptoSessions.delete(id); }
  cleanCache();
  cleanLimits();
  globalThis.timeNestDashboard = Object.freeze({
    subscribeCrypto, unsubscribeCrypto,
    async request(module, rawArgs, refresh = false) {
      return JSON.stringify(await requestData(module, rawArgs, refresh === true));
    },
    readPreferences() {
      try {
        const raw = localStorage.getItem(PREF_KEY);
        return raw && raw.length <= 20_000 && object(JSON.parse(raw)) ? raw : null;
      } catch (_) { return null; }
    },
    writePreferences(raw) {
      try {
        if (typeof raw !== 'string' || raw.length > 20_000 || !object(JSON.parse(raw))) return false;
        localStorage.setItem(PREF_KEY, raw);
        return true;
      } catch (_) { return false; }
    },
    openUrl(raw) {
      const url = safeUrl(raw);
      if (!url) return false;
      try { globalThis.open(url, '_blank', 'noopener,noreferrer'); return true; } catch (_) { return false; }
    },
  });
})();
