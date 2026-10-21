import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../web/network_tools.js', import.meta.url), 'utf8');
const PROBE = 'time-nest-network-probe-v1\n';
const DOWN = 'https://speed.cloudflare.com/__down';
const UP = 'https://speed.cloudflare.com/__up';
const DNS = 'https://cloudflare-dns.com/dns-query';
const HISTORY_KEY = 'shike.network.history.v1';
const START = Date.parse('2026-10-20T12:00:00Z');
const MiB = 1024 * 1024;
const settle = async () => { for (let i = 0; i < 8; i++) await new Promise(setImmediate); };
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
class Events {
  listeners = new Map();
  addEventListener(type, callback) {
    if (!this.listeners.has(type)) this.listeners.set(type, new Set());
    this.listeners.get(type).add(callback);
  }
  emit(type) { for (const callback of this.listeners.get(type) || []) callback(); }
}
function response(bytes, { status = 200, headers = {} } = {}) {
  return new Response(bytes, { status, headers: { 'content-type': 'application/octet-stream', ...headers } });
}
function dnsResponse(value, options = {}) {
  return response(JSON.stringify(value), { ...options, headers: { 'content-type': 'application/dns-json', ...options.headers } });
}
function normalResponse(url, init) {
  const parsed = new URL(url);
  if (parsed.origin + parsed.pathname === DOWN) return response(new Uint8Array(Number(parsed.searchParams.get('bytes'))));
  if (url === UP && init.method === 'POST') return response('ok');
  if (parsed.origin + parsed.pathname === DNS) return dnsResponse({
    Status: 0, TC: false, AD: false,
    Question: [{ name: `${parsed.searchParams.get('name')}.`, type: { A: 1, NS: 2, CNAME: 5, MX: 15, TXT: 16, AAAA: 28 }[parsed.searchParams.get('type')] }],
    Answer: [],
  });
  if (parsed.origin === 'https://clock.test' && parsed.pathname.endsWith('/network-probe.txt')) return response(PROBE, { headers: { 'content-type': 'text/plain' } });
  assert.fail(`Unexpected request, never sent to the network: ${url}`);
}
function harness(options = {}) {
  let now = 0, nextTimer = 0;
  const timers = new Map(), requests = [], events = [], opened = [], randomCalls = [];
  const storage = options.storage || new Map(), storageOps = [];
  const localStorage = {
    getItem(key) {
      storageOps.push(['get', key]);
      if (options.storageReadFails) throw new DOMException('Storage blocked', 'SecurityError');
      return storage.get(key) ?? null;
    },
    setItem(key, value) {
      storageOps.push(['set', key, value]);
      if (options.storageWriteFails) throw new DOMException('Quota exceeded', 'QuotaExceededError');
      storage.set(key, value);
    },
    removeItem(key) {
      storageOps.push(['remove', key]);
      if (options.storageRemoveFails) throw new DOMException('Storage blocked', 'SecurityError');
      storage.delete(key);
    },
  };
  const document = new Events(), window = new Events();
  document.baseURI = options.baseURI || 'https://clock.test/time_nest/';
  document.hidden = !!options.hidden;
  const state = {
    elapse(ms) { now += ms; },
    now: () => now,
    requests, events, opened, randomCalls, timers, document, storage, storageOps,
  };
  const navigator = options.navigator || {};
  const context = {
    URL, URLSearchParams, AbortController, DOMException, TextDecoder, TextEncoder, Uint8Array,
    Response, ReadableStream, document, navigator, localStorage,
    location: { origin: 'https://clock.test' },
    Date: class extends Date {
      constructor(...args) { super(...(args.length ? args : [START + now])); }
      static now() { return START + now; }
    },
    performance: { now: () => now },
    addEventListener: window.addEventListener.bind(window),
    setTimeout(fn, delay) { const id = ++nextTimer; timers.set(id, { fn, at: now + delay, delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    open(...args) { opened.push(args); },
    crypto: options.noCrypto ? undefined : {
      getRandomValues(bytes) {
        assert.ok(bytes.byteLength <= 65536, 'Web Crypto per-call limit');
        randomCalls.push(bytes.byteLength);
        for (let i = 0; i < bytes.length; i++) bytes[i] = (i + randomCalls.length) % 251;
        return bytes;
      },
    },
    async fetch(url, init) {
      const call = { url: String(url), init, index: requests.length };
      requests.push(call);
      if (options.fetch) return options.fetch(call, state);
      now += options.durations?.[call.index] ?? 50;
      return normalResponse(call.url, init);
    },
  };
  if ('secure' in options) context.isSecureContext = options.secure;
  if (options.storageGetterFails) Object.defineProperty(context, 'localStorage', { get() { throw new DOMException('Storage blocked', 'SecurityError'); } });
  vm.runInNewContext(source, context, { filename: 'network_tools.js' });
  return Object.assign(state, {
    api: context.timeNestNetwork,
    history: () => JSON.parse(context.timeNestNetwork.history()),
    start(kind = 'speed', args = {}, sink = events) {
      return context.timeNestNetwork.start(kind, typeof args === 'string' ? args : JSON.stringify(args), raw => sink.push(JSON.parse(raw)));
    },
    async advance(ms) {
      const target = now + ms;
      while (true) {
        const due = [...timers].filter(([, timer]) => timer.at <= target).sort((a, b) => a[1].at - b[1].at)[0];
        if (!due) break;
        const [id, timer] = due;
        now = timer.at; timers.delete(id); timer.fn();
        await settle();
      }
      now = target;
      await settle();
    },
    hide() { document.hidden = true; document.emit('visibilitychange'); },
    show() { document.hidden = false; document.emit('visibilitychange'); },
    pagehide() { window.emit('pagehide'); },
    result: () => events.at(-1),
  });
}
function assertPrivateRequest(call) {
  assert.equal(call.init.credentials, 'omit');
  assert.equal(call.init.referrerPolicy, 'no-referrer');
  assert.equal(call.init.cache, 'no-store');
  assert.equal(call.init.redirect, 'error');
  assert.equal(call.init.mode, 'cors');
  assert.ok(call.init.signal instanceof AbortSignal);
}
function assertTerminal(h, status) {
  assert.equal(h.result()?.status, status, JSON.stringify(h.result()));
  assert.equal(h.events.filter(event => event.status !== 'running').length, 1);
  assert.equal(h.timers.size, 0, 'completed operations release every timer');
}
function abortablePending(call) {
  return new Promise((resolve, reject) => {
    call.init.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true });
  });
}

test('loading the bridge and inspecting the environment cause zero requests and zero timers', async () => {
  const h = harness();
  assert.deepEqual(Object.keys(h.api).sort(), ['cancel', 'clearHistory', 'environment', 'history', 'openUrl', 'start']);
  assert.ok(Object.isFrozen(h.api));
  assert.deepEqual(JSON.parse(h.api.environment()), {
    online: null, secure: null, effectiveType: null, estimatedDownlinkMbps: null, estimatedRttMs: null, saveData: null,
  });
  h.api.environment(); h.hide(); h.show(); h.pagehide();
  await h.advance(300000);
  assert.equal(h.requests.length, 0);
  assert.equal(h.events.length, 0);
  assert.equal(h.timers.size, 0);
});

test('environment reports browser estimates as estimates without inferring Wi-Fi, ISP, IP, or measured speed', () => {
  const h = harness({ secure: true, navigator: { onLine: false, connection: {
    effectiveType: '4g', downlink: 12.5, rtt: 75, saveData: true, type: 'wifi', ip: '192.0.2.1', isp: 'not supported',
  } } });
  assert.deepEqual(JSON.parse(h.api.environment()), {
    online: false, secure: true, effectiveType: '4g', estimatedDownlinkMbps: 12.5, estimatedRttMs: 75, saveData: true,
  });
  assert.equal(h.requests.length, 0);
});

test('invalid or unsupported browser estimates remain unknown instead of being fabricated', () => {
  for (const value of [-1, NaN, Infinity, '100', undefined, null]) {
    const h = harness({ secure: false, navigator: { onLine: 'yes', connection: {
      effectiveType: 'wifi', downlink: value, rtt: value, saveData: 'false',
    } } });
    assert.deepEqual(JSON.parse(h.api.environment()), {
      online: null, secure: false, effectiveType: null, estimatedDownlinkMbps: null, estimatedRttMs: null, saveData: null,
    });
  }
});

test('only exact allowlisted HTTPS source and policy links can open', () => {
  const h = harness();
  const allowed = [
    'https://github.com/cloudflare/speedtest',
    'https://www.cloudflare.com/privacypolicy/',
    'https://www.cloudflare.com/website-terms/',
    'https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/',
  ];
  for (const url of allowed) h.api.openUrl(url);
  for (const url of ['https://speed.cloudflare.com/', 'https://github.com/cloudflare/speedtest/issues', 'javascript:alert(1)', 'https://attacker.test/', 'https://speed.cloudflare.com.evil.test/',
    'https://speed.cloudflare.com/?redirect=evil', 'http://speed.cloudflare.com/', '//speed.cloudflare.com/', null, {}]) h.api.openUrl(url);
  assert.deepEqual(h.opened, allowed.map(url => [url, '_blank', 'noopener,noreferrer']));
  assert.equal(h.requests.length, 0);
});

test('a speed run uses only documented fixed endpoints and bounded byte amounts with privacy-preserving requests', async () => {
  const h = harness({ durations: [900, 10, 20, 30, 40, 50, 100, 200, 400, 100, 200] });
  const id = h.start('speed', { url: 'https://attacker.test/upload', bytes: 1000000000, payload: 'private text', repeats: 100 });
  assert.match(id, /^network-/);
  assert.equal(h.events.length, 0, 'callbacks are queued until the caller receives the cancellation token');
  await settle();
  assertTerminal(h, 'complete');
  assert.equal(h.requests.length, 11);
  const result = h.result().result;
  assert.deepEqual(result.samples, [10, 20, 30, 40, 50]);
  assert.equal(result.attempted, 5);
  assert.equal(result.successful, 5);
  assert.equal(result.latencyMs, 30, 'the 900 ms warm-up is excluded');
  assert.equal(result.jitterMs, 10);
  assert.equal(result.downloadBytes, 5.25 * MiB);
  assert.equal(result.uploadBytes, 1.25 * MiB);
  assert.equal(result.downloadMbps, 5.25 * MiB * 8 / 700 / 1000);
  assert.equal(result.uploadMbps, 1.25 * MiB * 8 / 300 / 1000);
  assert.equal(result.provider, 'Cloudflare');
  assert.ok(result.startedAt && result.completedAt);
  assert.deepEqual(h.requests.slice(0, 9).map(call => Number(new URL(call.url).searchParams.get('bytes'))),
    [0, 0, 0, 0, 0, 0, 262144, 1048576, 4194304]);
  for (const call of h.requests) {
    assertPrivateRequest(call);
    const url = new URL(call.url);
    assert.equal(url.origin + url.pathname, call.init.method === 'POST' ? UP : DOWN);
    if (call.init.method === 'GET') {
      assert.deepEqual([...url.searchParams.keys()].sort(), ['bytes', 'tn']);
      assert.ok(url.searchParams.get('tn').startsWith(id));
      assert.equal(call.init.body, undefined);
    }
  }
  const uploads = h.requests.filter(call => call.init.method === 'POST');
  assert.deepEqual(uploads.map(call => call.init.body.byteLength), [262144, 1048576]);
  assert.equal(h.randomCalls.reduce((sum, bytes) => sum + bytes, 0), 1.25 * MiB);
  assert.ok(uploads.every(call => call.init.body instanceof Uint8Array));
  assert.ok(uploads.every(call => new Set(call.init.body).size > 200), 'upload content comes from the synthetic random-byte generator');
  assert.ok(!uploads.some(call => new TextDecoder().decode(call.init.body).includes('private text')));
  await h.advance(600000);
  assert.equal(h.requests.length, 11, 'no repeat or automatic background run');
});

test('throughput includes only transfers lasting at least 20 ms while traffic counts include all actual transfers', async () => {
  const h = harness({ durations: [50, 5, 5, 5, 5, 5, 19, 20, 40, 19, 20] });
  h.start(); await settle(); assertTerminal(h, 'complete');
  const result = h.result().result;
  assert.equal(result.downloadBytes, 5.25 * MiB);
  assert.equal(result.uploadBytes, 1.25 * MiB);
  assert.equal(result.downloadMbps, 5 * MiB * 8 / 60 / 1000);
  assert.equal(result.uploadMbps, MiB * 8 / 20 / 1000);
});

test('sub-20 ms transfers never produce implausibly large or infinite speed numbers', async () => {
  const h = harness({ durations: [50, 5, 5, 5, 5, 5, 0, 19, 1, 19, 0] });
  h.start(); await settle(); assertTerminal(h, 'complete');
  assert.equal(h.result().result.downloadMbps, null);
  assert.equal(h.result().result.uploadMbps, null);
  assert.ok(h.result().result.warnings.some(warning => warning.includes('20')));
});

test('actual streamed bytes and full body duration determine speed, not Content-Length or the fetch headers time', async () => {
  const h = harness({ fetch(call, state) {
    if (call.index < 6 || call.init.method === 'POST') { state.elapse(50); return normalResponse(call.url, call.init); }
    const size = Number(new URL(call.url).searchParams.get('bytes'));
    let sent = 0;
    return response(new ReadableStream({ pull(controller) {
      if (sent === size) { controller.close(); return; }
      const length = Math.min(65536, size - sent);
      state.elapse(10); controller.enqueue(new Uint8Array(length)); sent += length;
    } }), { headers: { 'content-length': '1' } });
  } });
  h.start(); await settle(); assertTerminal(h, 'complete');
  assert.equal(h.result().result.downloadBytes, 5.25 * MiB);
  assert.equal(h.result().result.downloadMbps, 5.25 * MiB * 8 / (84 * 10) / 1000);
});

for (const status of [301, 403, 429, 500, 503]) {
  test(`HTTP ${status} terminates without a measurement, fallback endpoint, or automatic retry`, async () => {
    const h = harness({ fetch: () => response('blocked', { status, headers: { 'retry-after': '1' } }) });
    h.start(); await settle(); assertTerminal(h, 'error');
    assert.match(h.result().message, new RegExp(`HTTP ${status}`));
    for (const key of ['latencyMs', 'jitterMs', 'downloadMbps', 'uploadMbps']) assert.equal(h.result().result[key], null);
    assert.equal(h.result().result.downloadBytes, 0);
    assert.equal(h.result().result.uploadBytes, 0);
    assert.deepEqual(h.result().result.samples, []);
    await h.advance(300000);
    assert.equal(h.requests.length, 1);
  });
}

test('opaque and network/CORS failures are never presented as measurements or proof that a provider is down', async () => {
  for (const fetch of [() => ({ ok: true, type: 'opaque', status: 0 }), () => Promise.reject(new TypeError('Failed to fetch'))]) {
    const h = harness({ fetch }); h.start(); await settle(); assertTerminal(h, 'error');
    assert.equal(h.result().result.latencyMs, null);
    assert.equal(h.result().result.downloadMbps, null);
    assert.equal(h.requests.length, 1);
    assert.ok(h.result().message);
  }
});

test('HTML responses are rejected even with a successful status and a plausible byte length', async () => {
  const h = harness({ fetch: () => response('', { headers: { 'content-type': 'text/html; charset=UTF-8' } }) });
  h.start(); await settle(); assertTerminal(h, 'error');
  assert.match(h.result().message, /网页/);
  assert.equal(h.requests.length, 1);
  assert.equal(h.result().result.latencyMs, null);
});

test('a download with the wrong actual byte count cannot yield a throughput value', async () => {
  const h = harness({ fetch(call, state) {
    state.elapse(50);
    if (call.index === 6) return response(new Uint8Array(10), { headers: { 'content-length': '262144' } });
    return normalResponse(call.url, call.init);
  } });
  h.start(); await settle(); assertTerminal(h, 'error');
  assert.match(h.result().message, /大小/);
  assert.equal(h.result().result.downloadMbps, null);
  assert.equal(h.result().result.downloadBytes, 0);
  assert.equal(h.result().result.uploadBytes, 0);
  assert.equal(h.requests.length, 7);
});

test('oversized streams are aborted and cancelled without reading the rest or moving on to upload', async () => {
  let cancelled = 0, pulled = 0;
  const h = harness({ fetch(call, state) {
    state.elapse(50);
    if (call.index !== 6) return normalResponse(call.url, call.init);
    return response(new ReadableStream({ pull(controller) {
      pulled++; controller.enqueue(new Uint8Array(262145));
    }, cancel() { cancelled++; } }, { highWaterMark: 0 }));
  } });
  h.start(); await settle(); assertTerminal(h, 'error');
  assert.match(h.result().message, /超过/);
  assert.equal(h.requests[6].init.signal.aborted, true);
  assert.equal(cancelled, 1);
  assert.equal(pulled, 1);
  assert.equal(h.requests.length, 7);
  assert.equal(h.result().result.downloadMbps, null);
});

test('oversized upload acknowledgement is rejected and a second upload is not sent', async () => {
  const h = harness({ fetch(call, state) {
    state.elapse(50);
    return call.init.method === 'POST' ? response(new Uint8Array(8193)) : normalResponse(call.url, call.init);
  } });
  h.start(); await settle(); assertTerminal(h, 'error');
  assert.equal(h.requests.filter(call => call.init.method === 'POST').length, 1);
  assert.equal(h.result().result.uploadMbps, null);
  assert.equal(h.result().result.uploadBytes, 0);
});

test('unsupported streaming and random-byte APIs stop cleanly instead of inventing measurement or upload data', async () => {
  const noStream = harness({ fetch: () => ({ ok: true, headers: new Headers(), body: null }) });
  noStream.start(); await settle(); assertTerminal(noStream, 'error');
  assert.equal(noStream.requests.length, 1);
  assert.equal(noStream.result().result.latencyMs, null);
  const noRandom = harness({ noCrypto: true });
  noRandom.start(); await settle(); assertTerminal(noRandom, 'error');
  assert.equal(noRandom.requests.filter(call => call.init.method === 'POST').length, 0);
  assert.equal(noRandom.result().result.uploadMbps, null);
});

test('same-origin HTTPS latency uses an exact probe body, unique nonces, one excluded warm-up, and ten samples', async () => {
  const h = harness({ durations: [500, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100] });
  h.start('latency', { url: 'https://attacker.test/' }); await settle(); assertTerminal(h, 'complete');
  assert.equal(h.requests.length, 11);
  const nonces = new Set();
  for (const call of h.requests) {
    assertPrivateRequest(call);
    const url = new URL(call.url);
    assert.equal(url.origin, 'https://clock.test');
    assert.equal(url.pathname, '/time_nest/network-probe.txt');
    assert.deepEqual([...url.searchParams.keys()], ['tn']);
    nonces.add(url.searchParams.get('tn'));
    assert.equal(call.init.method, 'GET');
  }
  assert.equal(nonces.size, 11);
  assert.equal(h.result().result.provider, '本站 HTTPS');
  assert.equal(h.result().result.latencyMs, 55);
  assert.equal(h.result().result.jitterMs, 10);
  assert.equal(h.result().result.attempted, 10);
  assert.equal(h.result().result.successful, 10);
  assert.deepEqual(h.result().result.samples, [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]);
  assert.equal(h.result().result.downloadMbps, null);
  assert.equal(h.result().result.uploadMbps, null);
});

test('the checked-in probe is the exact measurement sentinel rather than a generated page', async () => {
  assert.equal(await readFile(new URL('../web/network-probe.txt', import.meta.url), 'utf8'), PROBE);
});

test('bad probe bodies and cross-origin document bases fail without accepting a false latency sample', async () => {
  for (const body of ['x'.repeat(PROBE.length), `${PROBE}\n`, '<html>offline shell</html>']) {
    const h = harness({ fetch: () => response(body) });
    h.start('latency'); await settle(); assertTerminal(h, 'error');
    assert.equal(h.result().result.latencyMs, null);
    assert.equal(h.requests.length, 1);
  }
  const h = harness({ baseURI: 'https://attacker.test/' });
  h.start('latency'); await settle(); assertTerminal(h, 'error');
  assert.equal(h.requests.length, 0);
});

test('failed latency samples are null, with only successful adjacent samples contributing to jitter', async () => {
  const values = [999, 10, null, 30, 50, null, 90, 100, 110, 120, 130];
  const h = harness({ fetch(call, state) {
    if (values[call.index] === null) throw new TypeError('simulated network failure');
    state.elapse(values[call.index]); return normalResponse(call.url, call.init);
  } });
  h.start('latency'); await settle(); assertTerminal(h, 'complete');
  assert.deepEqual(h.result().result.samples, values.slice(1));
  assert.equal(h.result().result.successful, 8);
  assert.equal(h.result().result.attempted, 10);
  assert.equal(h.result().result.latencyMs, 80);
  assert.equal(h.result().result.jitterMs, 12);
  assert.equal(h.requests.length, 11, 'failed samples do not cause extra retries');
});

test('zero-duration latency samples remain invalid and cannot be promoted to zero-millisecond measurements', async () => {
  const h = harness({ durations: Array(11).fill(0) });
  h.start('latency'); await settle(); assertTerminal(h, 'error');
  assert.equal(h.result().result.successful, 0);
  assert.equal(h.result().result.latencyMs, null);
  assert.equal(h.result().result.jitterMs, null);
  assert.deepEqual(h.result().result.samples, Array(10).fill(null));
});

test('cancellation before queued execution and repeated cancellation never start a request', async () => {
  const h = harness(), id = h.start();
  h.api.cancel(id); h.api.cancel(id); h.api.cancel('nonexistent');
  await settle(); assertTerminal(h, 'cancelled');
  assert.equal(h.requests.length, 0);
});

test('cancelling an active request aborts it and late completion cannot emit stale events or restart work', async () => {
  const pending = deferred(), h = harness({ fetch: () => pending.promise });
  const id = h.start(); await settle();
  assert.equal(h.requests.length, 1);
  h.api.cancel(id);
  assert.equal(h.requests[0].init.signal.aborted, true);
  const count = h.events.length;
  pending.resolve(response('')); await settle();
  assertTerminal(h, 'cancelled');
  assert.equal(h.events.length, count);
  await h.advance(120000);
  assert.equal(h.requests.length, 1);
});

test('starting a new operation cancels and isolates the previous run even when its fetch resolves later', async () => {
  const pending = deferred(), oldEvents = [], newEvents = [];
  const h = harness({ fetch(call, state) {
    if (call.index === 0) return pending.promise;
    state.elapse(50); return normalResponse(call.url, call.init);
  } });
  const oldId = h.start('speed', {}, oldEvents); await settle();
  const newId = h.start('dns', { name: 'example.com', type: 'A' }, newEvents); await settle();
  assert.notEqual(newId, oldId);
  assert.equal(oldEvents.at(-1).status, 'cancelled');
  assert.equal(newEvents.at(-1).status, 'complete');
  assert.equal(h.requests[0].init.signal.aborted, true);
  const oldCount = oldEvents.length, newCount = newEvents.length;
  pending.resolve(response('')); await settle();
  assert.equal(oldEvents.length, oldCount);
  assert.equal(newEvents.length, newCount);
  h.api.cancel(oldId);
  assert.equal(newEvents.at(-1).status, 'complete');
  assert.equal(h.requests.length, 2);
  assert.equal(h.timers.size, 0);
});

test('the per-request timeout aborts a stalled warm-up after eight seconds with no fallback or retry', async () => {
  const h = harness({ fetch: abortablePending }); h.start(); await settle();
  await h.advance(7999);
  assert.equal(h.requests[0].init.signal.aborted, false);
  await h.advance(1); assertTerminal(h, 'error');
  assert.equal(h.requests[0].init.signal.aborted, true);
  assert.match(h.result().message, /超时/);
  assert.equal(h.result().result.latencyMs, null);
  await h.advance(120000);
  assert.equal(h.requests.length, 1);
});

test('the 45-second global limit stops otherwise continuing latency attempts and does not resume automatically', async () => {
  const h = harness({ fetch(call, state) {
    if (call.index === 0) { state.elapse(1); return normalResponse(call.url, call.init); }
    return abortablePending(call);
  } });
  h.start('latency'); await settle();
  await h.advance(44998);
  assert.notEqual(h.result().status, 'cancelled');
  await h.advance(1); assertTerminal(h, 'cancelled');
  assert.match(h.result().message, /45/);
  assert.equal(h.requests.at(-1).init.signal.aborted, true);
  const count = h.requests.length;
  await h.advance(300000);
  assert.equal(h.requests.length, count);
});

for (const event of ['hide', 'pagehide']) {
  test(`${event} aborts active work; returning visible requires a new explicit start`, async () => {
    const h = harness({ fetch: abortablePending }); h.start(); await settle();
    h[event](); await settle(); assertTerminal(h, 'cancelled');
    assert.equal(h.requests[0].init.signal.aborted, true);
    h.show(); await h.advance(300000);
    assert.equal(h.requests.length, 1);
  });
}

test('starting while hidden does not make requests', async () => {
  const h = harness({ hidden: true }); h.start(); await settle(); assertTerminal(h, 'error');
  assert.equal(h.requests.length, 0);
  h.show(); await h.advance(300000); assert.equal(h.requests.length, 0);
});

test('cancelling while reading a body suppresses all partial results and later stream data', async () => {
  let stream;
  const h = harness({ fetch: () => response(new ReadableStream({ start(controller) { stream = controller; } })) });
  const id = h.start(); await settle();
  h.api.cancel(id);
  const count = h.events.length;
  stream.enqueue(new Uint8Array()); stream.close(); await settle();
  assertTerminal(h, 'cancelled');
  assert.equal(h.requests[0].init.signal.aborted, true);
  assert.equal(h.events.length, count);
  assert.equal(h.requests.length, 1);
});

test('invalid JSON, invalid argument shapes, and unknown tools fail before making requests', async () => {
  for (const [kind, args] of [['speed', '{'], ['speed', 'null'], ['speed', '[]'], ['speed', '42'], ['unknown', '{}']]) {
    const h = harness(); h.start(kind, args); await settle(); assertTerminal(h, 'error');
    assert.equal(h.requests.length, 0);
  }
});

test('DNS rejects URLs, credentials, ports, private names, IPs, malformed labels, and unknown types without any request', async () => {
  const invalidNames = [
    '', 'localhost', 'router', 'printer.local', 'host.localhost', 'corp.internal', 'printer.lan', 'device.home',
    'printer.home.arpa', 'private.onion', 'device.localdomain', 'a.test', 'a.invalid', '127.0.0.1', '192.168.1.1', '8.8.8.8', '0x7f000001', '2130706433', '[::1]',
    'https://example.com', '//example.com', 'example.com/path', 'example.com:443', 'me@example.com',
    'example.com?x=1', 'example.com#secret', 'example%2ecom', 'example\\com', 'a..com', '-bad.com',
    'bad-.com', 'bad_name.com', 'x.123', `${'a'.repeat(64)}.com`, `${'a'.repeat(250)}.com`,
  ];
  for (const name of invalidNames) {
    const h = harness(); h.start('dns', { name, type: 'A' }); await settle();
    assertTerminal(h, 'error'); assert.equal(h.requests.length, 0, name);
  }
  for (const type of ['ANY', 'AXFR', 'HTTPS', 'a', 'constructor', '__proto__', 1, null]) {
    const h = harness(); h.start('dns', { name: 'example.com', type }); await settle();
    assertTerminal(h, 'error'); assert.equal(h.requests.length, 0, String(type));
  }
});

test('public IDNA and a trailing root dot normalize safely; each documented record type uses the fixed DNS endpoint', async () => {
  for (const type of ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'NS']) {
    const h = harness(); h.start('dns', { name: '  BÜCHER.de.  ', type, url: 'https://attacker.test/' });
    await settle(); assertTerminal(h, 'complete');
    assert.equal(h.requests.length, 1);
    const call = h.requests[0], url = new URL(call.url);
    assertPrivateRequest(call);
    assert.equal(url.origin + url.pathname, DNS);
    assert.deepEqual([...url.searchParams.keys()].sort(), ['name', 'type']);
    assert.equal(url.searchParams.get('name'), 'xn--bcher-kva.de');
    assert.equal(url.searchParams.get('type'), type);
    assert.equal(call.init.headers.Accept, 'application/dns-json');
    assert.equal(call.init.method, 'GET');
    assert.equal(call.init.body, undefined);
    assert.equal(h.result().result.name, 'xn--bcher-kva.de');
    assert.equal(h.result().result.type, type);
    assert.equal(h.result().result.latencyMs, null);
  }
});

