// The site's CSP runs only our own script files (script-src 'self'), so an
// inline <script> in a served page never runs, silently. Every landing page's
// "open the app, else the App Store" and the postcard lightbox were dead this
// way until 2026-11-11. Scripts go in public/*.js; data-only JSON blocks are fine.
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..', '..');
const DIRS = ['routes', 'views', 'controllers', 'public'];
const INLINE = /<script(?![^>]*\bsrc=)(?![^>]*type="application\/(?:ld\+)?json")[^>]*>/i;

const files = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
  const full = path.join(dir, entry.name);
  if (entry.isDirectory()) return entry.name === '__tests__' || entry.name === 'admin' ? [] : files(full);
  return /\.(js|html)$/.test(entry.name) ? [full] : [];
});

test('no served page carries an inline script', () => {
  const offenders = DIRS.flatMap((dir) => files(path.join(root, dir)))
    .filter((file) => !file.startsWith(path.join(root, 'public') + path.sep) || file.endsWith('.html'))
    .filter((file) => INLINE.test(fs.readFileSync(file, 'utf8')))
    .map((file) => path.relative(root, file));
  expect(offenders).toEqual([]);
});

test('the shared landing script only opens our own scheme and the App Store', () => {
  const js = fs.readFileSync(path.join(root, 'public', 'landing.js'), 'utf8');
  expect(js).toContain('/^circles:\\/\\//');
  expect(js).toContain('apps\\.apple\\.com');
});
