// The web app at app.favcircles.com: which requests get its page, and that
// the built files in public/app are the ones webapp/ would build today.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { isWebAppPath, servesWebApp, APP_DIR } = require('../webAppRoutes');

afterEach(() => { delete process.env.WEB_APP; delete process.env.WEB_APP_HOSTS; });

test("the app's screens are its own; the API, share pages and store page are not", () => {
  ['/', '/map', '/circle/abc', '/place/abc', '/user/abc', '/feed', '/messages/c1', '/rewards', '/me/edit?x=1']
    .forEach((p) => expect(isWebAppPath(p)).toBe(true));
  ['/api/circles/me', '/public/app/assets/a.js', '/s/WIN123', '/app/open', '/q/abc', '/e/c', '/order/x', '/admin', '/health', '/.well-known/apple-app-site-association', '/connect/u1']
    .forEach((p) => expect(isWebAppPath(p)).toBe(false));
});

test('only GETs on the app host get the page, and the switch turns it off', () => {
  const ask = (extra) => servesWebApp({ method: 'GET', host: 'app.favcircles.com', urlPath: '/circle/abc', ...extra });
  expect(ask()).toBe(true);
  expect(ask({ host: 'APP.favcircles.com:443' })).toBe(true);
  expect(ask({ host: 'api.favcircles.com' })).toBe(false);
  expect(ask({ host: 'order.favcircles.com' })).toBe(false);
  expect(ask({ method: 'POST' })).toBe(false);
  expect(ask({ urlPath: '/api/circles/me' })).toBe(false);
  process.env.WEB_APP_HOSTS = 'localhost';
  expect(ask({ host: 'localhost:8099' })).toBe(true);
  process.env.WEB_APP = 'false';
  expect(ask()).toBe(false);
});

// Same walk as webapp/scripts/stamp-build.mjs
const sourceHash = (base) => {
  const files = [];
  const walk = (p) => {
    if (fs.statSync(p).isDirectory()) fs.readdirSync(p).sort().forEach((name) => walk(path.join(p, name)));
    else files.push(p);
  };
  ['src', 'index.html', 'package.json', 'vite.config.ts'].forEach((name) => walk(path.join(base, name)));
  const hash = crypto.createHash('sha256');
  for (const file of files) {
    hash.update(path.relative(base, file));
    hash.update('\0');
    hash.update(fs.readFileSync(file));
    hash.update('\0');
  }
  return hash.digest('hex');
};

test('the built app is committed and matches its sources (run `npm run build` in webapp/)', () => {
  const index = path.join(APP_DIR, 'index.html');
  expect(fs.existsSync(index)).toBe(true);
  const html = fs.readFileSync(index, 'utf8');
  // Every script and style the page names is a built file that exists
  const assets = [...html.matchAll(/(?:src|href)="\/public\/app\/(assets\/[^"]+)"/g)].map((m) => m[1]);
  expect(assets.length).toBeGreaterThan(0);
  assets.forEach((asset) => expect(fs.existsSync(path.join(APP_DIR, asset))).toBe(true));
  // CSP runs only our own script files: nothing inline
  expect(html).not.toMatch(/<script(?![^>]*\bsrc=)[^>]*>/i);
  const webapp = path.join(__dirname, '..', '..', '..', 'webapp');
  if (!fs.existsSync(path.join(webapp, 'src'))) return; // a backend-only checkout
  const { sourceHash: built } = JSON.parse(fs.readFileSync(path.join(APP_DIR, 'build-info.json'), 'utf8'));
  expect(built).toBe(sourceHash(webapp));
});