test('valid DNS records expose only returned answers, TTL, type, rcode, and authentication state', async () => {
  const answer = [
    { name: 'example.com.', type: 1, TTL: 300, data: '93.184.216.34' },
    { name: 'example.com.', type: 28, TTL: 0, data: '2606:2800:220:1::1' },
    { name: 'example.com.', type: 16, TTL: 60, data: '"verification token"' },
  ];
  const h = harness({ fetch: () => dnsResponse({ Status: 0, TC: false, AD: true, Question: [{ name: 'example.com.', type: 1 }], Answer: answer }) });
  h.start('dns', { name: 'example.com', type: 'A' }); await settle(); assertTerminal(h, 'complete');
  assert.equal(h.result().result.rcode, 0);
  assert.equal(h.result().result.dnssec, true);
  assert.deepEqual(h.result().result.answers, answer.map((record, index) => ({
    name: record.name, type: ['A', 'AAAA', 'TXT'][index], ttl: record.TTL, data: record.data,
  })));
  assert.equal(h.requests.length, 1);
});

test('DNS NXDOMAIN is a real empty DNS response, not a fabricated answer or a network failure', async () => {
  const h = harness({ fetch: () => dnsResponse({ Status: 3, TC: false, AD: false, Question: [{ name: 'does-not-exist.example.com.', type: 1 }] }) });
  h.start('dns', { name: 'does-not-exist.example.com', type: 'A' }); await settle(); assertTerminal(h, 'complete');
  assert.equal(h.result().result.rcode, 3);
  assert.equal(h.result().result.dnssec, false);
  assert.deepEqual(h.result().result.answers, []);
  assert.equal(h.requests.length, 1);
});

