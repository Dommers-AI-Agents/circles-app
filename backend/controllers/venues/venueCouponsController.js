// controllers/venues/venueCouponsController.js
// Manage Store → Coupons (2026-11-14): the store's flyer and mailer coupons,
// each with its QR link and how the campaign is doing. Business only; the
// rules live in services/storeCoupons.
const QRCode = require('qrcode');
const coupons = require('../../services/storeCoupons');
const { sendServiceError } = require('../../utils/serviceError');

// @route GET /api/rewards/venues/:venueId/coupons
exports.list = async (req, res) => {
  try {
    res.json({ success: true, data: { coupons: coupons.listForOwner(req.venue) } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to load coupons', fallbackMessage: 'Failed to load coupons' });
  }
};

// @route POST /api/rewards/venues/:venueId/coupons   body: { title, detail?, onlineCode?, campaign?, expiresAt, maxClaims? }
exports.create = async (req, res) => {
  try {
    res.status(201).json({ success: true, data: await coupons.create(req.venue, req.body || {}) });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to create coupon', fallbackMessage: 'Failed to create the coupon' });
  }
};

// @route PUT /api/rewards/venues/:venueId/coupons/:couponId   body: any of the fields, plus active
exports.update = async (req, res) => {
  try {
    res.json({ success: true, data: await coupons.update(req.venue, String(req.params.couponId), req.body || {}) });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to update coupon', fallbackMessage: 'Failed to update the coupon' });
  }
};

// @route DELETE /api/rewards/venues/:venueId/coupons/:couponId
exports.remove = async (req, res) => {
  try {
    res.json({ success: true, data: await coupons.remove(req.venue, String(req.params.couponId)) });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to delete coupon', fallbackMessage: 'Failed to delete the coupon' });
  }
};

// @route GET /api/rewards/venues/:venueId/coupons/:couponId/qr.png?size=1200
//        The QR for the flyer: print resolution, high error correction
exports.qr = async (req, res) => {
  try {
    const coupon = coupons.findCoupon(req.venue, String(req.params.couponId));
    const url = coupon && coupons.couponUrl(req.venue, coupon.couponId);
    if (!url) return res.status(404).json({ success: false, error: 'That coupon isn’t here anymore.' });
    const size = Math.min(2400, Math.max(300, parseInt(req.query.size, 10) || 1200));
    const png = await QRCode.toBuffer(url, { errorCorrectionLevel: 'H', width: size, margin: 4, color: { dark: '#000000', light: '#FFFFFF' } });
    res.setHeader('Content-Type', 'image/png');
    res.setHeader('Content-Disposition', `attachment; filename="coupon-${coupon.couponId}.png"`);
    res.send(png);
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to render coupon QR', fallbackMessage: 'Could not build the QR' });
  }
};
