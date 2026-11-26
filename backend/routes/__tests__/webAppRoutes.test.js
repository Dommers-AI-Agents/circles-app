// The web app at app.favcircles.com: which requests get its page, and that
// the built files in public/app are the ones webapp/ would build today.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { isWebAppPath, servesWebApp, sharedLinkRedirect, APP_DIR } = require('../webAppRoutes');

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

test('a shared link opens in the web app on a phone that cannot have the iOS app', () => {
  const ANDROID = 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36';
  const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15';
  const ask = (extra) => sharedLinkRedirect({ method: 'GET', host: 'api.favcircles.com', urlPath: '/place/abc123', userAgent: ANDROID, ...extra });
  expect(ask()).toBe('https://app.favcircles.com/place/abc123');
  expect(ask({ urlPath: '/circle/c1', query: '?ref=u1' })).toBe('https://app.favcircles.com/circle/c1?ref=u1');
  expect(ask({ urlPath: '/user/u1' })).toBe('https://app.favcircles.com/user/u1');
  // The iPhone keeps the page that opens the app; a messaging app's preview keeps its title and picture
  expect(ask({ userAgent: IPHONE })).toBeNull();
  expect(ask({ userAgent: 'WhatsApp/2.23.20 A' })).toBeNull();
  expect(ask({ userAgent: 'facebookexternalhit/1.1' })).toBeNull();
  expect(ask({ userAgent: 'Mozilla/5.0 (compatible; Googlebot/2.1)' })).toBeNull();
  // Not the app's own host (it serves the app there already), not other pages, not writes
  expect(ask({ host: 'app.favcircles.com' })).toBeNull();
  expect(ask({ urlPath: '/connect/u1' })).toBeNull();
  // The "open the app" links in our emails land on the matching screen
  expect(ask({ urlPath: '/app/open' })).toBe('https://app.favcircles.com/');
  expect(ask({ urlPath: '/app/open', query: '?path=rewards' })).toBe('https://app.favcircles.com/rewards');
  expect(ask({ urlPath: '/app/messages/c1' })).toBe('https://app.favcircles.com/messages/c1');
  expect(ask({ urlPath: '/app/map' })).toBe('https://app.favcircles.com/');
  expect(ask({ urlPath: '/daily-summary' })).toBe('https://app.favcircles.com/feed');
  expect(ask({ urlPath: '/app/open', userAgent: IPHONE })).toBeNull();
  expect(ask({ urlPath: '/app/widget/water' })).toBeNull();
  expect(ask({ urlPath: '/place/abc/extra' })).toBeNull();
  expect(ask({ method: 'POST' })).toBeNull();
  process.env.WEB_APP = 'false';
  expect(ask()).toBeNull();
});

// Same walk as webapp/scripts/stamp-build.mjs
const sourceHash = (base) => {
  const files = [];
  const walk = (p) => {
    if (fs.statSync(p).isDirectory()) fs.readdirSync(p).sort().forEach((name) => walk(path.join(p, name)));
    else files.push(p);
  };
  ['src', 'public', 'index.html', 'package.json', 'vite.config.ts'].forEach((name) => walk(path.join(base, name)));
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