test('malformed, truncated, invalid-record, and oversized DNS responses stop without fallback or invented records', async () => {
  const valid = { name: 'example.com.', type: 1, TTL: 60, data: '192.0.2.1' };
  const Question = [{ name: 'example.com.', type: 1 }];
  const malformed = [
    null, {}, { Status: '0', Question }, { Status: -1, Question }, { Status: 16, Question }, { Status: 0, TC: true, Question },
    { Status: 0, Question, Answer: {} }, { Status: 0, Question, Answer: [null] }, { Status: 0, Question, Answer: Array(101).fill(valid) },
    ...[{ ...valid, name: 1 }, { ...valid, name: 'a'.repeat(256) }, { ...valid, type: 'A' },
      { ...valid, TTL: -1 }, { ...valid, TTL: 0.5 }, { ...valid, data: 1 }, { ...valid, data: 'x'.repeat(4097) }]
      .map(record => ({ Status: 0, Question, Answer: [record] })),
  ];
  const replies = malformed.map(value => () => dnsResponse(value));
  replies.push(() => response('{not JSON'), () => response(new Uint8Array(65537)), () => response('<html>blocked</html>', { headers: { 'content-type': 'text/html' } }));
  for (const fetch of replies) {
    const h = harness({ fetch }); h.start('dns', { name: 'example.com', type: 'A' });
    await settle(); assertTerminal(h, 'error');
    assert.equal(h.result().result.answers, undefined);
    assert.equal(h.result().result.rcode, undefined);
    assert.equal(h.requests.length, 1);
    await h.advance(300000); assert.equal(h.requests.length, 1);
  }
});


