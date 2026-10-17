import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../web/platform.js', import.meta.url), 'utf8');
const settle = async () => { for (let i = 0; i < 6; i += 1) await new Promise(setImmediate); };
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
  removeEventListener(type, callback) { this.listeners.get(type)?.delete(callback); }
  emit(type, data = {}) { for (const callback of [...(this.listeners.get(type) || [])]) callback(data); }
  count() { return [...this.listeners.values()].reduce((sum, callbacks) => sum + callbacks.size, 0); }
}
class Sentinel extends Events {
  released = false;
  releases = 0;
  release() { this.releases += 1; this.released = true; this.emit('release'); return Promise.resolve(); }
}
class Channel {
  constructor() {
    this.port1 = { onmessage: null, close() { this.closed = true; } };
    this.port2 = {
      postMessage: (data) => this.port1.onmessage?.({ data }),
      close() { this.closed = true; },
    };
  }
}
function browser(options = {}) {
  const events = new Events();
  const document = new Events();
  const media = new Events();
  media.matches = false;
  document.baseURI = options.base || 'https://clock.test/clock/';
  document.visibilityState = 'visible';
  document.fullscreenEnabled = true;
  document.fullscreenElement = null;
  const calls = [];
  document.documentElement = { requestFullscreen() {
    calls.push('fullscreen');
    return options.fullscreenRequest?.() || Promise.resolve();
  } };
  document.exitFullscreen = () => { calls.push('exitFullscreen'); return Promise.resolve(); };
  const storage = new Map();
  const localStorage = {
    getItem(key) { if (options.readFails) throw new Error('storage blocked'); return storage.get(key) ?? null; },
    setItem(key, value) { if (options.writeFails || (options.settingsWriteFails && key === 'shike.settings.v1')) throw new Error('quota'); storage.set(key, value); },
  };
  const timers = new Map();
  let timerId = 0;
  const nav = {
    wakeLock: options.noWake ? undefined : { request(type) {
      assert.equal(type, 'screen');
      calls.push('wake');
      return options.wakeRequest?.() || Promise.resolve(new Sentinel());
    } },
  };
  const workerURL = new URL('shike-sw.js', new URL('./', document.baseURI)).href;
  function worker(state = 'activated') {
    return Object.assign(new Events(), {
      scriptURL: workerURL, state, messages: [],
      postMessage(message, ports) {
        this.messages.push(message);
        if (message.type === 'SHIKE_STATUS' && !options.noStatusReply) {
          ports[0].postMessage({ type: 'SHIKE_STATUS', ready: options.ready !== false,
            version: options.pageVersion || 'one', activeVersion: options.activeVersion || 'one' });
        }
        if (message.type === 'SKIP_WAITING' && options.postFails) throw new Error('post failed');
      },
    });
  }
  const active = options.noActive ? null : worker();
  const reg = Object.assign(new Events(), {
    scope: new URL('./', document.baseURI).href,
    active, waiting: null, installing: null,
    async update() { calls.push('update'); if (options.updateFails) throw new Error('offline'); },
  });
  const sw = Object.assign(new Events(), {
    controller: active,
    async getRegistration() { return options.existing ? reg : undefined; },
    async register(url, settings) {
      calls.push(['register', url, settings]);
      if (options.registerFails) throw new Error('registration denied');
      return reg;
    },
  });
  if (options.sw) nav.serviceWorker = sw;
  let reloads = 0;
  const context = {
    shikeLoadingManaged: options.loadingManaged,
    AudioContext: options.AudioContext,
    document, navigator: nav, localStorage, isSecureContext: options.secure !== false,
    location: { origin: 'https://clock.test', reload() { reloads += 1; } },
    URL, AbortController, MessageChannel: Channel,
    addEventListener: events.addEventListener.bind(events),
    removeEventListener: events.removeEventListener.bind(events),
    matchMedia: () => media,
    setTimeout: (callback) => { timers.set(++timerId, callback); return timerId; },
    clearTimeout: (id) => timers.delete(id),
    async fetch(url, init) {
      calls.push(['fetch', url, init]);
      if (options.fetchRequest) return options.fetchRequest(url, init);
      if (options.fetchFails) throw new Error('offline');
      return { ok: options.status ? options.status < 400 : true, status: options.status || 200,
        text: async () => options.body ?? '/* SHIKE_GENERATED_SERVICE_WORKER */\n' };
    },
  };
  if (options.storageGetterFails) Object.defineProperty(context, 'localStorage', { get() { throw new Error('denied'); } });
  context.window = context;
  vm.runInNewContext(source, context, { filename: 'platform.js' });
  return {
    api: context.shike, state: () => JSON.parse(context.shike.getState()), calls, storage, document,
    nav, events, media, timers, sw, reg, worker, reloads: () => reloads,
    hide() { document.visibilityState = 'hidden'; document.emit('visibilitychange'); },
    show() { document.visibilityState = 'visible'; document.emit('visibilitychange'); },
  };
}

