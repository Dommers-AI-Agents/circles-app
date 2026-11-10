// backend/controllers/orders/orderWebController.js — the public ordering
// page and its guest endpoints (services/orders/webOrderService). Mounted
// at /order on the API host; the order.favcircles.com host is rewritten
// onto the same paths in server.js, so links use `base` to fit either.
const web = require('../../services/orders/webOrderService');
const pages = require('../../views/orderPage');
const { sendServiceError } = require('../../utils/serviceError');

const fail = (res, error) => sendServiceError(res, error, { log: 'Web order failed', fallbackCode: 'order_failed', fallbackMessage: 'Something went wrong with that order. Try again.' });
const baseFor = (req) => (req.orderHost ? '' : '/order');
const hostFor = (req) => (req.orderHost ? 'https://order.favcircles.com' : `https://${req.get('host') || 'api.favcircles.com'}/order`);

const html = (res, body, { cache = 'public, max-age=60', status = 200, noindex = false } = {}) => {
  res.set('Content-Type', 'text/html; charset=utf-8');
  res.set('Cache-Control', cache);
  if (noindex) res.set('X-Robots-Tag', 'noindex');
  res.status(status).send(body);
};

// @route GET /order/
exports.index = (req, res) => res.redirect(302, 'https://favcircles.com/store-owners.html');

// @route GET /order/:slug
exports.page = async (req, res) => {
  try {
    const page = await web.pageFor(req.params.slug);
    if (page && page.redirectTo) return res.redirect(301, `${baseFor(req)}/${page.redirectTo}`);
    if (!page) return html(res, pages.renderNotFound({ base: baseFor(req) }), { status: 404, cache: 'no-store', noindex: true });
    // The menu and ordering, plus the website parts (photos, about, what's on, score, earn, waitlist)
    const p = { ...web.projection(page.venue, page.place, { live: page.live, ordering: page.ordering }), ...(await web.siteProjection(page.venue, page.place, { live: page.live })) };
    const body = pages.renderOrderPage(p, { base: baseFor(req), canonicalUrl: `https://order.favcircles.com/${p.slug}`, noindex: page.isTestStore });
    html(res, body, { noindex: page.isTestStore });
  } catch (error) {
    console.error('Order page failed:', error.message);
    html(res, pages.renderNotFound({ base: baseFor(req) }), { status: 500, cache: 'no-store', noindex: true });
  }
};

// @route GET /order/:slug/menu.json
exports.menu = async (req, res) => {
  try {
    const page = await web.pageFor(req.params.slug);
    if (!page || page.redirectTo) return res.status(404).json({ success: false, code: 'store_not_found', message: 'That store isn’t taking online orders.' });
    res.set('Cache-Control', 'public, max-age=60');
    res.json({ success: true, data: web.projection(page.venue, page.place, { live: page.live, ordering: page.ordering }) });
  } catch (error) { fail(res, error); }
};

// @route POST /order/:slug/orders   body: { guest:{name,phone,email}, items, note, pickup, website (honeypot) }
exports.place = async (req, res) => {
  try {
    const { guest, items, note, pickup, website } = req.body || {};
    const result = await web.placeGuest({ slug: req.params.slug, guest, items, note, pickup, honeypot: website });
    if (result.ignored) return res.json({ success: true });
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data: { order: result.order, token: result.token, statusUrl: `${hostFor(req)}/o/${result.order.orderId}?t=${result.token}` } });
  } catch (error) { fail(res, error); }
};

// @route GET /order/o/:orderId   (the status page shell)
exports.statusPage = (req, res) => {
  html(res, pages.renderOrderStatusPage({ base: baseFor(req), orderId: req.params.orderId }), { cache: 'no-store', noindex: true });
};

const tokenFrom = (req) => {
  const auth = String(req.headers.authorization || '');
  if (auth.startsWith('Bearer ')) return auth.slice(7);
  return req.query.t ? String(req.query.t) : '';
};

// @route GET /order/api/orders/:orderId   (token-checked)
exports.status = async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data: await web.status(req.params.orderId, tokenFrom(req)) });
  } catch (error) { fail(res, error); }
};

// @route POST /order/api/orders/:orderId/cancel   (token-checked, before the store accepts)
exports.cancel = async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data: await web.cancel(req.params.orderId, tokenFrom(req)) });
  } catch (error) { fail(res, error); }
};

// ---- the waitlist on the store's page (services/waitlistService, web guests)

// @route POST /order/:slug/waitlist   body: { name, email, partySize, website (honeypot) }
exports.joinWaitlist = async (req, res) => {
  try {
    const { name, email, partySize, website } = req.body || {};
    if (website) return res.json({ success: true }); // a bot filled the hidden field
    const page = await web.pageFor(req.params.slug);
    if (!page || page.redirectTo) return res.status(404).json({ success: false, code: 'store_not_found', message: 'That store isn’t on FavCircles.' });
    const result = await require('../../services/waitlistService').joinGuest({ venueId: page.venue.venueId, name, email, partySize });
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data: result });
  } catch (error) { fail(res, error); }
};

// @route GET /order/api/waitlist/:entryId?t=   (token-checked)
exports.waitlistStatus = async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data: await require('../../services/waitlistService').guestStatus(req.params.entryId, tokenFrom(req)) });
  } catch (error) { fail(res, error); }
};

// @route POST /order/api/waitlist/:entryId/leave?t=
exports.leaveWaitlist = async (req, res) => {
  try {
    res.set('Cache-Control', 'no-store');
    res.json({ success: true, data: await require('../../services/waitlistService').leaveGuest(req.params.entryId, tokenFrom(req)) });
  } catch (error) { fail(res, error); }
};

// @route GET /order/sitemap.xml — every public store page (cached an hour)
exports.sitemap = async (req, res) => {
  try {
    const rows = await web.sitemapSlugs();
    const urls = rows.map((r) => `<url><loc>https://order.favcircles.com/${r.slug}</loc>${r.updatedAt ? `<lastmod>${String(r.updatedAt).slice(0, 10)}</lastmod>` : ''}</url>`).join('');
    res.set('Content-Type', 'application/xml; charset=utf-8');
    res.set('Cache-Control', 'public, max-age=3600');
    res.send(`<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${urls}</urlset>`);
  } catch (error) {
    console.error('Sitemap failed:', error.message);
    res.status(500).send('');
  }
};

// @route GET /order/robots.txt
exports.robots = (req, res) => {
  res.set('Content-Type', 'text/plain');
  res.set('Cache-Control', 'public, max-age=86400');
  res.send('User-agent: *\nAllow: /\nDisallow: /o/\nDisallow: /api/\nSitemap: https://order.favcircles.com/sitemap.xml\n');
};

// Anything else under /order is a page, not an API: say so in HTML
exports.notFound = (req, res) => html(res, pages.renderNotFound({ base: baseFor(req) }), { status: 404, cache: 'no-store', noindex: true });