test('a missing, repeated, malformed, or mismatched DNS Question cannot be accepted as this lookup result', async () => {
  const questions = [undefined, null, [], {}, [null], [{ name: 'example.com.', type: 1 }, { name: 'example.com.', type: 1 }],
    [{ name: 'other.example.com.', type: 1 }], [{ name: 'example.com.', type: 28 }],
    [{ name: 'example.com.', type: '1' }], [{ name: 1, type: 1 }]];
  for (const Question of questions) {
    const h = harness({ fetch: () => dnsResponse({ Status: 0, Question,
      Answer: [{ name: 'example.com.', type: 1, TTL: 300, data: '192.0.2.1' }],
    }) });
    h.start('dns', { name: 'example.com', type: 'A' }); await settle(); assertTerminal(h, 'error');
    assert.equal(h.result().result.answers, undefined);
    assert.equal(h.result().result.rcode, undefined);
    assert.equal(h.requests.length, 1);
  }
});

test('a disposed callback cannot leave transfers running unseen', async () => {
  for (const throwAt of ['warmup', 'download', 'upload']) {
    const h = harness();
    h.api.start('speed', '{}', raw => {
      const event = JSON.parse(raw);
      h.events.push(event);
      if (event.stage === throwAt) throw new Error('disposed listener');
    });
    await settle(); assertTerminal(h, 'cancelled');
    assert.equal(h.requests.length, { warmup: 0, download: 6, upload: 9 }[throwAt]);
    const count = h.requests.length;
    await h.advance(300000); assert.equal(h.requests.length, count);
  }
});