test('public API and state are exact, string-based, and non-polling', async () => {
  const b = browser();
  assert.deepEqual(Object.keys(b.api).sort(), [
    'readSettings', 'writeSettings', 'readIntroSeen', 'markIntroSeen', 'getState', 'subscribe',
    'readTimer', 'writeTimer', 'armTimerSound', 'playTimerSound',
    'unsubscribe', 'setKeepAwake', 'startPresentation', 'toggleFullscreen', 'checkForUpdate', 'applyUpdate', 'dispose',
  ].sort());
  assert.deepEqual(Object.keys(b.state()).sort(), [
    'visible', 'resumeSerial', 'storageAvailable', 'wakeSupported', 'wakeStatus', 'fullscreenSupported',
    'fullscreen', 'fullscreenError', 'standalone', 'offlineStatus', 'offlineCompleted', 'offlineTotal', 'updateAvailable', 'updateError', 'secureContext',
  ].sort());
  assert.equal(b.state().wakeStatus, 'off');
  assert.equal(b.state().offlineStatus, 'unavailable');
  assert.equal(b.calls.length, 0);
  assert.equal(b.timers.size, 0);
  b.api.dispose();
});

test('intro/read success cannot mask settings write failure; a successful settings write recovers', () => {
  const options = { settingsWriteFails: true };
  const b = browser(options);
  assert.equal(b.api.writeSettings('settings'), false);
  assert.equal(b.api.markIntroSeen(), true);
  b.api.readIntroSeen(); b.api.readSettings();
  assert.equal(b.state().storageAvailable, false);
  options.settingsWriteFails = false;
  assert.equal(b.api.writeSettings('settings'), true);
  assert.equal(b.state().storageAvailable, true);
  b.api.dispose();
});

test('failed empty registration is registered again on explicit retry', async () => {
  const b = browser({ sw: true, noActive: true });
  await settle();
  assert.equal(b.calls.filter(c => c[0] === 'register').length, 1);
  b.api.checkForUpdate();
  await settle();
  assert.equal(b.calls.filter(c => c[0] === 'register').length, 2);
  b.api.dispose();
});

test('old tab keeps a confirmation action after another tab activates the update', async () => {
  const options = { sw: true };
  const b = browser(options);
  await settle();
  options.activeVersion = 'two';
  b.sw.emit('controllerchange');
  await settle();
  assert.equal(b.state().updateAvailable, true);
  assert.equal(b.reloads(), 0);
  b.api.applyUpdate(); b.api.applyUpdate();
  assert.equal(b.reloads(), 1);
  b.api.dispose();
});

test('settings/intro use their own versioned keys and never parse settings JSON', () => {
  const b = browser();
  assert.equal(b.api.readSettings(), null);
  assert.equal(b.api.readIntroSeen(), false);
  assert.equal(b.api.writeSettings('{not-json'), true);
  assert.equal(b.api.readSettings(), '{not-json');
  assert.equal(b.storage.get('shike.settings.v1'), '{not-json');
  assert.equal(b.api.markIntroSeen(), true);
  assert.equal(b.storage.get('shike.intro.v1'), '1');
  assert.equal(b.api.readIntroSeen(), true);
  assert.equal(b.api.writeSettings({}), false);
  b.api.dispose();
});

