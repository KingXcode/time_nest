import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../web/loading.js', import.meta.url), 'utf8');
function loading() {
  const nodes = Object.fromEntries(['loading', 'loading-message', 'loading-clock', 'retry']
    .map(id => [id, { textContent: '', hidden: true, remove() { this.removed = true; } }]));
  const events = [];
  const intervals = new Map(), timeouts = new Map();
  let id = 0;
  const context = { Date, Event,
    document: { getElementById: key => nodes[key], dispatchEvent: event => events.push(event.type) },
    setInterval: fn => { intervals.set(++id, fn); return id; },
    clearInterval: id => intervals.delete(id),
    setTimeout: fn => { timeouts.set(++id, fn); return id; },
    clearTimeout: id => timeouts.delete(id),
  };
  context.window = context;
  vm.runInNewContext(source, context);
  return { nodes, events, intervals, timeouts, api: context.shikeLoader };
}

test('first paint provides time; slow download and failure preserve it', () => {
  const b = loading();
  assert.match(b.nodes['loading-clock'].textContent, /^\d\d:\d\d:\d\d$/);
  for (const fn of b.timeouts.values()) fn();
  assert.equal(b.nodes.retry.hidden, false);
  assert.match(b.nodes['loading-message'].textContent, /网络较慢/);
  b.api.fail();
  assert.match(b.nodes['loading-message'].textContent, /基础时间仍可查看/);
  assert.equal(b.intervals.size, 1);
});
test('stages are honest and readiness cleans timers and starts offline setup once', () => {
  const b = loading();
  b.api.stage('正在初始化显示引擎');
  assert.match(b.nodes['loading-message'].textContent, /初始化/);
  b.api.ready(); b.api.ready(); b.api.fail();
  assert.equal(b.nodes.loading.removed, true);
  assert.equal(b.intervals.size, 0); assert.equal(b.timeouts.size, 0);
  assert.deepEqual(b.events, ['shike-app-ready']);
});