for (const failure of ['HTTP error', 'HTML page']) {
  test(`a stalled ${failure} response is aborted before its body can continue downloading`, async () => {
    let aborted = 0, pulls = 0;
    const h = harness({ fetch(call) {
      const body = new ReadableStream({
        start(controller) {
          call.init.signal.addEventListener('abort', () => {
            aborted++;
            controller.error(new DOMException('Aborted', 'AbortError'));
          }, { once: true });
        },
        pull() { pulls++; return new Promise(() => {}); },
      }, { highWaterMark: 0 });
      return response(body, failure === 'HTTP error'
        ? { status: 503 }
        : { headers: { 'content-type': 'text/html' } });
    } });
    h.start(); await settle(); assertTerminal(h, 'error');
    assert.equal(h.requests[0].init.signal.aborted, true);
    assert.equal(aborted, 1);
    assert.equal(pulls, 0, 'unwanted response bodies need not be read to detect the error');
    assert.equal(h.result().result.latencyMs, null);
    await h.advance(120000);
    assert.equal(h.requests.length, 1);
  });
}

for (const [rcode, explanation] of [[2, 'SERVFAIL'], [5, 'REFUSED']]) {
  test(`DNS ${explanation} retains its real RCODE but is an error, not a successful no-record answer`, async () => {
    const h = harness({ fetch: () => dnsResponse({
      Status: rcode, TC: false, AD: false, Question: [{ name: 'example.com.', type: 1 }],
    }) });
    h.start('dns', { name: 'example.com', type: 'A' }); await settle(); assertTerminal(h, 'error');
    assert.equal(h.result().result.rcode, rcode);
    assert.match(h.result().message, new RegExp(explanation));
    assert.match(h.result().message, /无法判断/);
    assert.deepEqual(h.result().result.answers, []);
    assert.equal(h.requests.length, 1);
    assert.deepEqual(h.history(), { available: true, items: [] });
    assert.equal(h.storageOps.filter(([operation]) => operation === 'set').length, 0);
  });
}