for (const failure of ['readFails', 'writeFails', 'storageGetterFails']) {
  test(`storage ${failure} is contained and reports unavailable`, () => {
    const b = browser({ [failure]: true });
    if (failure !== 'writeFails') {
      assert.equal(b.state().storageAvailable, false);
      assert.equal(b.api.readSettings(), null);
      assert.equal(b.api.readIntroSeen(), false);
    } else assert.equal(b.api.writeSettings('test'), false);
    assert.equal(b.state().storageAvailable, false);
    b.api.dispose();
  });
}

test('only one zero-argument subscriber, unsubscribe, and no duplicate hidden notification', () => {
  const b = browser();
  let first = 0, second = 0;
  b.api.subscribe(() => { first += 1; });
  b.api.subscribe((...args) => { assert.equal(args.length, 0); second += 1; });
  b.hide();
  b.hide();
  assert.equal(first, 0);
  assert.equal(second, 1); // visible=false; unrequested wake remains off
  b.api.unsubscribe();
  b.show();
  assert.equal(second, 1);
  b.api.dispose();
});

test('startPresentation invokes both APIs synchronously in the gesture stack', async () => {
  const fullscreen = deferred();
  const wake = deferred();
  const b = browser({ fullscreenRequest: () => fullscreen.promise, wakeRequest: () => wake.promise });
  b.api.startPresentation();
  assert.deepEqual(b.calls, ['fullscreen', 'wake']);
  assert.equal(b.state().wakeStatus, 'requesting');
  fullscreen.reject(new Error('not allowed'));
  wake.resolve(new Sentinel());
  await settle();
  assert.equal(b.state().fullscreenError, true);
  assert.equal(b.state().wakeStatus, 'active');
  b.api.dispose();
});

test('wake denial and system release are visible and do not auto-retry', async () => {
  const denied = browser({ wakeRequest: () => Promise.reject(new Error('battery saver')) });
  denied.api.setKeepAwake(true);
  await settle();
  assert.equal(denied.state().wakeStatus, 'failed');
  assert.deepEqual(denied.calls, ['wake']);
  denied.api.setKeepAwake(false);
  assert.equal(denied.state().wakeStatus, 'off');
  denied.api.dispose();
  const lock = new Sentinel();
  const b = browser({ wakeRequest: () => Promise.resolve(lock) });
  b.api.setKeepAwake(true);
  await settle();
  await lock.release();
  await settle();
  assert.equal(b.state().wakeStatus, 'released');
  assert.deepEqual(b.calls, ['wake']);
  b.api.dispose();
});

test('hidden pending wake is released, and resumed preference requests once after settling', async () => {
  const first = deferred();
  const stale = new Sentinel();
  let requests = 0;
  const b = browser({ wakeRequest: () => ++requests === 1 ? first.promise : Promise.resolve(new Sentinel()) });
  b.api.setKeepAwake(true);
  b.api.setKeepAwake(true);
  b.hide();
  b.show();
  b.events.emit('pageshow', { persisted: true });
  assert.equal(requests, 1);
  first.resolve(stale);
  await settle();
  assert.equal(stale.releases, 1);
  assert.equal(requests, 2);
  assert.equal(b.state().wakeStatus, 'active');
  assert.equal(b.state().resumeSerial, 2);
  b.api.dispose();
});

for (const action of ['disable', 'dispose', 'pagehide']) {
  test(`late wake fulfillment after ${action} cannot retain the sentinel`, async () => {
    const pending = deferred();
    const lock = new Sentinel();
    const b = browser({ wakeRequest: () => pending.promise });
    b.api.setKeepAwake(true);
    if (action === 'disable') b.api.setKeepAwake(false);
    else if (action === 'dispose') b.api.dispose();
    else b.events.emit('pagehide', { persisted: true });
    pending.resolve(lock);
    await settle();
    assert.equal(lock.releases, 1);
    assert.notEqual(b.state().wakeStatus, 'active');
    assert.deepEqual(b.calls, ['wake']);
    b.api.dispose();
  });
}

test('visibility and BFCache lifecycle restores authorized wake and cleans all listeners', async () => {
  const b = browser();
  b.api.setKeepAwake(true);
  await settle();
  b.events.emit('pagehide', { persisted: true });
  assert.equal(b.state().visible, false);
  assert.equal(b.state().wakeStatus, 'released');
  b.events.emit('pageshow', { persisted: true });
  await settle();
  assert.equal(b.state().resumeSerial, 1);
  assert.equal(b.state().wakeStatus, 'active');
  b.api.dispose();
  assert.equal(b.events.count() + b.document.count() + b.media.count(), 0);
  const before = b.api.getState();
  b.events.emit('pageshow');
  assert.equal(b.api.getState(), before);
});

