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
function browser({
  noViewport = false, hidden = false, installed = false, legacyStandalone = false,
  noMatchMedia = false, insets = {},
} = {}) {
  const events = new Events();
  const document = new Events();
  document.visibilityState = hidden ? 'hidden' : 'visible';
  const values = new Map();
  let writes = 0;
  const host = { style: {
    getPropertyValue: key => values.get(key) || '',
    setProperty: (key, value) => { writes++; values.set(key, value); },
  } };
  const layout = { width: 390, height: 844 };
  const probe = { getBoundingClientRect: () => layout };
  document.getElementById = id => id === 'app' ? host : id === 'viewport-probe' ? probe : null;
  const displayMode = Object.assign(new Events(), { matches: installed });
  const viewport = Object.assign(new Events(), {
    width: 390, height: 740, offsetLeft: 0, offsetTop: 24, scale: 1,
  });
  const frames = new Map(), timers = new Map();
  let observeResize;
  let id = 0;
  const context = {
    document, visualViewport: noViewport ? undefined : viewport,
    innerWidth: 390, innerHeight: 844,
    navigator: { standalone: legacyStandalone },
    matchMedia: noMatchMedia ? undefined : () => displayMode,
    getComputedStyle: () => ({
      getPropertyValue: key => `${insets[key.replace('padding-', '')] || 0}px`,
    }),
    ResizeObserver: class {
      constructor(callback) { observeResize = callback; }
      observe(element) { assert.equal(element, probe); }
    },
    addEventListener: events.addEventListener.bind(events),
    requestAnimationFrame: callback => { frames.set(++id, callback); return id; },
    cancelAnimationFrame: id => frames.delete(id),
    setTimeout: (callback, delay) => { timers.set(++id, { callback, delay }); return id; },
    clearTimeout: id => timers.delete(id),
  };
  vm.runInNewContext(source, context, { filename: 'viewport.js' });
  return {
    context, document, events, viewport, frames, timers, layout, insets, displayMode,
    resizeProbe: () => observeResize(),
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

test('standalone uses the full CSS viewport and removes safe areas only once', () => {
  const b = browser({ installed: true, insets: { top: 47, bottom: 34 } });
  b.viewport.height = 763; // WebKit may already exclude the 81px safe areas.
  b.context.innerHeight = 763; // innerHeight is not a reliable replacement either.
  b.viewport.offsetTop = 0;
  b.viewport.emit('resize'); b.frame();
  assert.equal(b.get('top'), '47px');
  assert.equal(b.get('height'), '797px');
  assert.equal(Number.parseFloat(b.get('top')) + Number.parseFloat(b.get('height')), 844);
  assert.equal(b.get('width'), '390px');
});

test('late safe-area changes resize the host without a window resize', () => {
  const b = browser({ installed: true });
  assert.equal(b.get('height'), '844px');
  Object.assign(b.insets, { top: 47, bottom: 34 });
  b.resizeProbe(); b.frame();
  assert.equal(b.get('top'), '47px');
  assert.equal(b.get('height'), '797px');
  const writes = b.writes();
  b.resizeProbe(); b.frame();
  assert.equal(b.writes(), writes, 'independent probe observation must not create a resize loop');
});

test('standalone keyboard intersects safe bounds, then restores with the same focused field', () => {
  const b = browser({ installed: true, insets: { top: 47, bottom: 34 } });
  b.document.activeElement = { shadowRoot: { activeElement: { tagName: 'INPUT', type: 'search' } } };
  b.viewport.height = 510; b.viewport.offsetTop = 0;
  b.document.emit('focusin'); b.frame();
  assert.equal(b.get('top'), '47px');
  assert.equal(b.get('height'), '463px', 'no extra home-indicator gutter above the keyboard');
  b.viewport.offsetTop = 60; b.viewport.height = 450;
  b.viewport.emit('scroll'); b.frame();
  assert.equal(b.get('top'), '60px', 'do not add the notch inset to an already panned viewport');
  assert.equal(b.get('height'), '450px');
  b.viewport.offsetTop = 0; b.viewport.height = 763;
  b.viewport.emit('resize'); b.frame();
  assert.equal(b.get('top'), '47px');
  assert.equal(b.get('height'), '797px', 'keyboard dismissal need not blur the field');
});

test('hardware keyboards, readonly inputs and non-editable focus do not shorten standalone', () => {
  const b = browser({ installed: true, insets: { top: 47, bottom: 34 } });
  b.viewport.height = 763; b.viewport.offsetTop = 0;
  b.document.activeElement = { tagName: 'TEXTAREA' };
  b.document.emit('focusin'); b.frame();
  assert.equal(b.get('height'), '797px');
  b.viewport.height = 510;
  for (const element of [
    { tagName: 'INPUT', type: 'checkbox' },
    { tagName: 'INPUT', type: 'text', readOnly: true },
    { tagName: 'TEXTAREA', disabled: true },
    { tagName: 'BUTTON' },
  ]) {
    b.document.activeElement = element; b.document.emit('focusin'); b.frame();
    assert.equal(b.get('height'), '797px');
  }
});

test('rapid blur and refocus cannot cache a shrunken standalone viewport', () => {
  const b = browser({ installed: true, insets: { top: 47, bottom: 34 } });
  b.viewport.height = 510; b.viewport.offsetTop = 0;
  b.document.activeElement = { isContentEditable: true };
  b.document.emit('focusin'); b.frame();
  assert.equal(b.get('height'), '463px');
  b.document.activeElement = null; b.document.emit('focusout'); b.frame();
  assert.equal(b.get('height'), '797px');
  b.document.activeElement = { isContentEditable: true };
  b.document.emit('focusin'); b.frame();
  assert.equal(b.get('height'), '463px');
  b.viewport.height = 763; b.viewport.emit('resize'); b.frame();
  assert.equal(b.get('height'), '797px');
});

test('standalone rotates into landscape side safe areas and survives repeated resume', () => {
  const b = browser({ installed: true, insets: { top: 47, bottom: 34 } });
  Object.assign(b.layout, { width: 844, height: 390 });
  Object.assign(b.insets, { top: 0, right: 47, bottom: 21, left: 47 });
  Object.assign(b.viewport, { width: 750, height: 369, offsetTop: 0, offsetLeft: 0 });
  b.events.emit('orientationchange'); b.frame();
  assert.equal(b.get('left'), '47px');
  assert.equal(b.get('top'), '0px');
  assert.equal(b.get('width'), '750px');
  assert.equal(b.get('height'), '390px');
  b.document.activeElement = { tagName: 'INPUT', type: 'text' };
  b.viewport.height = 210; b.viewport.emit('resize'); b.frame();
  assert.equal(b.get('left'), '47px');
  assert.equal(b.get('width'), '750px', 'a vertical keyboard must not double-subtract side insets');
  assert.equal(b.get('height'), '210px');
  b.viewport.height = 369; b.viewport.emit('resize'); b.frame();
  assert.equal(b.get('height'), '390px');
  b.document.activeElement = null;
  for (let n = 0; n < 3; n++) {
    b.document.visibilityState = 'hidden'; b.document.emit('visibilitychange');
    b.events.emit('pagehide');
    assert.equal(b.frames.size + b.timers.size, 0);
    b.document.visibilityState = 'visible'; b.events.emit('pageshow'); b.frame();
    b.timer(100); b.frame(); b.timer(500); b.frame();
    assert.equal(b.get('height'), '390px');
    assert.equal(b.frames.size + b.timers.size, 0);
  }
});

test('legacy standalone, no visual viewport and no safe insets remain supported', () => {
  for (const options of [
    { installed: true, noViewport: true },
    { legacyStandalone: true, noMatchMedia: true },
  ]) {
    const b = browser(options);
    assert.equal(b.get('height'), '844px');
    assert.equal(b.get('top'), '0px');
    b.layout.height = 0; b.events.emit('resize'); b.frame();
    assert.equal(b.get('height'), '844px', 'ignore invalid transitional CSS bounds');
  }
});

test('standalone keeps its layout through pinch zoom, and display-mode changes resync', () => {
  const b = browser({ installed: true, insets: { top: 47, bottom: 34 } });
  b.viewport.scale = 2; b.viewport.height = 381.5; b.viewport.width = 195;
  b.viewport.emit('resize'); b.frame();
  assert.equal(b.get('height'), '797px');
  b.viewport.scale = 1; b.viewport.height = 740; b.viewport.width = 390;
  b.viewport.offsetTop = 24;
  b.displayMode.matches = false; b.displayMode.emit('change'); b.frame();
  assert.equal(b.get('height'), '693px', 'regular tab keeps visible top/side bounds but extends through bottom inset');
  assert.equal(b.get('top'), '71px');
  b.displayMode.matches = true; b.displayMode.emit('change'); b.frame();
  assert.equal(b.get('height'), '797px');
  assert.equal(b.get('top'), '47px');
});

test('viewport synchronization is loaded before the engine and safe insets remain in CSS', async () => {
  const html = await readFile(new URL('../web/index.html', import.meta.url), 'utf8');
  assert.ok(html.indexOf('src="viewport.js"') < html.indexOf('src="flutter_bootstrap.js"'));
  for (const edge of ['top', 'bottom', 'left', 'right']) assert.ok(html.includes(`env(safe-area-inset-${edge}, 0px)`));
  assert.match(html, /id="viewport-probe" aria-hidden="true"/);
  assert.match(html, /width: 100vw; height: 100vh/);
  assert.match(html, /height: var\(--app-viewport-height, calc\(100vh/);
  assert.doesNotMatch(html, /calc\(var\(--app-viewport-(height|width|top|left)/,
    'final JS bounds must not receive the safe-area insets twice');
});

test('edge-to-edge host publishes bottom control inset without adding a permanent gutter', () => {
  const b = browser({ installed: true, insets: { top: 47, bottom: 34 } });
  assert.equal(b.get('height'), '797px');
  assert.equal(b.context.shikeViewport.getBottomInset(), 34);
  let changes = 0;
  const listener = () => changes++;
  b.context.shikeViewport.subscribe(listener);
  b.context.shikeViewport.subscribe(listener);
  b.viewport.height = 510; b.viewport.offsetTop = 0;
  b.document.activeElement = { tagName: 'INPUT', type: 'search' };
  b.document.emit('focusin'); b.frame();
  assert.equal(b.context.shikeViewport.getBottomInset(), 0);
  assert.equal(changes, 1);
  b.viewport.height = 763; b.viewport.emit('resize'); b.frame();
  assert.equal(b.context.shikeViewport.getBottomInset(), 34);
  assert.equal(b.get('height'), '797px');
  assert.equal(changes, 2);
  b.context.shikeViewport.unsubscribe(listener);
  b.document.activeElement = null;
  b.insets.bottom = 21; b.resizeProbe(); b.frame();
  assert.equal(changes, 2);
  assert.equal(b.context.shikeViewport.getBottomInset(), 21);
});

test('host CSS does not reserve bottom space before the viewport script runs', async () => {
  const html = await readFile(new URL('../web/index.html', import.meta.url), 'utf8');
  assert.doesNotMatch(html, /height:[^;]*- env\(safe-area-inset-bottom/);
});

test('regular-tab hardware keyboard focus keeps bottom inset despite browser chrome', () => {
  const b = browser({ insets: { top: 47, bottom: 34 } });
  assert.equal(b.viewport.height, 740);
  assert.equal(b.layout.height, 844);
  assert.equal(b.context.shikeViewport.getBottomInset(), 34);
  b.document.activeElement = { tagName: 'INPUT', type: 'text' };
  b.document.emit('focusin'); b.frame();
  assert.equal(b.context.shikeViewport.getBottomInset(), 34);
  b.viewport.height = 450; b.viewport.emit('resize'); b.frame();
  assert.equal(b.context.shikeViewport.getBottomInset(), 0);
  b.viewport.height = 740; b.viewport.emit('resize'); b.frame();
  assert.equal(b.context.shikeViewport.getBottomInset(), 34);
});

test('regular-tab width rotation resets the focused baseline instead of inferring a keyboard', () => {
  const b = browser({ insets: { top: 47, bottom: 34 } });
  b.document.activeElement = { tagName: 'TEXTAREA' };
  Object.assign(b.viewport, { width: 844, height: 390, offsetTop: 0 });
  Object.assign(b.insets, { top: 0, bottom: 21 });
  b.events.emit('orientationchange'); b.frame();
  assert.equal(b.context.shikeViewport.getBottomInset(), 21);
  b.viewport.height = 210; b.viewport.emit('resize'); b.frame();
  assert.equal(b.context.shikeViewport.getBottomInset(), 0);
  b.viewport.height = 390; b.viewport.emit('resize'); b.frame();
  assert.equal(b.context.shikeViewport.getBottomInset(), 21);
});