function historyRecord(overrides = {}) {
  return { kind: 'speed', status: 'complete', provider: 'Cloudflare', completedAt: '2026-10-20T11:00:00.000Z',
    latencyMs: 30, jitterMs: 5, downloadMbps: 100, uploadMbps: 20, ...overrides };
}
const METRICS = ['latencyMs', 'jitterMs', 'downloadMbps', 'uploadMbps'];
const HISTORY_FIELDS = ['kind', 'status', 'provider', 'completedAt', ...METRICS].sort();

test('initialization, environment inspection, and history reads never write local history or create network requests', async () => {
  const existing = JSON.stringify([historyRecord()]);
  const h = harness({ storage: new Map([[HISTORY_KEY, existing], ['other.setting', 'keep']]) });
  assert.deepEqual(h.storageOps, []);
  h.api.environment(); h.api.environment();
  assert.deepEqual(h.storageOps, []);
  assert.deepEqual(h.history(), { available: true, items: [historyRecord()] });
  h.history(); await h.advance(300000);
  assert.ok(h.storageOps.every(([operation, key]) => operation === 'get' && key === HISTORY_KEY));
  assert.equal(h.storage.get(HISTORY_KEY), existing);
  assert.equal(h.storage.get('other.setting'), 'keep');
  assert.equal(h.requests.length, 0);
  assert.equal(h.timers.size, 0);
});

