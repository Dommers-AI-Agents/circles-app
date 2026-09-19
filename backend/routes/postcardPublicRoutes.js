// backend/routes/postcardPublicRoutes.js
//
// The public, unauthenticated postcard pages: the image proxy, the QR for
// the back of a mailed card, and the share page. Mounted at the app root
// (no /api) so favcircles.com/postcard/<token> can point straight here.
const express = require('express');
const QRCode = require('qrcode');
const postcardShareService = require('../services/postcardShareService');
const { renderNotFound, renderPostcard } = require('../views/postcardPage');

const router = express.Router();

// The postcard image, served from our own host so it can be saved with a
// real filename (the storage URL is a token soup). `download` forces the
// save dialog; `image` shows it inline (the lightbox).
router.get('/postcard/:token/:mode(image|download)', async (req, res) => {
  try {
    const share = await postcardShareService.get(req.params.token);
    if (!share) return res.status(404).end();
    const upstream = await fetch(share.imageUrl);
    if (!upstream.ok) return res.status(502).end();
    const bytes = Buffer.from(await upstream.arrayBuffer());
    const slug = (share.placeName || 'favcircles').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'favcircles';
    res.setHeader('Content-Type', upstream.headers.get('content-type') || 'image/jpeg');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    if (req.params.mode === 'download') {
      res.setHeader('Content-Disposition', `attachment; filename="postcard-${slug}.jpg"`);
    }
    return res.send(bytes);
  } catch (e) {
    console.error('postcard image proxy failed:', e.message);
    return res.status(502).end();
  }
});

// The QR printed on the back of a mailed postcard, pointing at that card's
// public page. Served as a URL rather than an inline data URI because Lob
// caps the HTML it renders at roughly 10k characters.
router.get('/postcard/:token/qr.png', async (req, res) => {
  try {
    const share = await postcardShareService.get(req.params.token);
    if (!share) return res.status(404).end();
    const png = await QRCode.toBuffer(
      `${postcardShareService.PUBLIC_BASE_URL}/postcard/${req.params.token}`,
      { type: 'png', width: 600, margin: 1, errorCorrectionLevel: 'M' }
    );
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Cache-Control', 'public, max-age=86400');
    return res.send(png);
  } catch (e) {
    console.error('postcard qr failed:', e.message);
    return res.status(502).end();
  }
});

// Public postcard page (Widgets tab → Postcard → "Share by text or email").
// Deliberately NOT a universal link: a non-user opens it in the browser,
// sees the card, and gets the pitch underneath.
router.get('/postcard/:token', async (req, res) => {
  let share = null;
  try {
    share = await postcardShareService.get(req.params.token);
  } catch (e) {
    console.error('postcard page lookup failed:', e.message);
  }
  if (!share) return res.status(404).send(renderNotFound());
  res.send(renderPostcard(share));
});

module.exports = router;
