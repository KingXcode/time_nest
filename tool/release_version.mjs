#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// The workflow sequence increases on both pushes and manual deployments.
// A retry of the same workflow is the same release and keeps its version.
export function releaseVersion(pubspec, sequence = '0') {
  const match = /^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m.exec(pubspec);
  if (!match) throw new Error('pubspec.yaml must have version: major.minor.patch+build');
  if (!/^(0|[1-9]\d*)$/.test(sequence)) throw new Error('Invalid WEB_RELEASE_SEQUENCE');
  const build = Number(match[2]) + Number(sequence);
  if (!Number.isSafeInteger(build)) throw new Error('Release build number is too large');
  return `${match[1]}+${build}`;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const pubspec = await readFile(new URL('../pubspec.yaml', import.meta.url), 'utf8');
    console.log(releaseVersion(pubspec, process.env.WEB_RELEASE_SEQUENCE ?? '0'));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
