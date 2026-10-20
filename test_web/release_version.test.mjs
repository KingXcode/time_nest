import test from 'node:test';
import assert from 'node:assert/strict';
import { releaseVersion } from '../tool/release_version.mjs';

test('deployment versions increase automatically and retrying a release is deterministic', () => {
  const pubspec = 'name: clock\nversion: 2.3.2+8\n';
  assert.equal(releaseVersion(pubspec), '2.3.2+8');
  assert.equal(releaseVersion(pubspec, '41'), '2.3.2+49');
  assert.equal(releaseVersion(pubspec, '42'), '2.3.2+50');
  assert.equal(releaseVersion(pubspec, '42'), '2.3.2+50');
  assert.equal(releaseVersion('version: 2.4.0+9\n', '43'), '2.4.0+52');
});

test('malformed versions and deployment sequences fail before building', () => {
  for (const spec of ['version: latest', 'version: 1.0.0', 'version: 1.0.0+-1']) {
    assert.throws(() => releaseVersion(spec));
  }
  for (const sequence of ['', '-1', '1.5', 'NaN', '01', '9007199254740991']) {
    assert.throws(() => releaseVersion('version: 2.3.2+8', sequence));
  }
});
