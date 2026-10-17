import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../web/viewport.js', import.meta.url), 'utf8');
class Events {
  listeners = new Map();
  addEventListener(name, callback) {
    if (!this.listeners.has(name)) this.listeners.set(name, []);
    this.listeners.get(name).push(callback);
  }
  emit(name) { for (const callback of this.listeners.get(name) || []) callback(); }
}
function browser({ noViewport = false, hidden = false } = {}) {
  const events = new Events();
  const document = new Events();
  document.visibilityState = hidden ? 'hidden' : 'visible';
  const values = new Map();
  let writes = 0;
  const host = { style: {
    getPropertyValue: key => values.get(key) || '',
    setProperty: (key, value) => { writes++; values.set(key, value); },
  } };
  document.getElementById = id => id === 'app' ? host : null;
  const viewport = Object.assign(new Events(), {
    width: 390, height: 740, offsetLeft: 0, offsetTop: 24, scale: 1,
  });
  const frames = new Map(), timers = new Map();
  let id = 0;
  const context = {
    document, visualViewport: noViewport ? undefined : viewport,
    innerWidth: 390, innerHeight: 844,
    addEventListener: events.addEventListener.bind(events),
    requestAnimationFrame: callback => { frames.set(++id, callback); return id; },
    cancelAnimationFrame: id => frames.delete(id),
    setTimeout: (callback, delay) => { timers.set(++id, { callback, delay }); return id; },
    clearTimeout: id => timers.delete(id),
  };
  vm.runInNewContext(source, context, { filename: 'viewport.js' });
  return {
    context, document, events, viewport, frames, timers,
    get: name => values.get(`--app-viewport-${name}`), writes: () => writes,
    frame() {
      for (const [id, callback] of [...frames]) { frames.delete(id); callback(); }
    },
    timer(delay) {
      for (const [id, timer] of [...timers]) {
        if (timer.delay === delay) { timers.delete(id); timer.callback(); }
      }
    },
  };
}

test('initial bounds use the visible viewport before Flutter loads, not a taller layout viewport', () => {
  const b = browser();
  assert.equal(b.get('height'), '740px');
  assert.equal(b.get('width'), '390px');
  assert.equal(b.get('top'), '24px');
  assert.equal(b.get('left'), '0px');
  assert.equal(b.frames.size + b.timers.size, 0);
});

test('visual resize and scroll update bounds without a window resize or a rotation', () => {
  const b = browser();
  b.viewport.height = 780; b.viewport.offsetTop = 0;
  b.viewport.emit('resize'); b.viewport.emit('scroll');
  assert.equal(b.frames.size, 1, 'coalesce event bursts');
  b.frame();
  assert.equal(b.get('height'), '780px');
  assert.equal(b.get('top'), '0px');
  const writes = b.writes();
  b.viewport.emit('resize'); b.frame();
  assert.equal(b.writes(), writes, 'unchanged bounds must not cause canvas resize');
});

test('startup and rotation settle intermediate dimensions with bounded checks', () => {
  const b = browser();
  b.document.emit('shike-app-ready'); b.frame();
  b.viewport.height = 844; b.viewport.offsetTop = 0;
  b.timer(100); b.frame();
  assert.equal(b.get('height'), '844px');
  b.events.emit('orientationchange');
  assert.equal(b.timers.size, 2, 'replace the old settling checks');
  b.viewport.width = 844; b.viewport.height = 390;
  b.timer(100); b.frame(); b.timer(500); b.frame();
  assert.equal(b.get('width'), '844px');
  assert.equal(b.get('height'), '390px');
  assert.equal(b.frames.size + b.timers.size, 0);
});

test('BFCache and background transitions cancel pending work and remeasure on return', () => {
  const b = browser();
  b.document.emit('shike-app-ready');
  b.events.emit('pagehide');
  assert.equal(b.frames.size + b.timers.size, 0);
  b.viewport.height = 700; b.viewport.emit('resize');
  assert.equal(b.frames.size, 0);
  b.events.emit('pageshow'); b.frame();
  assert.equal(b.get('height'), '700px');
  b.document.visibilityState = 'hidden'; b.document.emit('visibilitychange');
  assert.equal(b.frames.size + b.timers.size, 0);
  b.viewport.height = 740;
  b.document.visibilityState = 'visible'; b.document.emit('visibilitychange'); b.frame();
  assert.equal(b.get('height'), '740px');
});

test('pinch zoom preserves the layout until normal scale is restored', () => {
  const b = browser();
  b.viewport.scale = 2; b.viewport.width = 195; b.viewport.height = 370;
  b.viewport.emit('resize'); b.frame();
  assert.equal(b.get('width'), '390px');
  assert.equal(b.get('height'), '740px');
  b.viewport.scale = 1; b.viewport.width = 390; b.viewport.height = 844;
  b.viewport.emit('resize'); b.frame();
  assert.equal(b.get('height'), '844px');
});

test('legacy browsers use window dimensions; transient zero measurements cannot erase the view', () => {
  const b = browser({ noViewport: true });
  assert.equal(b.get('height'), '844px');
  b.context.innerHeight = 0; b.events.emit('resize'); b.frame();
  assert.equal(b.get('height'), '844px');
  b.context.innerWidth = 844; b.context.innerHeight = 390;
  b.events.emit('resize'); b.frame();
  assert.equal(b.get('width'), '844px');
  assert.equal(b.get('height'), '390px');
});

test('viewport synchronization is loaded before the engine and safe insets remain in CSS', async () => {
  const html = await readFile(new URL('../web/index.html', import.meta.url), 'utf8');
  assert.ok(html.indexOf('src="viewport.js"') < html.indexOf('src="flutter_bootstrap.js"'));
  for (const edge of ['top', 'bottom', 'left', 'right']) assert.ok(html.includes(`env(safe-area-inset-${edge}, 0px)`));
});
