// The embedded Flutter view observes #app. Publish its final safe bounds before
// the engine measures its first frame. Top/side insets are removed here; bottom
// content is edge-to-edge and Flutter receives its control/scroll inset below.
(() => {
  'use strict';
  const win = globalThis;
  const doc = win.document;
  const host = doc.getElementById('app');
  if (!host) return;
  const viewport = win.visualViewport;
  const probe = doc.getElementById('viewport-probe');
  const standalone = win.matchMedia?.('(display-mode: standalone)');
  let paused = false;
  let frame = null;
  let settling = [];
  let bottomInset = 0;
  let regularBaseline = null;
  const insetListeners = new Set();
  win.shikeViewport = Object.freeze({
    getBottomInset: () => bottomInset,
    subscribe: callback => { if (typeof callback === 'function') insetListeners.add(callback); },
    unsubscribe: callback => insetListeners.delete(callback),
  });
  function publishBottomInset(value) {
    if (value === bottomInset) return;
    bottomInset = value;
    for (const listener of [...insetListeners]) {
      try { listener(); } catch (_) { /* One consumer must not stop viewport sizing. */ }
    }
  }

  function editing() {
    let element = doc.activeElement;
    while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement;
    if (!element || element.disabled || element.readOnly) return false;
    if (element.isContentEditable || element.tagName === 'TEXTAREA') return true;
    return element.tagName === 'INPUT'
      && /^(text|search|email|url|tel|password|number)$/.test(element.type || 'text');
  }
  function safeArea() {
    const style = probe && win.getComputedStyle(probe);
    return Object.fromEntries(['top', 'right', 'bottom', 'left'].map(edge => [
      edge, Math.max(0, Number.parseFloat(style?.getPropertyValue(`padding-${edge}`)) || 0),
    ]));
  }
  function inset(rect, safe) {
    return {
      left: rect.left + safe.left, top: rect.top + safe.top,
      width: rect.width - safe.left - safe.right,
      height: rect.height - safe.top,
    };
  }
  function aboveKeyboard(a, b) {
    const top = Math.max(a.top, b.top);
    // At normal scale the software keyboard changes vertical space, not the
    // safe horizontal layout. WebKit may also pre-inset its reported width.
    return { left: a.left, width: a.width, top,
      height: Math.min(a.top + a.height, b.top + b.height) - top,
    };
  }
  function sync() {
    if (paused || doc.visibilityState === 'hidden') return;
    // Let browser zoom magnify the existing layout; resizing the Flutter canvas
    // to the zoomed viewport would cancel that magnification and move controls.
    if (viewport && Math.abs((viewport.scale || 1) - 1) > .01) return;
    const visible = {
      width: viewport?.width || win.innerWidth,
      height: viewport?.height || win.innerHeight,
      left: Math.max(0, viewport?.offsetLeft || 0),
      top: Math.max(0, viewport?.offsetTop || 0),
    };
    const safe = safeArea();
    let values = inset(visible, safe);
    let keyboard = false;
    if ((standalone?.matches || win.navigator?.standalone === true) && probe) {
      const layout = probe.getBoundingClientRect();
      // Installed WebKit can report visualViewport/innerHeight with safe areas
      // already removed (WebKit 254868 / 210009). 100vh is the full CSS viewport.
      // Do not use screen.height: multitasking and display zoom need CSS bounds.
      values = inset({ left: 0, top: 0, width: layout.width, height: layout.height }, safe);
      // A focused field alone does not imply a software keyboard (hardware
      // keyboards and dismissed keyboards keep focus). Only a viewport smaller
      // than the full safe area is occlusion; allow 2px for fractional rounding.
      if (viewport && editing() && visible.height < values.height - safe.bottom - 2) {
        values = aboveKeyboard(values, visible);
        keyboard = true;
      }
    }
    // Browser bars also make a regular tab shorter than 100vh. Establish a
    // non-editing visible baseline; focus alone (e.g. a hardware keyboard) is
    // never proof of occlusion. A width change starts a new orientation baseline.
    if (!(standalone?.matches || win.navigator?.standalone === true)) {
      if (!regularBaseline || Math.abs(regularBaseline.width - visible.width) > 2
        || !editing()) {
        regularBaseline = { width: visible.width, height: visible.height };
      } else if (visible.height > regularBaseline.height) {
        regularBaseline.height = visible.height;
      }
      keyboard = editing() && visible.height < regularBaseline.height - 2;
    } else {
      regularBaseline = null;
    }
    if (Object.values(values).some(value => !Number.isFinite(value))
      || values.width <= 0 || values.height <= 0) return;
    publishBottomInset(keyboard ? 0 : safe.bottom);
    for (const [name, value] of Object.entries(values)) {
      const key = `--app-viewport-${name}`;
      const css = `${value}px`;
      if (host.style.getPropertyValue(key) !== css) host.style.setProperty(key, css);
    }
  }
  function queue() {
    if (paused || doc.visibilityState === 'hidden' || frame !== null) return;
    frame = win.requestAnimationFrame(() => { frame = null; sync(); });
  }
  function cancel() {
    if (frame !== null) win.cancelAnimationFrame(frame);
    frame = null;
    for (const timer of settling) win.clearTimeout(timer);
    settling = [];
  }
  function settle() {
    cancel();
    if (paused || doc.visibilityState === 'hidden') return;
    queue();
    // Launch/resume/rotation may report intermediate viewport dimensions.
    // Recheck only during that transition, never poll throughout clock display.
    settling = [100, 500].map(delay => win.setTimeout(queue, delay));
  }
  win.addEventListener('resize', queue);
  viewport?.addEventListener('resize', queue);
  viewport?.addEventListener('scroll', queue);
  win.addEventListener('orientationchange', settle);
  win.addEventListener('pageshow', () => { paused = false; settle(); });
  win.addEventListener('pagehide', () => { paused = true; cancel(); });
  doc.addEventListener('visibilitychange', () => {
    if (doc.visibilityState === 'hidden') cancel(); else settle();
  });
  doc.addEventListener('shike-app-ready', settle);
  doc.addEventListener('focusin', settle);
  doc.addEventListener('focusout', settle);
  if (standalone?.addEventListener) standalone.addEventListener('change', settle);
  else standalone?.addListener?.(settle);
  // Safe-area padding can settle independently of window/visualViewport events.
  // Observing the probe's content box also catches those inset-only changes.
  if (probe && win.ResizeObserver) new win.ResizeObserver(queue).observe(probe);
  sync();
})();
