import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { webcrypto } from 'node:crypto';
import vm from 'node:vm';
import { includedPath, renderServiceWorker } from '../tool/generate_sw.mjs';

const template = await readFile(new URL('../web/sw.template.js', import.meta.url), 'utf8');
function files(version = 'one') {
  return [
    ['index.html', `<html>${version}</html>`],
    ['flutter_bootstrap.js', `bootstrap-${version}`],
    ['main.dart.js', `main-${version}`],
    ['platform.js', 'browser bridge'],
    ['assets/FontManifest.json', '[]'],
    ['assets/fonts/本地 clock.woff2', new Uint8Array([0, 255, 1, 200])],
    ['assets/data.json', '{"local":true}'],
    ['canvaskit/canvaskit.js', 'canvaskit loader'],
    ['canvaskit/canvaskit.wasm', new Uint8Array([0, 97, 115, 109])],
    ['canvaskit/chromium/canvaskit.wasm', 'local chromium'],
    ['icons/Icon-192.png', new Uint8Array([137, 80, 78, 71])],
  ].map(([path, bytes]) => ({ path, bytes }));
}
const absolute = (key) => typeof key === 'string' ? key : key.url;
class MemoryCache {
  entries = new Map();
  async put(key, response) { this.entries.set(absolute(key), response.clone()); }
  async match(key) { return this.entries.get(absolute(key))?.clone(); }
  async delete(key) { return this.entries.delete(absolute(key)); }
  async keys() { return [...this.entries.keys()].map((url) => ({ url })); }
}
class MemoryCaches {
  stores = new Map();
  async open(name) {
    if (!this.stores.has(name)) this.stores.set(name, new MemoryCache());
    return this.stores.get(name);
  }
  async keys() { return [...this.stores.keys()]; }
  async delete(name) { return this.stores.delete(name); }
}
function worker(buildFiles = files(), options = {}) {
  const built = renderServiceWorker(buildFiles, template);
  const caches = options.caches || new MemoryCaches();
  const scope = options.scope || 'https://clock.test/deep/clock/';
  const liveClients = options.clients || [];
  const handlers = new Map();
  const calls = [];
  let claims = 0, skips = 0;
  const resources = new Map(buildFiles.map((file) => [new URL(file.path.split('/').map(encodeURIComponent).join('/'), scope).href, file.bytes]));
  const self = {
    registration: { scope },
    addEventListener(type, callback) { handlers.set(type, callback); },
    clients: {
      async matchAll() { return liveClients; },
      async claim() { claims += 1; },
    },
    async skipWaiting() { skips += 1; },
  };
  vm.runInNewContext(built.source, {
    self, caches, URL, Response, crypto: webcrypto,
    async fetch(request, init) {
      const url = absolute(request);
      calls.push({ url, init });
      if (options.offline) throw new Error('offline');
      if (options.failPath && url.includes(options.failPath)) return new Response('server error', { status: 500 });
      if (options.changedPath && url.includes(options.changedPath)) return new Response('wrong deployment');
      if (resources.has(url)) return new Response(resources.get(url));
      return new Response('not in precache', { status: 404 });
    },
  }, { filename: 'generated-shike-sw.js' });
  async function lifecycle(type) {
    const work = [];
    handlers.get(type)({ waitUntil(promise) { work.push(promise); } });
    await Promise.all(work);
  }
  async function request(path, { clientId = '', resultingClientId = '', mode = 'cors', method = 'GET' } = {}) {
    let result;
    const request = { url: new URL(path, scope).href, mode, method };
    handlers.get('fetch')({ request, clientId, resultingClientId,
      respondWith(promise) { result = promise; },
    });
    return result ? await result : undefined;
  }
  async function message(type, source = { id: 'tab', url: scope }) {
    const work = [];
    let reply;
    handlers.get('message')({ data: { type }, source,
      ports: [{ postMessage(data) { reply = data; } }],
      waitUntil(promise) { work.push(promise); },
    });
    await Promise.all(work);
    return reply;
  }
  return { ...built, caches, scope, calls, clients: liveClients, lifecycle, request, message,
    claims: () => claims, skips: () => skips,
    cacheName: `shike:${encodeURIComponent(scope)}:version:${built.manifest.version}`,
  };
}

test('generator discovers all supplied assets, fonts and local CanvasKit with URL-safe paths', () => {
  const built = renderServiceWorker(files(), template);
  const paths = built.manifest.resources.map((resource) => resource.path);
  assert.equal(paths.length, files().length);
  assert.ok(paths.includes('assets/fonts/%E6%9C%AC%E5%9C%B0%20clock.woff2'));
  assert.ok(paths.includes('canvaskit/chromium/canvaskit.wasm'));
  assert.ok(paths.includes('icons/Icon-192.png'));
  assert.match(built.manifest.version, /^[0-9a-f]{64}$/);
  assert.ok(built.manifest.resources.every((r) => /^[0-9a-f]{64}$/.test(r.hash)));
  assert.ok(built.source.startsWith('/* SHIKE_GENERATED_SERVICE_WORKER */'));
  assert.equal(built.source.includes('__SHIKE_BUILD_MANIFEST__'), false);
});

