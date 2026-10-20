/* SHIKE_GENERATED_SERVICE_WORKER */
'use strict';
// Replaced by tool/generate_sw.mjs, never maintain an asset list here.
const BUILD = __SHIKE_BUILD_MANIFEST__;
const SCOPE = new URL(self.registration.scope);
const PREFIX = `shike:${encodeURIComponent(SCOPE.href)}:`;
const CACHE_PREFIX = `${PREFIX}version:`;
const CACHE = `${CACHE_PREFIX}${BUILD.version}`;
const META = `${PREFIX}clients`;
const markerURL = new URL('__shike_internal__/manifest', SCOPE).href;
const activeURL = new URL('__shike_internal__/active', SCOPE).href;
const clientURL = (id) => new URL(`__shike_internal__/client/${encodeURIComponent(id)}`, SCOPE).href;
const resourceURL = (path) => new URL(path, SCOPE).href;
const inScope = (url) => url.origin === SCOPE.origin && url.pathname.startsWith(SCOPE.pathname);
const hash = async (bytes) => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
  (byte) => byte.toString(16).padStart(2, '0')).join('');

async function manifestFor(version) {
  const cache = await caches.open(`${CACHE_PREFIX}${version}`);
  const response = await cache.match(markerURL);
  if (!response) return version === BUILD.version ? BUILD : null;
  try {
    const manifest = await response.json();
    return manifest.version === version && Array.isArray(manifest.resources) ? manifest : null;
  } catch (_) { return null; }
}
async function isComplete(version) {
  const manifest = await manifestFor(version);
  if (!manifest) return false;
  const cache = await caches.open(`${CACHE_PREFIX}${version}`);
  const keys = new Set((await cache.keys()).map((request) => request.url));
  return manifest.resources.every((resource) => keys.has(resourceURL(resource.path)));
}
async function reportProgress(completed) {
  try {
    for (const client of await self.clients.matchAll({ type: 'window', includeUncontrolled: true })) {
      if (inScope(new URL(client.url))) client.postMessage({
        type: 'SHIKE_PROGRESS', completed, total: BUILD.resources.length,
      });
    }
  } catch (_) { /* Progress is optional; cache integrity is authoritative. */ }
}
async function installBuild() {
  if (await isComplete(BUILD.version)) return;
  const cache = await caches.open(CACHE);
  let next = 0;
  let completed = 0;
  await reportProgress(0);
  let failure = null;
  // Bounded concurrency, and drain all in-flight writes before deleting a failed
  // install. A successful marker is written only after EVERY resource is cached.
  await Promise.all(Array.from({ length: Math.min(8, BUILD.resources.length) }, async () => {
    while (!failure && next < BUILD.resources.length) {
      const resource = BUILD.resources[next++];
      try {
        const url = resourceURL(resource.path);
        const response = await fetch(url, { cache: 'reload', credentials: 'same-origin', redirect: 'error' });
        if (response.status !== 200 || response.type === 'opaque') throw new Error(`HTTP error: ${resource.path}`);
        if (await hash(await response.clone().arrayBuffer()) !== resource.hash) {
          throw new Error(`Deployment changed during installation: ${resource.path}`);
        }
        await cache.put(url, response);
        await reportProgress(++completed);
      } catch (error) { failure = error; }
    }
  }));
  if (failure) {
    await caches.delete(CACHE);
    throw failure;
  }
  await cache.put(markerURL, new Response(JSON.stringify(BUILD), {
    headers: { 'Content-Type': 'application/json' },
  }));
  // The page bridge decides when to activate, after UI readiness/visibility.
}
self.addEventListener('install', (event) => event.waitUntil(installBuild()));

let repairPending = null;
function repairCurrentBuild() {
  if (repairPending) return repairPending;
  repairPending = (async () => {
    const cache = await caches.open(CACHE);
    // Repair eviction using only the current build's exact bytes. Never delete
    // surviving entries on failure, or substitute a newer deployment's assets.
    for (const resource of BUILD.resources) {
      const url = resourceURL(resource.path);
      if (await cache.match(url)) continue;
      const response = await fetch(url, { cache: 'reload', credentials: 'same-origin', redirect: 'error' });
      if (response.status !== 200 || response.type === 'opaque'
          || await hash(await response.clone().arrayBuffer()) !== resource.hash) {
        throw new Error('Cannot repair this exact offline version');
      }
      await cache.put(url, response);
    }
    await cache.put(markerURL, new Response(JSON.stringify(BUILD), {
      headers: { 'Content-Type': 'application/json' },
    }));
  })().finally(() => { repairPending = null; });
  return repairPending;
}

