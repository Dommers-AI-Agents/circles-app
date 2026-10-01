// backend/utils/text.js — small string helpers shared by the services.

/** HTML-escapes the five characters that matter; null/undefined → ''. */
const escapeHtml = (value) => String(value == null ? '' : value)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/** Trimmed string capped at `max`; anything that isn't a string → ''. */
const clean = (value, max) => (typeof value === 'string' ? value.trim().slice(0, max) : '');

// For logs: enough to recognise an address, not enough to collect it
// ("we***@gmail.com"). Security audit 2026-10-01: auth logs held full emails.
const maskEmail = (email) => {
  const [name, domain] = String(email || '').split('@');
  if (!domain) return email ? '***' : String(email);
  return `${name.slice(0, 2)}***@${domain}`;
};

module.exports = { escapeHtml, clean, maskEmail };