test('terminal speed and latency metrics persist once and remain readable in a fresh VM instance', async () => {
  const storage = new Map();
  const speed = harness({ storage });
  speed.start(); await settle(); assertTerminal(speed, 'complete');
  const record = speed.history().items[0], result = speed.result().result;
  assert.equal(record.kind, 'speed'); assert.equal(record.status, 'complete');
  assert.equal(record.completedAt, result.completedAt);
  for (const metric of METRICS) assert.equal(record[metric], result[metric]);
  assert.deepEqual(Object.keys(record).sort(), HISTORY_FIELDS);
  assert.equal(speed.storageOps.filter(([operation]) => operation === 'set').length, 1);
  const latency = harness({ storage });
  assert.deepEqual(latency.history().items, [record]);
  latency.elapse(1000); latency.start('latency'); await settle(); assertTerminal(latency, 'complete');
  const reloaded = harness({ storage });
  assert.deepEqual(reloaded.history().items.map(item => item.kind), ['latency', 'speed']);
  assert.equal(reloaded.history().items[0].provider, '本站 HTTPS');
  assert.equal(reloaded.history().items[0].downloadMbps, null);
  assert.equal(reloaded.history().items[0].uploadMbps, null);
  assert.equal(reloaded.requests.length, 0);
  assert.equal(reloaded.storageOps.filter(([operation]) => operation === 'set').length, 0);
});

test('history keeps at most twenty newest terminal measurements across page reloads', async () => {
  const storage = new Map();
  const completedAt = [];
  for (let index = 0; index < 24; index++) {
    const h = harness({ storage });
    h.elapse(index * 1000); h.start('latency'); await settle(); assertTerminal(h, 'complete');
    completedAt.push(h.result().result.completedAt);
    assert.equal(h.storageOps.filter(([operation]) => operation === 'set').length, 1);
    assert.equal(JSON.parse(storage.get(HISTORY_KEY)).length, Math.min(index + 1, 20));
  }
  const restored = harness({ storage });
  assert.deepEqual(restored.history().items.map(item => item.completedAt), completedAt.slice(-20).reverse());
  assert.equal(restored.requests.length, 0);
});

test('DNS successes, failures, and cancellations never enter local history', async () => {
  const existing = JSON.stringify([historyRecord()]), storage = new Map([[HISTORY_KEY, existing]]);
  const good = harness({ storage });
  good.start('dns', { name: 'example.com', type: 'A' }); await settle(); assertTerminal(good, 'complete');
  const invalid = harness({ storage });
  invalid.start('dns', { name: 'private.local', type: 'A' }); await settle(); assertTerminal(invalid, 'error');
  const cancelled = harness({ storage, fetch: abortablePending });
  const id = cancelled.start('dns', { name: 'example.com', type: 'A' }); await settle();
  cancelled.api.cancel(id); await settle(); assertTerminal(cancelled, 'cancelled');
  for (const h of [good, invalid, cancelled]) assert.equal(h.storageOps.filter(([operation]) => operation === 'set').length, 0);
  assert.equal(storage.get(HISTORY_KEY), existing);
});

