// After `vite build`: records a hash of the sources next to the built files
// (backend/public/app/build-info.json). A backend test recomputes it, so a
// commit that changes webapp/ without rebuilding fails before it can deploy.
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(fileURLToPath(import.meta.url), '..', '..');
const SOURCES = ['src', 'index.html', 'package.json', 'vite.config.ts'];

export function sourceHash(base = root) {
  const files = [];
  const walk = (path) => {
    if (statSync(path).isDirectory()) readdirSync(path).sort().forEach((name) => walk(join(path, name)));
    else files.push(path);
  };
  SOURCES.forEach((name) => walk(join(base, name)));
  const hash = createHash('sha256');
  for (const file of files) {
    hash.update(relative(base, file));
    hash.update('\0');
    hash.update(readFileSync(file));
    hash.update('\0');
  }
  return hash.digest('hex');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const out = join(root, '..', 'backend', 'public', 'app', 'build-info.json');
  writeFileSync(out, `${JSON.stringify({ sourceHash: sourceHash() }, null, 2)}\n`);
  console.log(`stamped ${out}`);
}
