import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = (await readFile(new URL('../web/flutter_bootstrap.js', import.meta.url), 'utf8'))
  .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');

test('custom startup forwards the embedded host and local renderer configuration to the engine', async () => {
  const host = {}, events = [];
  let options;
  const context = {
    URL, Event,
    document: { baseURI: 'https://example.test/time_nest/', getElementById: id => id === 'app' ? host : { remove() {} }, dispatchEvent: e => events.push(e.type) },
    _flutter: { loader: { load: config => { options = config; return Promise.resolve(); } } },
    shikeLoadError() { assert.fail('startup failed'); },
    console,
  };
  context.window = context;
  vm.runInNewContext(source, context);
  let initialized, ran = false;
  await options.onEntrypointLoaded({ initializeEngine: async config => { initialized = config; return { runApp: async () => { ran = true; } }; } });
  assert.equal(initialized, options.config);
  assert.equal(initialized.hostElement, host);
  assert.equal(initialized.renderer, 'canvaskit');
  assert.equal(initialized.canvasKitBaseUrl, 'https://example.test/time_nest/canvaskit/');
  assert.equal(ran, true);
  assert.deepEqual(events, ['shike-app-ready']);
});

test('fixed embedded host clips native focus scrolling without changing Flutter scroll containers', async () => {
  const html = await readFile(new URL('../web/index.html', import.meta.url), 'utf8');
  assert.match(html, /#app\s*\{[^}]*overflow: hidden;\s*overflow: clip;/);
  assert.match(html, /#app > flutter-view \{ overflow: clip !important; \}/);
});
