// Public read-only APIs. No credentials, location permission or tracking.
// Provider documentation: open-meteo.com/en/docs, frankfurter.dev,
// github.com/HackerNews/API,
// docs.github.com/en/rest/releases/releases, sspai.com/post/24194 (official RSS).
(() => {
  'use strict';
  const MINUTE = 60_000, HOUR = 60 * MINUTE, DAY = 24 * HOUR;
  const CACHE_KEY = 'shike.dashboard.cache.v1';
  const LIMIT_KEY = 'shike.dashboard.limits.v1';
  const PREF_KEY = 'shike.dashboard.preferences.v1';
  const MAX_CACHE_ENTRIES = 80, MAX_CACHE_BYTES = 900_000;
  const settings = {
    searchCities: { ttl: DAY, retain: 30 * DAY, gap: 1000, label: '城市搜索' },
    weather: { ttl: 15 * MINUTE, retain: 2 * DAY, gap: 10_000, label: '天气' },
    releases: { ttl: HOUR, retain: 14 * DAY, gap: MINUTE, label: 'GitHub 发布' },
    fx: { ttl: 6 * HOUR, retain: 14 * DAY, gap: 10_000, label: '汇率' },
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
  function validDate(value) {
    return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
      Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
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
      case 'fx': {
        const base = text(args.base, 4).toUpperCase(), quote = text(args.quote, 4).toUpperCase();
        requireValue(/^[A-Z]{3}$/.test(base) && /^[A-Z]{3}$/.test(quote), '请输入三位货币代码，例如 USD、CNY。');
        return { base, quote };
      }
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
      case 'fx': return /^[A-Z]{3}$/.test(data.base) && /^[A-Z]{3}$/.test(data.quote) && finite(data.rate) && data.rate > 0 && validDate(data.date) && Array.isArray(data.history) && data.history.length > 0 && data.history.length <= 40 && data.history.every(d => object(d) && validDate(d.date) && finite(d.rate) && d.rate > 0);
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
      return config && object(entry) && finite(entry.at) && entry.at <= now + 5 * MINUTE && now - entry.at <= config.retain && validData(module, entry.data) && (module !== 'news' || key === `news:${JSON.stringify({ feed: entry.data.feed })}`);
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
    limits = Object.fromEntries(Object.entries(limits).filter(([key, value]) => ['api.github.com', 'api.open-meteo.com', 'geocoding-api.open-meteo.com', 'api.frankfurter.dev', 'hacker-news.firebaseio.com', 'sspai.com'].includes(key) && finite(value) && value > now && value <= now + 2 * DAY));
    saveObject(LIMIT_KEY, limits);
  }
  function blockedMessage(host, until) {
    const minutes = Math.max(1, Math.ceil((until - Date.now()) / MINUTE));
    return `${host === 'api.github.com' ? 'GitHub' : '数据服务'}请求受限，请约 ${minutes} 分钟后重试。`;
  }
  function blockHost(host, response) {
    let until = Date.now() + MINUTE;
    const retry = response.headers.get('retry-after');
    if (retry) {
      const seconds = Number(retry);
      const target = finite(seconds) ? Date.now() + seconds * 1000 : Date.parse(retry);
      if (finite(target)) until = Math.max(until, target);
    }
    const reset = Number(response.headers.get('x-ratelimit-reset'));
    if (finite(reset) && reset > 0) until = Math.max(until, reset * 1000 + 1000);
    else if (!retry && host === 'api.github.com') until = Date.now() + 15 * MINUTE;
    limits[host] = Math.min(until, Date.now() + DAY);
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
  async function jsonFetch(url, { xml = false } = {}) {
    const host = new URL(url).host;
    const persisted = readObject(LIMIT_KEY);
    if (finite(persisted[host])) limits[host] = Math.max(limits[host] || 0, persisted[host]);
    cleanLimits();
    if (limits[host] > Date.now()) throw new Error(blockedMessage(host, limits[host]));
    if (host === 'api.github.com') reserveGithubRequest();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10_000);
    try {
      const response = await fetch(url, { signal: controller.signal, credentials: 'omit', referrerPolicy: 'no-referrer', cache: 'no-store', headers: { Accept: host === 'api.github.com' ? 'application/vnd.github+json' : xml ? 'application/rss+xml, application/xml, text/xml' : 'application/json' } });
      if (response.status === 429 || (host === 'api.github.com' && response.status === 403)) throw blockHost(host, response);
      if (!response.ok) {
        if (host === 'api.github.com' && response.status === 404) throw new Error('找不到公开仓库，请检查 owner/repo；私有仓库不受支持。');
        if (host === 'api.frankfurter.dev' && [400, 404, 422].includes(response.status)) throw new Error('暂不支持该货币或货币对，请换一组货币。');
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
    } finally { clearTimeout(timer); }
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
      case 'fx': {
        const end = new Date(Date.now()).toISOString().slice(0, 10);
        const start = new Date(Date.now() - 29 * DAY).toISOString().slice(0, 10);
        const url = new URL('https://api.frankfurter.dev/v2/rates');
        url.search = new URLSearchParams({ base: args.base, quotes: args.quote, from: start, to: end });
        const [latest, historyRaw] = await Promise.all([
          jsonFetch(`https://api.frankfurter.dev/v2/rate/${args.base}/${args.quote}`), jsonFetch(url.href),
        ]);
        const rateValid = r => object(r) && r.base === args.base && r.quote === args.quote && validDate(r.date) && finite(r.rate) && r.rate > 0;
        requireValue(rateValid(latest) && Array.isArray(historyRaw) && historyRaw.length > 0 && historyRaw.every(rateValid));
        const unique = new Map(historyRaw.filter(r => r.date >= start && r.date <= end).map(r => [r.date, { date: r.date, rate: r.rate }]));
        const history = [...unique.values()].sort((a, b) => a.date.localeCompare(b.date));
        requireValue(history.length > 0, '该货币对近 30 天没有可用日频数据。');
        return { data: { base: args.base, quote: args.quote, rate: latest.rate, date: latest.date, history } };
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
  cleanCache();
  cleanLimits();
  globalThis.timeNestDashboard = Object.freeze({
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
