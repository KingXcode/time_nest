/* Browser capabilities only. Flutter owns all UI and clock rendering. */
(() => {
  'use strict';
  const win = globalThis;
  const doc = win.document;
  const nav = win.navigator;
  const settingsKey = 'shike.settings.v1';
  const introKey = 'shike.intro.v1';
  const timerKey = 'shike.timer.v1';
  let audioContext = null;
  const base = new URL('./', doc.baseURI);
  const workerURL = new URL('shike-sw.js', base);
  const media = typeof win.matchMedia === 'function'
    ? win.matchMedia('(display-mode: standalone)') : null;
  const requestFullscreen = doc.documentElement.requestFullscreen
    || doc.documentElement.webkitRequestFullscreen;
  const exitFullscreen = doc.exitFullscreen || doc.webkitExitFullscreen;
  const fullscreenElement = () => doc.fullscreenElement || doc.webkitFullscreenElement;
  const state = {
    visible: doc.visibilityState !== 'hidden',
    resumeSerial: 0,
    storageAvailable: true,
    wakeSupported: win.isSecureContext === true && typeof nav.wakeLock?.request === 'function',
    wakeStatus: 'off',
    fullscreenSupported: typeof requestFullscreen === 'function'
      && (doc.fullscreenEnabled ?? doc.webkitFullscreenEnabled) !== false,
    fullscreen: Boolean(fullscreenElement()),
    fullscreenError: false,
    standalone: Boolean(nav.standalone || media?.matches),
    offlineStatus: 'checking',
    offlineCompleted: 0,
    offlineTotal: 0,
    updateAvailable: false,
    updateError: false,
    secureContext: win.isSecureContext === true,
  };
  if (!state.wakeSupported) state.wakeStatus = 'unsupported';
  let appReady = !win.shikeLoadingManaged;
  let disposed = false;
  let paused = false;
  let subscriber = null;
  const cleanups = [];
  const channels = new Set();
  let keepAwake = false;
  let wakeEpoch = 0;
  let wakePending = null;
  let wakeLock = null;
  let wakeReleaseListener = null;
  let registration = null;
  let activeUpdateAvailable = false;
  const storageFailures = new Set();
  let setupPending = null;
  let swEpoch = 0;
  let updatePending = false;
  const explicitlyCheckedWorkers = new WeakSet();
  let probeAbort = null;
  let acceptedWorker = null;
  let reloading = false;
  let readySerial = 0;
  const observedWorkers = new WeakSet();
  const observedRegistrations = new WeakSet();

  function patch(values) {
    if (disposed) return;
    let changed = false;
    for (const [key, value] of Object.entries(values)) {
      if (state[key] !== value) { state[key] = value; changed = true; }
    }
    if (changed && subscriber) {
      // A Dart callback failure must not break lifecycle cleanup or browser APIs.
      try { subscriber(); } catch (_) { /* subscriber owns its errors */ }
    }
  }
  function listen(target, event, callback) {
    target.addEventListener(event, callback);
    cleanups.push(() => target.removeEventListener(event, callback));
  }
  function storageRead(key) {
    try {
      const value = win.localStorage.getItem(key);
      patch({ storageAvailable: storageFailures.size === 0 });
      return value;
    } catch (_) {
      if (key === settingsKey || key === timerKey) storageFailures.add(key);
      patch({ storageAvailable: false });
      return null;
    }
  }
  function storageWrite(key, value) {
    if (disposed) return false;
    try {
      win.localStorage.setItem(key, value);
      storageFailures.delete(key);
      patch({ storageAvailable: storageFailures.size === 0 });
      return true;
    } catch (_) {
      if (key === settingsKey || key === timerKey) storageFailures.add(key);
      patch({ storageAvailable: false });
      return false;
    }
  }
  // Check the getter as well as getItem: both can throw in restricted contexts.
  storageRead(settingsKey);

  function releaseSentinel(lock) {
    try { return Promise.resolve(lock.release()).catch(() => {}); }
    catch (_) { return Promise.resolve(); }
  }
  function stopWake() {
    wakeEpoch += 1;
    if (wakeLock) {
      const lock = wakeLock;
      if (wakeReleaseListener) lock.removeEventListener('release', wakeReleaseListener);
      wakeLock = null;
      wakeReleaseListener = null;
      releaseSentinel(lock);
    }
    // Do not clear wakePending: even an invalidated request must settle before
    // another request starts. Its late sentinel will be released, never retained.
    patch({ wakeStatus: !keepAwake ? 'off' : state.wakeSupported ? 'released' : 'unsupported' });
  }
  function requestWake() {
    if (disposed || paused || !keepAwake || !state.visible) return;
    if (!state.wakeSupported) { patch({ wakeStatus: 'unsupported' }); return; }
    if (wakeLock || wakePending) return;
    const epoch = wakeEpoch;
    patch({ wakeStatus: 'requesting' });
    let request;
    try { request = nav.wakeLock.request('screen'); }
    catch (_) { patch({ wakeStatus: 'failed' }); return; }
    const pending = Promise.resolve(request).then(async (lock) => {
      if (disposed || paused || epoch !== wakeEpoch || !keepAwake || !state.visible) {
        await releaseSentinel(lock);
        return;
      }
      if (lock.released) { patch({ wakeStatus: 'released' }); return; }
      wakeLock = lock;
      wakeReleaseListener = () => {
        if (wakeLock !== lock) return;
        lock.removeEventListener('release', wakeReleaseListener);
        wakeLock = null;
        wakeReleaseListener = null;
        patch({ wakeStatus: keepAwake ? 'released' : 'off' });
        // System release is observable, not an automatic retry loop.
      };
      lock.addEventListener('release', wakeReleaseListener);
      patch({ wakeStatus: 'active' });
    }).catch(() => {
      if (epoch === wakeEpoch && keepAwake && state.visible && !paused) patch({ wakeStatus: 'failed' });
    }).finally(() => {
      if (wakePending === pending) wakePending = null;
      // A user/resume event invalidated a pending request, then re-enabled it.
      // Retry once for that new epoch, not on ordinary failure/system release.
      if (epoch !== wakeEpoch && !disposed && !paused && keepAwake && state.visible) requestWake();
    });
    wakePending = pending;
  }
  function setKeepAwake(value) {
    if (disposed) return;
    const enabled = value === true;
    if (keepAwake !== enabled) wakeEpoch += 1;
    keepAwake = enabled;
    if (enabled) requestWake(); else stopWake();
  }
  function performFullscreen(enterOnly) {
    if (disposed || !state.fullscreenSupported) return;
    if (enterOnly && fullscreenElement()) return;
    patch({ fullscreenError: false });
    try {
      const result = fullscreenElement()
        ? exitFullscreen.call(doc)
        : requestFullscreen.call(doc.documentElement);
      Promise.resolve(result).catch(() => patch({ fullscreenError: true }));
    } catch (_) { patch({ fullscreenError: true }); }
  }

  const sw = nav.serviceWorker;
  function ownsWorker(worker) { return worker?.scriptURL === workerURL.href; }
  function closeChannels() {
    readySerial += 1;
    for (const cancel of [...channels]) cancel();
  }
  function queryReady() {
    if (disposed || paused || !registration?.active || !ownsWorker(registration.active)) return;
    const serial = ++readySerial;
    if (typeof win.MessageChannel !== 'function') { patch({ offlineStatus: 'unavailable' }); return; }
    const channel = new win.MessageChannel();
    let finished = false;
    let timer;
    function finish(value) {
      if (finished) return;
      finished = true;
      win.clearTimeout(timer);
      channel.port1.close();
      channel.port2.close();
      channels.delete(cancel);
      if (value && serial === readySerial && !paused) patch({ offlineStatus: value });
    }
    const cancel = () => finish(null);
    channels.add(cancel);
    timer = win.setTimeout(() => finish('failed'), 4000);
    channel.port1.onmessage = (event) => {
      if (event.data?.type === 'SHIKE_STATUS') {
        activeUpdateAvailable = Boolean(event.data.version && event.data.activeVersion
          && event.data.version !== event.data.activeVersion);
        patch({ updateAvailable: activeUpdateAvailable || Boolean(registration?.waiting && ownsWorker(registration.waiting)) });
        finish(event.data.ready === true ? 'ready' : 'failed');
      }
    };
    try { registration.active.postMessage({ type: 'SHIKE_STATUS' }, [channel.port2]); }
    catch (_) { finish('failed'); }
  }
  function refreshRegistration() {
    if (disposed || paused || !registration) return;
    patch({ updateAvailable: activeUpdateAvailable || Boolean(registration.waiting && ownsWorker(registration.waiting)) });
    if (registration.installing) {
      if (updatePending) explicitlyCheckedWorkers.add(registration.installing);
      observeWorker(registration.installing);
    }
    if (registration.waiting) observeWorker(registration.waiting);
    if (registration.active) {
      observeWorker(registration.active);
      if (registration.active.state === 'activated') queryReady();
    }
  }
  function observeWorker(worker) {
    if (!ownsWorker(worker) || observedWorkers.has(worker)) return;
    observedWorkers.add(worker);
    listen(worker, 'statechange', () => {
      if (worker.state === 'redundant') {
        if (!registration?.active) patch({ offlineStatus: 'failed' });
        if (explicitlyCheckedWorkers.has(worker) || acceptedWorker === worker) patch({ updateError: true });
        if (acceptedWorker === worker) acceptedWorker = null;
      }
      refreshRegistration();
    });
  }
  function observeRegistration(reg) {
    registration = reg;
    if (!observedRegistrations.has(reg)) {
      observedRegistrations.add(reg);
      listen(reg, 'updatefound', refreshRegistration);
    }
    refreshRegistration();
  }
  function setupSW() {
    if (!appReady || disposed || paused) return Promise.resolve(false);
    if (setupPending) return setupPending;
    if (!state.secureContext || !sw || base.origin !== win.location.origin) {
      patch({ offlineStatus: 'unavailable' });
      return Promise.resolve(false);
    }
    const epoch = swEpoch;
    const cancelled = () => disposed || paused || epoch !== swEpoch;
    const task = (async () => {
      // An already installed worker can prove offline readiness without network.
      try {
        const existing = await sw.getRegistration(base.href);
        if (cancelled()) return false;
        if (existing?.scope === base.href && [existing.active, existing.waiting, existing.installing].some(ownsWorker)) {
          observeRegistration(existing);
        }
      } catch (_) { /* a fresh registration may still work */ }
      if (cancelled()) return false;
      probeAbort = typeof win.AbortController === 'function' ? new win.AbortController() : null;
      try {
        const response = await win.fetch(workerURL.href, {
          cache: 'no-store', credentials: 'same-origin', signal: probeAbort?.signal,
        });
        if (cancelled()) return false;
        if (!response.ok || !(await response.text()).startsWith('/* SHIKE_GENERATED_SERVICE_WORKER */')) {
          if (!registration?.active) patch({ offlineStatus: response.status === 404 || response.ok ? 'unavailable' : 'failed' });
          return false;
        }
        if (cancelled()) return false;
        const reg = await sw.register(workerURL.href, { scope: base.href, updateViaCache: 'none' });
        if (cancelled()) return false;
        observeRegistration(reg);
        return true;
      } catch (_) {
        if (!cancelled() && !registration?.active) patch({ offlineStatus: 'failed' });
        return false;
      } finally { probeAbort = null; }
    })().finally(() => {
      if (setupPending === task) setupPending = null;
      // BFCache can restore before an aborted probe settles. Resume once for
      // that lifecycle epoch, never retry ordinary network/install failures.
      if (!disposed && !paused && epoch !== swEpoch) setupSW();
    });
    setupPending = task;
    return task;
  }
  function checkForUpdate() {
    if (disposed || paused || updatePending) return;
    updatePending = true;
    const epoch = swEpoch;
    patch({ updateError: false });
    (async () => {
      if (!registration || ![registration.active, registration.waiting, registration.installing].some(ownsWorker)) {
        registration = null;
        if (!(await setupSW())) throw new Error('Release worker unavailable');
      }
      if (disposed || paused || epoch !== swEpoch) return;
      await registration.update();
      if (epoch === swEpoch) refreshRegistration();
    })().catch(() => {
      if (!paused && epoch === swEpoch) patch({ updateError: true });
    }).finally(() => { updatePending = false; });
  }
  function applyUpdate() {
    if (disposed || paused || acceptedWorker || reloading) return;
    if (!registration?.waiting) {
      if (activeUpdateAvailable && ownsWorker(registration?.active)) {
        reloading = true;
        win.location.reload();
      }
      return;
    }
    if (!ownsWorker(registration.waiting)) return;
    patch({ updateError: false });
    acceptedWorker = registration.waiting;
    try { acceptedWorker.postMessage({ type: 'SKIP_WAITING' }); }
    catch (_) { acceptedWorker = null; patch({ updateError: true }); }
  }
  function controllerChanged() {
    if (disposed || paused) return;
    // Initial clients.claim and another tab's acceptance MUST NOT reload us.
    if (acceptedWorker && sw.controller === acceptedWorker && !reloading) {
      reloading = true;
      win.location.reload();
      return;
    }
    refreshRegistration();
  }
  function visibilityChanged() {
    if (disposed) return;
    const visible = !paused && doc.visibilityState !== 'hidden';
    const resumed = visible && !state.visible;
    patch({ visible, ...(resumed ? { resumeSerial: state.resumeSerial + 1 } : {}) });
    if (!visible) stopWake(); else if (resumed) requestWake();
  }
  function pageHide() {
    if (disposed) return;
    paused = true;
    swEpoch += 1;
    patch({ visible: false });
    stopWake();
    probeAbort?.abort();
    closeChannels();
  }
  function pageShow() {
    if (disposed) return;
    paused = false;
    patch({ visible: doc.visibilityState !== 'hidden', resumeSerial: state.resumeSerial + 1 });
    requestWake();
    if (registration) refreshRegistration(); else setupSW();
    controllerChanged();
  }
  function dispose() {
    if (disposed) return;
    subscriber = null;
    keepAwake = false;
    stopWake();
    disposed = true;
    if (audioContext) Promise.resolve(audioContext.close()).catch(() => {});
    swEpoch += 1;
    probeAbort?.abort();
    closeChannels();
    for (const cleanup of cleanups.splice(0)) cleanup();
    acceptedWorker = null;
  }
  listen(doc, 'visibilitychange', visibilityChanged);
  listen(win, 'pagehide', pageHide);
  listen(win, 'pageshow', pageShow);
  listen(doc, 'fullscreenchange', () => patch({ fullscreen: Boolean(fullscreenElement()), fullscreenError: false }));
  listen(doc, 'webkitfullscreenchange', () => patch({ fullscreen: Boolean(fullscreenElement()), fullscreenError: false }));
  listen(doc, 'fullscreenerror', () => patch({ fullscreenError: true }));
  listen(doc, 'webkitfullscreenerror', () => patch({ fullscreenError: true }));
  if (media?.addEventListener) listen(media, 'change', () => patch({ standalone: Boolean(nav.standalone || media.matches) }));
  listen(doc, 'shike-app-ready', () => { appReady = true; setupSW(); });
  if (sw?.addEventListener) {
    listen(sw, 'controllerchange', controllerChanged);
    listen(sw, 'message', (event) => {
      const data = event.data;
      if (!ownsWorker(event.source) || data?.type !== 'SHIKE_PROGRESS'
          || !Number.isInteger(data.completed) || !Number.isInteger(data.total)
          || data.total <= 0 || data.completed < 0 || data.completed > data.total) return;
      if (state.offlineStatus !== 'ready') patch({ offlineCompleted: data.completed,
        offlineTotal: data.total, offlineStatus: 'checking' });
    });
  }
  win.shike = {
    readSettings: () => disposed ? null : storageRead(settingsKey),
    writeSettings: (value) => typeof value === 'string' && storageWrite(settingsKey, value),
    readTimer: () => disposed ? null : storageRead(timerKey),
    writeTimer: (value) => typeof value === 'string' && storageWrite(timerKey, value),
    armTimerSound: () => {
      if (disposed) return;
      try {
        const AudioContext = win.AudioContext || win.webkitAudioContext;
        if (!AudioContext) return;
        audioContext ||= new AudioContext();
        Promise.resolve(audioContext.resume()).catch(() => {});
      } catch (_) { /* Visual completion always remains available. */ }
    },
    playTimerSound: () => {
      if (disposed || !state.visible || audioContext?.state !== 'running') return;
      try {
        for (let i = 0; i < 3; i++) {
          const oscillator = audioContext.createOscillator();
          const gain = audioContext.createGain();
          const start = audioContext.currentTime + i * .32;
          oscillator.frequency.value = 660;
          gain.gain.setValueAtTime(0, start);
          gain.gain.linearRampToValueAtTime(.12, start + .02);
          gain.gain.exponentialRampToValueAtTime(.001, start + .24);
          oscillator.connect(gain); gain.connect(audioContext.destination);
          oscillator.onended = () => { oscillator.disconnect(); gain.disconnect(); };
          oscillator.start(start); oscillator.stop(start + .25);
        }
      } catch (_) { /* Unsupported audio must not affect the timer. */ }
    },
    readIntroSeen: () => !disposed && storageRead(introKey) === '1',
    markIntroSeen: () => storageWrite(introKey, '1'),
    getState: () => JSON.stringify(state),
    subscribe: (callback) => { if (!disposed) subscriber = typeof callback === 'function' ? callback : null; },
    unsubscribe: () => { subscriber = null; },
    setKeepAwake,
    startPresentation: () => {
      // Both calls happen in the original gesture stack; no await, no rotation.
      performFullscreen(true);
      setKeepAwake(true);
    },
    toggleFullscreen: () => performFullscreen(false),
    checkForUpdate,
    applyUpdate,
    dispose,
  };
  setupSW();
})();