test('generation is deterministic; content, resource names, and template change the cache version', () => {
  const first = renderServiceWorker(files(), template);
  assert.equal(renderServiceWorker([...files()].reverse(), template).source, first.source);
  assert.notEqual(renderServiceWorker(files('two'), template).manifest.version, first.manifest.version);
  assert.notEqual(renderServiceWorker([...files(), { path: 'new.txt', bytes: 'new' }], template).manifest.version, first.manifest.version);
  assert.notEqual(renderServiceWorker(files(), `${template}\n// updated policy`).manifest.version, first.manifest.version);
});

test('generated workers, Flutter default worker, sources/maps and hidden files are excluded', () => {
  const extras = ['shike-sw.js', 'sw.template.js', 'flutter_service_worker.js', 'network-probe.txt', 'news.json', 'main.dart.js.map', '.DS_Store', 'assets/.hidden/key'];
  for (const path of extras) assert.equal(includedPath(path), false);
  const first = renderServiceWorker(files(), template);
  const second = renderServiceWorker([...files(), ...extras.map((path) => ({ path, bytes: 'excluded' }))], template);
  assert.equal(first.source, second.source);
});

test('generator fails closed for incomplete or unsafe builds and malformed templates', () => {
  for (const path of ['index.html', 'flutter_bootstrap.js', 'main.dart.js', 'platform.js', 'canvaskit/canvaskit.js']) {
    assert.throws(() => renderServiceWorker(files().filter((file) => file.path !== path), template), /Missing|CanvasKit/);
  }
  assert.throws(() => renderServiceWorker(files().filter((file) => !file.path.endsWith('.wasm')), template), /CanvasKit/);
  for (const path of ['../escape', '/absolute', 'dir\\file', 'dir//file', './file']) {
    assert.throws(() => renderServiceWorker([...files(), { path, bytes: '' }], template), /Unsafe/);
  }
  assert.throws(() => renderServiceWorker([...files(), files()[0]], template), /Duplicate/);
  assert.throws(() => renderServiceWorker(files(), 'missing placeholder'), /exactly one/);
});

test('installation caches the full build, verifies hashes, and never skips waiting', async () => {
  const w = worker();
  await w.lifecycle('install');
  assert.equal(w.calls.length, files().length);
  assert.ok(w.calls.every((call) => call.init.cache === 'reload' && call.init.redirect === 'error'));
  const cache = await w.caches.open(w.cacheName);
  assert.equal((await cache.keys()).length, files().length + 1);
  assert.equal(w.skips(), 0);
  await w.lifecycle('activate');
  assert.equal(w.claims(), 1);
  assert.equal((await w.message('SHIKE_STATUS')).ready, true);
});

for (const failure of ['failPath', 'changedPath']) {
  test(`${failure} rejects installation and removes partial resource cache`, async () => {
    const w = worker(files(), { [failure]: 'main.dart.js' });
    await assert.rejects(w.lifecycle('install'), /HTTP error|Deployment changed/);
    assert.equal((await w.caches.keys()).includes(w.cacheName), false);
    assert.equal(w.skips(), 0);
    await assert.rejects(w.lifecycle('activate'), /Incomplete/);
    assert.equal(w.claims(), 0);
    assert.equal((await w.message('SHIKE_STATUS')).ready, false);
  });
}

test('offline root/index navigation and query-string assets are matched under a subpath', async () => {
  const options = { offline: false };
  const w = worker(files(), options);
  await w.lifecycle('install');
  await w.lifecycle('activate');
  options.offline = true;
  for (const path of ['./', './?from=home', 'index.html?source=app']) {
    const response = await w.request(path, { mode: 'navigate', resultingClientId: `nav-${path}` });
    assert.equal(await response.text(), '<html>one</html>');
  }
  assert.equal(await (await w.request('main.dart.js?cache=anything')).text(), 'main-one');
  const font = await w.request('assets/fonts/%E6%9C%AC%E5%9C%B0%20clock.woff2?version=1');
  assert.deepEqual(new Uint8Array(await font.arrayBuffer()), new Uint8Array([0, 255, 1, 200]));
  assert.equal(w.calls.length, files().length);
});

test('root deployment works without hardcoded subpath', async () => {
  const w = worker(files(), { scope: 'https://clock.test/' });
  await w.lifecycle('install');
  await w.lifecycle('activate');
  assert.equal(await (await w.request('/?launch=1', { mode: 'navigate' })).text(), '<html>one</html>');
});

test('cross-origin/out-of-scope/non-GET and worker probes are untouched; unknown URLs are not cached', async () => {
  const w = worker();
  await w.lifecycle('install');
  for (const path of ['https://other.test/main.dart.js', '/main.dart.js', 'shike-sw.js', 'sw.template.js', 'network-probe.txt?tn=fresh', 'news.json']) {
    assert.equal(await w.request(path), undefined);
  }
  assert.equal(await w.request('main.dart.js', { method: 'POST' }), undefined);
  assert.equal(await w.request('unknown-route', { mode: 'navigate' }), undefined);
  const before = (await (await w.caches.open(w.cacheName)).keys()).length;
  const response = await w.request('not-an-asset.json?random=123');
  assert.equal(response.status, 404);
  const after = (await (await w.caches.open(w.cacheName)).keys()).length;
  assert.equal(after, before);
});