test('unsupported and insecure wake degrade; false always means off', () => {
  for (const option of [{ noWake: true }, { secure: false }]) {
    const b = browser(option);
    b.api.setKeepAwake(true);
    assert.equal(b.state().wakeStatus, 'unsupported');
    assert.equal(b.state().wakeSupported, false);
    b.api.setKeepAwake(false);
    assert.equal(b.state().wakeStatus, 'off');
    b.api.dispose();
  }
});

test('fullscreen change/error and standalone change reflect actual browser state', async () => {
  const b = browser({ fullscreenRequest: () => { throw new Error('denied synchronously'); } });
  b.api.toggleFullscreen();
  assert.equal(b.state().fullscreenError, true);
  b.document.fullscreenElement = b.document.documentElement;
  b.document.emit('fullscreenchange');
  assert.equal(b.state().fullscreen, true);
  assert.equal(b.state().fullscreenError, false);
  b.api.toggleFullscreen();
  assert.equal(b.calls.at(-1), 'exitFullscreen');
  b.document.emit('fullscreenerror');
  assert.equal(b.state().fullscreenError, true);
  b.media.matches = true;
  b.media.emit('change');
  assert.equal(b.state().standalone, true);
  b.api.dispose();
});

test('debug 404 and fallback HTML never register a worker or crash', async () => {
  for (const option of [{ status: 404 }, { body: '<!doctype html>debug flutter_bootstrap' }]) {
    const b = browser({ sw: true, ...option });
    await settle();
    assert.equal(b.state().offlineStatus, 'unavailable');
    assert.equal(b.calls.some((call) => call[0] === 'register'), false);
    assert.equal(b.state().updateError, false);
    b.api.dispose();
  }
});

test('release worker uses document base directory and must confirm complete cache readiness', async () => {
  const b = browser({ sw: true, base: 'https://clock.test/deep/clock/index.html' });
  await settle();
  const registration = b.calls.find((call) => call[0] === 'register');
  assert.equal(registration[1], 'https://clock.test/deep/clock/shike-sw.js');
  assert.equal(registration[2].scope, 'https://clock.test/deep/clock/');
  assert.equal(registration[2].updateViaCache, 'none');
  assert.equal(b.state().offlineStatus, 'ready');
  assert.equal(b.timers.size, 0);
  assert.equal(b.reg.active.messages[0].type, 'SHIKE_STATUS');
  b.api.dispose();
  const incomplete = browser({ sw: true, ready: false });
  await settle();
  assert.equal(incomplete.state().offlineStatus, 'failed');
  incomplete.api.dispose();
});

test('installing is checking, installed+activated is ready; claim alone never reloads', async () => {
  const b = browser({ sw: true, noActive: true });
  b.reg.installing = b.worker('installing');
  await settle();
  assert.equal(b.state().offlineStatus, 'checking');
  const worker = b.reg.installing;
  b.reg.active = worker;
  b.reg.installing = null;
  worker.state = 'activated';
  worker.emit('statechange');
  b.sw.controller = worker;
  b.sw.emit('controllerchange');
  await settle();
  assert.equal(b.state().offlineStatus, 'ready');
  assert.equal(b.reloads(), 0);
  b.api.dispose();
});

test('only explicit applyUpdate sends skipWaiting and reloads accepting tab once', async () => {
  const b = browser({ sw: true });
  await settle();
  const waiting = b.worker('installed');
  b.reg.waiting = waiting;
  b.reg.emit('updatefound');
  assert.equal(b.state().updateAvailable, true);
  assert.equal(waiting.messages.length, 0);
  const other = b.worker();
  b.sw.controller = other;
  b.sw.emit('controllerchange');
  assert.equal(b.reloads(), 0);
  b.api.applyUpdate();
  assert.equal(waiting.messages[0].type, 'SKIP_WAITING');
  b.api.applyUpdate();
  assert.equal(waiting.messages.length, 1);
  b.sw.controller = waiting;
  b.sw.emit('controllerchange');
  b.sw.emit('controllerchange');
  assert.equal(b.reloads(), 1);
  b.api.dispose();
});

