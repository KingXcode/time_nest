import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, copyFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

test('release removes retired A-share assets before generating the offline manifest', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'time-nest-release-'));
  try {
    for (const dir of ['tool', 'web', 'build/web/canvaskit']) {
      await mkdir(path.join(root, dir), { recursive: true });
    }
    for (const file of ['tool/build_web.sh', 'tool/release_version.mjs', 'tool/generate_sw.mjs', 'web/sw.template.js']) {
      await copyFile(new URL(`../${file}`, import.meta.url), path.join(root, file));
    }
    await writeFile(path.join(root, 'pubspec.yaml'), 'name: time_nest\nversion: 2.3.2+8\n');
    const files = {
      'index.html': '<html>current app</html>',
      'flutter_bootstrap.js': 'bootstrap',
      'main.dart.js': 'old app',
      'platform.js': 'platform',
      'dashboard.js': 'retained dashboard and crypto bridge',
      'canvaskit/canvaskit.js': 'renderer',
      'canvaskit/canvaskit.wasm': 'wasm',
      'market_chart.html': 'retired A-share wrapper',
      'market_chart.js': 'retired A-share script',
    };
    for (const [file, bytes] of Object.entries(files)) {
      await writeFile(path.join(root, 'build/web', file), bytes);
    }
    // Model Flutter's incremental copy: compilation leaves old web assets intact.
    const flutter = path.join(root, 'fake-flutter');
    await writeFile(flutter, '#!/usr/bin/env bash\nset -eu\nprintf "current app" > build/web/main.dart.js\n', { mode: 0o755 });
    const result = spawnSync('bash', [path.join(root, 'tool/build_web.sh'), '--no-pub'], {
      cwd: tmpdir(), encoding: 'utf8', env: { ...process.env, FLUTTER_BIN: flutter },
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
    for (const file of ['market_chart.html', 'market_chart.js']) {
      await assert.rejects(access(path.join(root, 'build/web', file)), { code: 'ENOENT' });
    }
    assert.equal(await readFile(path.join(root, 'build/web/dashboard.js'), 'utf8'), files['dashboard.js']);
    assert.equal(await readFile(path.join(root, 'build/web/main.dart.js'), 'utf8'), 'current app');
    const worker = await readFile(path.join(root, 'build/web/shike-sw.js'), 'utf8');
    assert.doesNotMatch(worker, /market_chart/);
    assert.match(worker, /dashboard\.js/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