test('missing cached asset rejects bytes from a newer deployment', async () => {
  const options = {};
  const w = worker(files(), options);
  await w.lifecycle('install');
  await w.lifecycle('activate');
  const cache = await w.caches.open(w.cacheName);
  await cache.delete(new URL('main.dart.js', w.scope).href);
  options.changedPath = 'main.dart.js';
  const before = w.calls.length;
  assert.equal((await w.request('main.dart.js', { clientId: 'old-tab' })).status, 503);
  assert.equal(w.calls.length, before + 1);
  assert.equal((await w.message('SHIKE_STATUS', { id: 'old-tab', url: w.scope })).ready, false);
});

test('current cache eviction repairs exact bytes while online, including missing marker', async () => {
  const w = worker();
  await w.lifecycle('install');
  await w.lifecycle('activate');
  await w.caches.delete(w.cacheName);
  const response = await w.request('./', { mode: 'navigate', resultingClientId: 'recovered' });
  assert.equal(response.status, 200);
  assert.equal(await response.text(), '<html>one</html>');
  const state = await w.message('SHIKE_STATUS', { id: 'recovered', url: w.scope });
  assert.equal(state.ready, true);
  assert.equal(state.activeVersion, w.manifest.version);
});

test('skipWaiting is only called by an explicit, in-scope client message', async () => {
  const w = worker();
  await w.lifecycle('install');
  await w.message('SHIKE_STATUS');
  await w.message('SKIP_WAITING', { id: 'foreign', url: 'https://other.test/' });
  await w.message('SKIP_WAITING', { id: 'neighbor', url: 'https://clock.test/neighbor/' });
  await w.message('SKIP_WAITING', null);
  assert.equal(w.skips(), 0);
  await w.message('SKIP_WAITING');
  assert.equal(w.skips(), 1);
});

test('acceptance in one tab keeps other tabs on their complete old version across worker restart', async () => {
  const caches = new MemoryCaches();
  const scope = 'https://clock.test/deep/clock/';
  const clients = [{ id: 'accepting', url: scope }, { id: 'old-tab', url: `${scope}index.html` }];
  const old = worker(files('one'), { caches, clients });
  await old.lifecycle('install');
  await old.lifecycle('activate');
  const next = worker(files('two'), { caches, clients });
  await next.lifecycle('install');
  assert.equal(next.skips(), 0);
  assert.equal(await (await old.request('main.dart.js', { clientId: 'old-tab' })).text(), 'main-one');
  await next.message('SKIP_WAITING', clients[0]);
  await next.lifecycle('activate');
  assert.equal(await (await next.request('main.dart.js', { clientId: 'old-tab' })).text(), 'main-one');
  assert.equal(await (await next.request('./', { mode: 'navigate', resultingClientId: 'new-tab' })).text(), '<html>two</html>');
  assert.equal(await (await next.request('main.dart.js', { clientId: 'new-tab' })).text(), 'main-two');
  const restarted = worker(files('two'), { caches, clients });
  assert.equal(await (await restarted.request('main.dart.js', { clientId: 'old-tab' })).text(), 'main-one');
  assert.equal((await restarted.message('SHIKE_STATUS', clients[1])).version, old.manifest.version);
  assert.ok((await caches.keys()).includes(old.cacheName));
});

test('activation reclaims only unpinned old versions and preserves other apps/caches', async () => {
  const caches = new MemoryCaches();
  const scope = 'https://clock.test/deep/clock/';
  const clients = [{ id: 'old', url: scope }];
  const one = worker(files('one'), { caches, clients });
  await one.lifecycle('install'); await one.lifecycle('activate');
  const two = worker(files('two'), { caches, clients });
  await two.lifecycle('install'); await two.lifecycle('activate');
  await two.request('./', { mode: 'navigate', resultingClientId: 'current' });
  clients.splice(0, clients.length, { id: 'current', url: scope });
  await caches.open('another-app-cache');
  const three = worker(files('three'), { caches, clients });
  await three.lifecycle('install'); await three.lifecycle('activate');
  const names = await caches.keys();
  assert.equal(names.includes(one.cacheName), false);
  assert.equal(names.includes(two.cacheName), true);
  assert.equal(names.includes(three.cacheName), true);
  assert.equal(names.includes('another-app-cache'), true);
  assert.equal(await (await three.request('main.dart.js', { clientId: 'current' })).text(), 'main-two');
});

test('separate deployment scopes never clean each other\'s versions', async () => {
  const caches = new MemoryCaches();
  const first = worker(files(), { caches, scope: 'https://clock.test/a/' });
  const second = worker(files(), { caches, scope: 'https://clock.test/b/' });
  await first.lifecycle('install'); await first.lifecycle('activate');
  await second.lifecycle('install'); await second.lifecycle('activate');
  assert.ok((await caches.keys()).includes(first.cacheName));
  assert.ok((await caches.keys()).includes(second.cacheName));
});