test('update check is explicitly requested, deduplicated and failures reported without polling', async () => {
  const b = browser({ sw: true, updateFails: true });
  await settle();
  assert.equal(b.calls.includes('update'), false);
  b.api.checkForUpdate();
  b.api.checkForUpdate();
  await settle();
  assert.equal(b.calls.filter((call) => call === 'update').length, 1);
  assert.equal(b.state().updateError, true);
  assert.equal(b.state().offlineStatus, 'ready');
  b.api.dispose();
});

test('existing complete installation remains ready offline; failed fresh install does not', async () => {
  const existing = browser({ sw: true, existing: true, fetchFails: true });
  const fresh = browser({ sw: true, fetchFails: true });
  await settle();
  assert.equal(existing.state().offlineStatus, 'ready');
  assert.equal(fresh.state().offlineStatus, 'failed');
  existing.api.dispose(); fresh.api.dispose();
});

test('status timeout reports failure and pagehide/dispose cancel every pending channel', async () => {
  const b = browser({ sw: true, noStatusReply: true });
  await settle();
  assert.equal(b.state().offlineStatus, 'checking');
  for (const callback of [...b.timers.values()]) callback();
  assert.equal(b.state().offlineStatus, 'failed');
  assert.equal(b.timers.size, 0);
  b.sw.emit('controllerchange');
  assert.equal(b.timers.size, 1);
  b.events.emit('pagehide');
  assert.equal(b.timers.size, 0);
  b.events.emit('pageshow');
  b.api.dispose();
  assert.equal(b.timers.size, 0);
  assert.equal(b.sw.count() + b.reg.count() + b.reg.active.count(), 0);
});

test('offline downloads wait for usable UI and accept only owned progress messages', async () => {
  const b = browser({ sw: true, loadingManaged: true, noActive: true });
  await settle();
  assert.equal(b.calls.length, 0);
  b.events.emit('pageshow'); await settle();
  assert.equal(b.calls.length, 0);
  b.document.emit('shike-app-ready'); await settle();
  assert.equal(b.calls.filter(c => c[0] === 'register').length, 1);
  b.sw.emit('message', { source: { scriptURL: 'https://other.test/sw.js' }, data: { type: 'SHIKE_PROGRESS', completed: 2, total: 5 } });
  assert.equal(b.state().offlineTotal, 0);
  b.sw.emit('message', { source: b.worker(), data: { type: 'SHIKE_PROGRESS', completed: 2, total: 5 } });
  assert.equal(b.state().offlineCompleted, 2);
  b.sw.emit('message', { source: b.worker(), data: { type: 'SHIKE_PROGRESS', completed: 9, total: 5 } });
  assert.equal(b.state().offlineCompleted, 2);
  b.api.dispose();
});

test('timer storage is independent and missing sound APIs never throw', () => {
  const b = browser();
  b.api.writeSettings('settings'); b.api.writeTimer('timer');
  assert.equal(b.api.readSettings(), 'settings');
  assert.equal(b.api.readTimer(), 'timer');
  b.api.armTimerSound(); b.api.playTimerSound();
  b.api.dispose();
});

test('completion sound requires a gesture-enabled context and a visible page', () => {
  let starts = 0, closes = 0;
  class Audio {
    state = 'suspended'; currentTime = 0; destination = {};
    resume() { this.state = 'running'; return Promise.resolve(); }
    close() { closes++; return Promise.resolve(); }
    createOscillator() { return { frequency: {}, connect() {}, disconnect() {}, start() { starts++; }, stop() {} }; }
    createGain() { return { gain: { setValueAtTime() {}, linearRampToValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {}, disconnect() {} }; }
  }
  const b = browser({ AudioContext: Audio });
  b.api.playTimerSound(); assert.equal(starts, 0);
  b.api.armTimerSound(); b.api.playTimerSound(); assert.equal(starts, 3);
  b.hide(); b.api.playTimerSound(); assert.equal(starts, 3);
  b.api.dispose(); assert.equal(closes, 1);
});
