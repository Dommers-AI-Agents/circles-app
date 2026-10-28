// backend/routes/orderWebRoutes.js — order.favcircles.com/<slug>: a store's
// public ordering page and the guest endpoints behind it. Mounted at
// /order (server.js rewrites the ordering host onto it). Outside /api, so
// the general limiter doesn't apply: each route carries its own.
const express = require('express');
const rateLimit = require('express-rate-limit');
const c = require('../controllers/orders/orderWebController');

const router = express.Router();
const limit = (max, windowMs = 15 * 60 * 1000) => rateLimit({
  windowMs, max, standardHeaders: true, legacyHeaders: false,
  message: { success: false, code: 'rate_limited', message: 'Too many requests. Try again in a few minutes.' }
});
const pageLimiter = limit(300);
const statusLimiter = limit(400);   // a status tab polls every 10 s
const placeLimiter = limit(20);
const cancelLimiter = limit(20);

const SLUG = ':slug([a-z0-9-]{3,48})';
const ORDER = ':orderId([A-Za-z0-9_-]{8,40})';

router.get('/', c.index);
router.get(`/o/${ORDER}`, pageLimiter, c.statusPage);
router.get(`/api/orders/${ORDER}`, statusLimiter, c.status);
router.post(`/api/orders/${ORDER}/cancel`, cancelLimiter, c.cancel);
router.get(`/${SLUG}`, pageLimiter, c.page);
router.get(`/${SLUG}/menu.json`, pageLimiter, c.menu);
router.post(`/${SLUG}/orders`, placeLimiter, express.json({ limit: '32kb' }), c.place);
router.use(c.notFound);

module.exports = router;
