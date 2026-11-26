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
  // The service worker must be served from the root to cover every screen
  if (req.path === '/sw.js') {
    const worker = path.join(APP_DIR, 'sw.js');
    if (!fs.existsSync(worker)) return next();
    res.type('application/javascript');
    res.set('Cache-Control', 'no-cache');
    return res.sendFile(worker);
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

// Links the iOS app shares (https://api.favcircles.com/place/<id>, /circle/<id>,
// /user/<id>) open the same thing in the web app on a phone that can't have
// the iOS app: before this, the share page's button led an Android phone to
// the App Store. Apple devices and link-preview fetchers keep the share page.
const SHARED_LINK = /^\/(place|circle|user)\/[A-Za-z0-9._-]{1,200}\/?$/;
const SHARE_HOSTS = new Set(['api.favcircles.com', 'favcircles.com', 'www.favcircles.com']);

/**
 * Pure: the web app screen behind one of the "open the app" links our
 * emails and pushes use (/app/open?path=rewards, /app/messages/<id>,
 * /app/map, /daily-summary), or null when the link isn't one of them.
 */
const appLinkPath = (urlPath, query = '') => {
  const clean = String(urlPath || '').replace(/\/$/, '');
  if (clean === '/app/map') return '/';
  if (clean === '/app/daily-summary' || clean === '/daily-summary') return '/feed';
  if (clean === '/app/messages') return '/messages';
  const chat = /^\/app\/messages\/([A-Za-z0-9_-]{1,200})$/.exec(clean);
  if (chat) return `/messages/${chat[1]}`;
  if (clean === '/app/open') {
    const wanted = new URLSearchParams(String(query).replace(/^\?/, '')).get('path');
    return { rewards: '/rewards', messages: '/messages', people: '/people', feed: '/feed' }[wanted] || '/';
  }
  return null;
};

/** Pure: where a shared link should send this visitor, or null to leave it. */
const sharedLinkRedirect = ({ method, host, urlPath, userAgent, query = '' }) => {
  if (!webAppEnabled() || method !== 'GET') return null;
  const name = String(host || '').split(':')[0].toLowerCase();
  if (!SHARE_HOSTS.has(name)) return null;
  const shared = SHARED_LINK.test(String(urlPath || ''));
  const appLink = shared ? null : appLinkPath(urlPath, query);
  if (!shared && appLink === null) return null;
  const { isAppleDevice, isLinkPreviewBot } = require('../utils/clientPlatform');
  if (isAppleDevice(userAgent) || isLinkPreviewBot(userAgent)) return null;
  return shared ? `https://${DEFAULT_HOST}${urlPath}${query}` : `https://${DEFAULT_HOST}${appLink}`;
};

function sharedLinksToWebApp(req, res, next) {
  const queryAt = req.originalUrl.indexOf('?');
  const target = sharedLinkRedirect({
    method: req.method, host: req.headers.host, urlPath: req.path, userAgent: req.get('user-agent'),
    query: queryAt >= 0 ? req.originalUrl.slice(queryAt) : ''
  });
  if (!target) return next();
  res.set('Cache-Control', 'no-store');
  res.set('Vary', 'User-Agent');
  return res.redirect(302, target);
}

module.exports = {
  webApp, sharedLinksToWebApp, sharedLinkRedirect, appLinkPath, isWebAppPath, servesWebApp, appHosts, webAppEnabled,
  APP_PATHS, APP_DIR, DEFAULT_HOST
};