test('history reads strip injected names, addresses, and extra fields while deriving providers from known tool kinds', async () => {
  const injected = [
    historyRecord({ provider: 'attacker', name: 'private.host', ip: '192.168.1.25', answers: ['secret'], samples: [1, 2], url: 'https://private.host' }),
    historyRecord({ kind: 'latency', provider: 'another attacker', downloadMbps: 9000, uploadMbps: 9000, address: 'home address' }),
    historyRecord({ kind: 'dns', name: 'private.host', data: 'private answer' }),
  ];
  const raw = JSON.stringify(injected), storage = new Map([[HISTORY_KEY, raw]]), h = harness({ storage });
  const items = h.history().items;
  assert.equal(items.length, 2);
  assert.deepEqual(items[0], historyRecord());
  assert.deepEqual(items[1], historyRecord({ kind: 'latency', provider: '本站 HTTPS', downloadMbps: null, uploadMbps: null }));
  assert.ok(items.every(item => JSON.stringify(Object.keys(item).sort()) === JSON.stringify(HISTORY_FIELDS)));
  assert.equal(storage.get(HISTORY_KEY), raw, 'reading does not mutate storage');
  h.start('latency'); await settle(); assertTerminal(h, 'complete');
  const persisted = storage.get(HISTORY_KEY);
  assert.doesNotMatch(persisted, /attacker|private\.host|192\.168|secret|home address/);
  assert.ok(JSON.parse(persisted).every(item => JSON.stringify(Object.keys(item).sort()) === JSON.stringify(HISTORY_FIELDS)));
});

test('failed or cancelled measurements with real partial data store only null metrics, never partial successes', async () => {
  const failed = harness({ fetch(call, state) {
    state.elapse(50);
    return call.index === 7 ? response('blocked', { status: 503 }) : normalResponse(call.url, call.init);
  } });
  failed.start(); await settle(); assertTerminal(failed, 'error');
  assert.ok(failed.result().result.downloadMbps > 0, 'the request failed after a genuine partial transfer');
  assert.equal(failed.history().items[0].status, 'error');
  for (const metric of METRICS) assert.equal(failed.history().items[0][metric], null);
  const cancelled = harness();
  const id = cancelled.api.start('speed', '{}', raw => {
    const event = JSON.parse(raw); cancelled.events.push(event);
    if (event.status === 'running' && event.result.downloadBytes > 0) cancelled.api.cancel(id);
  });
  await settle(); assertTerminal(cancelled, 'cancelled');
  assert.ok(cancelled.result().result.downloadMbps > 0);
  assert.equal(cancelled.history().items[0].status, 'cancelled');
  for (const metric of METRICS) assert.equal(cancelled.history().items[0][metric], null);
  const pending = harness({ fetch: abortablePending });
  const pendingId = pending.start(); await settle();
  assert.deepEqual(pending.history().items, []);
  assert.equal(pending.storageOps.filter(([operation]) => operation === 'set').length, 0);
  pending.api.cancel(pendingId); await settle(); assertTerminal(pending, 'cancelled');
});

test('stored incomplete or malformed records are filtered, while failed metrics and nonnumeric values become null', () => {
  const records = [
    null, false, 'record', [], {},
    historyRecord({ kind: 'dns' }), historyRecord({ kind: 'unknown' }), historyRecord({ status: 'running' }),
    historyRecord({ status: 'pending' }), historyRecord({ completedAt: null }), historyRecord({ completedAt: 'not a date' }),
    historyRecord({ completedAt: '1'.repeat(41) }),
    historyRecord({ status: 'cancelled' }), historyRecord({ status: 'error' }),
    historyRecord({ latencyMs: '30', jitterMs: -1, downloadMbps: null, uploadMbps: false }),
  ];
  const h = harness({ storage: new Map([[HISTORY_KEY, JSON.stringify(records)]]) });
  const items = h.history().items;
  assert.equal(items.length, 3);
  assert.deepEqual(items.map(item => item.status), ['cancelled', 'error', 'complete']);
  for (const item of items) for (const metric of METRICS) assert.equal(item[metric], null);
  assert.equal(h.storageOps.filter(([operation]) => operation === 'set').length, 0);
});

test('invalid JSON, nonarray roots, and oversized history return empty rather than breaking the tools', () => {
  for (const raw of ['{', '{}', 'null', 'true', '42', '"records"', '', `[${' '.repeat(32768)}]`]) {
    const h = harness({ storage: new Map([[HISTORY_KEY, raw]]) });
    assert.deepEqual(h.history(), { available: true, items: [] });
    assert.equal(h.storageOps.filter(([operation]) => operation === 'set').length, 0);
    assert.equal(h.requests.length, 0);
  }
});

for (const failure of ['storageGetterFails', 'storageReadFails', 'storageWriteFails']) {
  test(`${failure} reports history unavailable without preventing a valid measurement`, async () => {
    const h = harness({ [failure]: true });
    if (failure !== 'storageWriteFails') assert.deepEqual(h.history(), { available: false, items: [] });
    h.start('latency'); await settle(); assertTerminal(h, 'complete');
    assert.equal(h.result().result.latencyMs, 50);
    assert.deepEqual(h.history(), { available: false, items: [] });
    assert.equal(h.requests.length, 11);
    assert.equal(h.timers.size, 0);
  });
}

test('clearing history removes only its own key and a failed clear leaves unrelated settings untouched', () => {
  const raw = JSON.stringify([historyRecord()]);
  const storage = new Map([[HISTORY_KEY, raw], ['shike.settings.v1', '{"theme":"dark"}'], ['unrelated', 'keep']]);
  const blocked = harness({ storage, storageRemoveFails: true });
  assert.equal(blocked.api.clearHistory(), false);
  assert.equal(blocked.history().available, false);
  assert.equal(storage.get(HISTORY_KEY), raw);
  assert.equal(storage.get('unrelated'), 'keep');
  const h = harness({ storage });
  assert.equal(h.api.clearHistory(), true);
  assert.equal(storage.has(HISTORY_KEY), false);
  assert.equal(storage.get('shike.settings.v1'), '{"theme":"dark"}');
  assert.equal(storage.get('unrelated'), 'keep');
  assert.deepEqual(h.history(), { available: true, items: [] });
  assert.deepEqual(h.storageOps.filter(([operation]) => operation !== 'get'), [['remove', HISTORY_KEY]]);
  assert.equal(h.requests.length, 0);
});
