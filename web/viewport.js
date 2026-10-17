// The embedded Flutter view observes #app, not window.visualViewport. Keep its
// DOM bounds in the visible viewport before the engine measures its first frame.
(() => {
  'use strict';
  const win = globalThis;
  const doc = win.document;
  const host = doc.getElementById('app');
  if (!host) return;
  const viewport = win.visualViewport;
  let paused = false;
  let frame = null;
  let settling = [];

  function sync() {
    if (paused || doc.visibilityState === 'hidden') return;
    // Let browser zoom magnify the existing layout; resizing the Flutter canvas
    // to the zoomed viewport would cancel that magnification and move controls.
    if (viewport && Math.abs((viewport.scale || 1) - 1) > .01) return;
    const width = viewport?.width || win.innerWidth;
    const height = viewport?.height || win.innerHeight;
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return;
    const values = {
      width, height,
      left: Math.max(0, viewport?.offsetLeft || 0),
      top: Math.max(0, viewport?.offsetTop || 0),
    };
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
  sync();
})();
