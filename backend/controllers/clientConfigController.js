// @route GET /api/config/client (public; nothing personal)
const { buildClientConfig } = require('../services/clientConfig');

exports.getClientConfig = (req, res) => {
  res.set('Cache-Control', 'public, max-age=300');
  res.json({ success: true, data: buildClientConfig() });
};