async function pinClient(id, version) {
  if (!id) return;
  const metadata = await caches.open(META);
  await metadata.put(clientURL(id), new Response(version));
}
async function versionFor(id) {
  if (!id) return BUILD.version;
  const metadata = await caches.open(META);
  const pinned = await metadata.match(clientURL(id));
  if (pinned) return pinned.text();
  await pinClient(id, BUILD.version);
  return BUILD.version;
}
async function activateBuild() {
  if (!(await isComplete(BUILD.version))) throw new Error('Incomplete offline build');
  const metadata = await caches.open(META);
  const previous = await metadata.match(activeURL);
  const previousVersion = previous ? await previous.text() : BUILD.version;
  const liveClients = (await self.clients.matchAll({ type: 'window', includeUncontrolled: true }))
    .filter((client) => inScope(new URL(client.url)));
  const retained = new Set([BUILD.version]);
  const liveKeys = new Set();
  for (const client of liveClients) {
    const key = clientURL(client.id);
    liveKeys.add(key);
    const existing = await metadata.match(key);
    const version = existing ? await existing.text() : previousVersion;
    await pinClient(client.id, version);
    retained.add(version);
  }
  await metadata.put(activeURL, new Response(BUILD.version));
  // Keep ALL versions pinned by living tabs. Cleanup happens only on activation,
  // so closing an old tab cannot race its final lazy-resource requests. Unused
  // old versions are reclaimed at the next activation, not on a timer/fetch.
  for (const request of await metadata.keys()) {
    if (request.url !== activeURL && !liveKeys.has(request.url)) await metadata.delete(request);
  }
  for (const name of await caches.keys()) {
    if (name.startsWith(CACHE_PREFIX) && !retained.has(name.slice(CACHE_PREFIX.length))) {
      await caches.delete(name);
    }
  }
  await self.clients.claim();
}
self.addEventListener('activate', (event) => event.waitUntil(activateBuild()));

async function serve(event, url, navigation) {
  // A navigation starts a new document at the current build. Existing documents
  // remain pinned to their build even after another tab accepts an update.
  const version = navigation ? BUILD.version : await versionFor(event.clientId);
  if (navigation) await pinClient(event.resultingClientId, version);
  const manifest = await manifestFor(version);
  const key = navigation ? resourceURL('index.html') : `${url.origin}${url.pathname}`;
  if (!manifest) return new Response('Offline version unavailable; reload when online.', { status: 503 });
  const known = manifest.resources.some((resource) => resourceURL(resource.path) === key);
  if (!known) return fetch(event.request); // Never runtime-cache arbitrary URLs.
  const cache = await caches.open(`${CACHE_PREFIX}${version}`);
  let response = await cache.match(key);
  if (!response && version === BUILD.version) {
    await repairCurrentBuild();
    response = await cache.match(key);
  }
  // An older tab must not receive newer bytes under the same resource URL.
  return response || new Response('Cached version unavailable. Reconnect and reload; if needed clear this site data.', { status: 503 });
}
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (!inScope(url)) return;
  const navigation = request.mode === 'navigate';
  if (navigation && url.pathname !== SCOPE.pathname && url.pathname !== resourceURL('index.html').replace(SCOPE.origin, '')) return;
  // Worker probes always go to the network, including when an old worker controls
  // the page; generated workers and source templates are not precache resources.
  if (url.pathname === new URL('shike-sw.js', SCOPE).pathname
      || url.pathname === new URL('sw.template.js', SCOPE).pathname) return;
  event.respondWith(serve(event, url, navigation).catch(() => new Response('Offline cache unavailable.', { status: 503 })));
});

self.addEventListener('message', (event) => {
  const source = event.source;
  if (!source?.id || !source.url || !inScope(new URL(source.url))) return;
  if (event.data?.type === 'SKIP_WAITING') {
    // The bridge accepts only fully installed releases, automatically or manually.
    event.waitUntil(self.skipWaiting());
  } else if (event.data?.type === 'SHIKE_STATUS' && event.ports?.[0]) {
    event.waitUntil((async () => {
      let ready = false;
      let version = BUILD.version;
      try {
        version = await versionFor(source.id);
        ready = await isComplete(version);
        if (!ready && version === BUILD.version) {
          await repairCurrentBuild();
          ready = await isComplete(version);
        }
      } catch (_) { /* quota/eviction must be reported, not an unhandled rejection */ }
      event.ports[0].postMessage({ type: 'SHIKE_STATUS', ready, version, activeVersion: BUILD.version });
    })());
  }
});
