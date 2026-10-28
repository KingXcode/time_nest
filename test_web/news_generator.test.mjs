import test from 'node:test';
import { execFileSync } from 'node:child_process';
test('RSS aggregation fixtures', () => {
  execFileSync('python3', ['-m', 'unittest', 'discover', '-s', 'test_python', '-v'], {cwd: new URL('..', import.meta.url), stdio: 'pipe'});
});

test('refresh follows only successful current-main app deploys and queues without cancellation', async () => {
  const { readFile } = await import('node:fs/promises');
  const assert = (await import('node:assert/strict')).default;
  const workflow = await readFile(new URL('../.github/workflows/refresh-news.yml', import.meta.url), 'utf8');
  assert.match(workflow, /cron: '23 \* \* \* \*'/);
  assert.match(workflow, /workflows: \['Deploy GitHub Pages'\]/);
  assert.match(workflow, /workflow_run\.conclusion == 'success'/);
  assert.match(workflow, /workflow_run\.head_sha == github.sha/);
  assert.match(workflow, /workflow_run\.head_repository.full_name == github.repository/);
  assert.match(workflow, /group: github-pages\n  cancel-in-progress: false\n  queue: max/);
  assert.match(workflow, /\.expired == false/);
  assert.match(workflow, /commits\/main.*APP_SHA/);
});
