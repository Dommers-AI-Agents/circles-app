// THE session-token mint — every auth path (social, register, login, refresh,
// passkey, account merge) signs the same {uid, email} payload the same way.
// Lives in services/ so controllers never import it from another controller.
const jwt = require('jsonwebtoken');

// JWT lifetime in seconds, parsed from JWT_EXPIRE (e.g. "30d", "12h", "3600").
// Returned to clients as expiresIn so they don't have to guess token lifetime.
function getTokenExpiresInSeconds() {
  const value = process.env.JWT_EXPIRE || '30d';
  const match = String(value).trim().match(/^(\d+)\s*([smhd]?)$/i);
  if (!match) return 30 * 24 * 60 * 60;
  const amount = parseInt(match[1], 10);
  const unitSeconds = { '': 1, s: 1, m: 60, h: 3600, d: 86400 }[match[2].toLowerCase()];
  return amount * unitSeconds;
}

function mintSessionToken(uid, email) {
  return jwt.sign({ uid, email }, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRE });
}

module.exports = { mintSessionToken, getTokenExpiresInSeconds };
