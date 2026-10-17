#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readdir, readFile, realpath, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const templatePath = fileURLToPath(new URL('../web/sw.template.js', import.meta.url));
const placeholder = '__SHIKE_BUILD_MANIFEST__';
const excluded = new Set(['shike-sw.js', 'sw.template.js', 'flutter_service_worker.js']);
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');

export function includedPath(name) {
  return !name.split('/').some((part) => part.startsWith('.'))
    && !excluded.has(name) && !name.endsWith('.map');
}

/** Pure rendering entry point: tests need no filesystem fixtures or dependencies. */
export function renderServiceWorker(files, template) {
  if (template.split(placeholder).length !== 2) throw new Error('SW template must contain exactly one manifest placeholder');
  const resources = [];
  const seen = new Set();
  for (const { path: relativePath, bytes } of files) {
    if (typeof relativePath !== 'string' || relativePath.startsWith('/') || relativePath.includes('\\')
        || relativePath.split('/').some((part) => part === '..' || part === '' || part === '.')) {
      throw new Error(`Unsafe build path: ${relativePath}`);
    }
    if (!includedPath(relativePath)) continue;
    const urlPath = relativePath.split('/').map(encodeURIComponent).join('/');
    if (seen.has(urlPath)) throw new Error(`Duplicate build path: ${relativePath}`);
    seen.add(urlPath);
    resources.push({ path: urlPath, hash: digest(bytes) });
  }
  resources.sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  // These are build validation requirements, not a hand-maintained precache list.
  // Every deployable file found by the walker is included above, including fonts,
  // deferred JS, manifest/icons, all assets and all local CanvasKit variants.
  for (const required of ['index.html', 'flutter_bootstrap.js', 'main.dart.js', 'platform.js']) {
    if (!seen.has(required)) throw new Error(`Missing release artifact: ${required}`);
  }
  if (!resources.some((r) => r.path.startsWith('canvaskit/') && r.path.endsWith('.wasm'))
      || !resources.some((r) => r.path.startsWith('canvaskit/') && r.path.endsWith('.js'))) {
    throw new Error('Local CanvasKit JS/WASM missing; use --no-web-resources-cdn');
  }
  const version = digest(`${template}\n${JSON.stringify(resources)}`);
  const manifest = { version, resources };
  return { source: template.replace(placeholder, JSON.stringify(manifest)), manifest };
}

export async function collectBuildFiles(root) {
  const files = [];
  async function walk(directory, prefix) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const relativePath = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (!includedPath(relativePath)) continue;
      const absolutePath = path.join(directory, entry.name);
      // Never pull arbitrary host files into a deployable offline bundle.
      if (entry.isSymbolicLink()) throw new Error(`Symlinks are not allowed in build output: ${relativePath}`);
      if (entry.isDirectory()) await walk(absolutePath, relativePath);
      else if (entry.isFile()) files.push({ path: relativePath, bytes: await readFile(absolutePath) });
    }
  }
  await walk(root, '');
  return files;
}

export async function generateServiceWorker(directory) {
  if (!directory) throw new Error('Usage: node tool/generate_sw.mjs build/web');
  const root = await realpath(path.resolve(directory));
  if (!(await stat(root)).isDirectory()) throw new Error('Build output must be a directory');
  const template = await readFile(templatePath, 'utf8');
  const result = renderServiceWorker(await collectBuildFiles(root), template);
  // Do not generate into web/: debug flutter_bootstrap must not register a SW.
  if (root === await realpath(path.dirname(templatePath))) throw new Error('Refusing to generate a release SW into source web/');
  const destination = path.join(root, 'shike-sw.js');
  // Refuse a pre-existing symlink instead of overwriting a file outside output.
  const entries = await readdir(root, { withFileTypes: true });
  if (entries.some((entry) => entry.name === 'shike-sw.js' && !entry.isFile())) {
    throw new Error('SW destination must be a regular file, not a symlink/directory');
  }
  await writeFile(destination, result.source, 'utf8');
  return { ...result, destination };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length !== 3) throw new Error('Usage: node tool/generate_sw.mjs build/web');
    const result = await generateServiceWorker(process.argv[2]);
    console.log(`Generated ${result.destination}: ${result.manifest.resources.length} files, version ${result.manifest.version}`);
  } catch (error) {
    console.error(`Service worker generation failed: ${error.message}`);
    process.exitCode = 1;
  }
}
