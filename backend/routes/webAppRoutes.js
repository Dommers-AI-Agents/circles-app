// backend/routes/webAppRoutes.js
// FavCircles in a browser, at app.favcircles.com (Wes, 2026-11-26: no
// Android app; "go ahead and build phase 1, 2, 3"). The app is a single
// page built from /webapp into public/app (committed, because the Cloud Run
// image is built from backend/ alone). On the app's host this serves that
// page for the app's own paths; everything else (/api, /public, /s, …) falls
// through to the routes every host shares.
//
// The app's paths match the links the iOS app shares (/place/<id>,
// /circle/<id>, /user/<id>), so a shared link opens the same thing here.
// Adding a screen = adding its path to APP_PATHS and to webapp/src/App.tsx.
//
// Off switch: WEB_APP=false (the host then behaves like api.favcircles.com).
const path = require('path');
const fs = require('fs');

const APP_DIR = path.join(__dirname, '..', 'public', 'app');
const DEFAULT_HOST = 'app.favcircles.com';

/** Hosts the app answers on. WEB_APP_HOSTS adds more (a local run: "localhost"). */
const appHosts = () => new Set([DEFAULT_HOST, ...String(process.env.WEB_APP_HOSTS || '').split(',')]
  .map((host) => host.trim().toLowerCase()).filter(Boolean));

const webAppEnabled = () => process.env.WEB_APP !== 'false';

// First path segment → the app owns it. Exact names only: /app/… and /s/…
// belong to the share pages and the store page.
const APP_PATHS = new Set([
  '', 'login', 'map', 'circles', 'circle', 'place', 'user', 'people', 'feed', 'messages',
  'rewards', 'locals', 'notifications', 'me', 'add', 'search', 'settings', 'trash'
]);

/** Pure: is this URL path one of the app's screens? */
const isWebAppPath = (urlPath) => {
  const clean = String(urlPath || '/').split('?')[0];
  if (!clean.startsWith('/')) return false;
  const first = clean.split('/')[1] || '';
  return APP_PATHS.has(first);
};

/** Pure: does this request get the app's page? */
const servesWebApp = ({ method, host, urlPath }) => {
  if (!webAppEnabled() || (method !== 'GET' && method !== 'HEAD')) return false;
  const name = String(host || '').split(':')[0].toLowerCase();
  return appHosts().has(name) && isWebAppPath(urlPath);
};

const MANIFEST = {
  name: 'FavCircles',
  short_name: 'FavCircles',
  description: 'Your own map of the places you love, and your friends\' maps.',
  start_url: '/',
  scope: '/',
  display: 'standalone',
  background_color: '#0F1E3A',
  theme_color: '#0F1E3A',
  icons: [
    { src: 'https://favcircles.com/app-icon.png', sizes: '1024x1024', type: 'image/png', purpose: 'any' }
  ]
};

function webApp(req, res, next) {
  const host = String(req.headers.host || '').split(':')[0].toLowerCase();
  if (!webAppEnabled() || !appHosts().has(host) || (req.method !== 'GET' && req.method !== 'HEAD')) return next();
  if (req.path === '/manifest.webmanifest') {
    res.type('application/manifest+json');
    res.set('Cache-Control', 'public, max-age=3600');
    return res.send(JSON.stringify(MANIFEST));
  }
  if (!isWebAppPath(req.path)) return next();
  const index = path.join(APP_DIR, 'index.html');
  if (!fs.existsSync(index)) return next();
  // The page names its hashed script and style files, so it must never be
  // cached; the files themselves can be kept for good.
  res.set('Cache-Control', 'no-cache');
  res.set('X-Robots-Tag', 'noindex');
  return res.sendFile(index);
}

module.exports = { webApp, isWebAppPath, servesWebApp, appHosts, webAppEnabled, APP_PATHS, APP_DIR };
