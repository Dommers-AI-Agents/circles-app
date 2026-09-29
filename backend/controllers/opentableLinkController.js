// backend/controllers/opentableLinkController.js
//
// GET /go/opentable?name=&address=&lat=&lng= — the Reserve chip's link.
// Public (the in-app browser carries no JWT) and a plain 302, so the
// partnerActions catalog can point here with no app release.
const linkService = require('../services/opentable/linkService');

const num = (v) => {
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : NaN;
};

exports.redirect = async (req, res) => {
  const name = String(req.query.name || '').slice(0, 200);
  const address = String(req.query.address || '').slice(0, 300);
  const lat = num(req.query.lat);
  const lng = num(req.query.lng);
  const result = await linkService.resolve({ name, address, lat, lng });
  linkService.logClick(result);
  res.set('Cache-Control', 'no-store');
  return res.redirect(302, result.url);
};
