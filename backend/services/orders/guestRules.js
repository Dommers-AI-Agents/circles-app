// backend/services/orders/guestRules.js — who a web customer is (no
// account): a name, a phone the store can call, an optional email for
// updates. Pure; the phone's HMAC is the key every guest limit hangs on.
const crypto = require('crypto');
const { jwtSecret } = require('../../config/secrets');
const { ServiceError } = require('../../utils/serviceError');

const GUEST_LIMITS = { openPerPhone: 3, perDay: 10, name: 60, email: 120 };
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** '(704) 555-0100' → '+17045550100'. 10 digits are US; '+' keeps its country. */
function normalizePhone(raw) {
  const s = String(raw || '').trim();
  const digits = s.replace(/\D/g, '');
  let e164 = null;
  if (s.startsWith('+') && digits.length >= 8 && digits.length <= 15) e164 = `+${digits}`;
  else if (digits.length === 10) e164 = `+1${digits}`;
  else if (digits.length === 11 && digits[0] === '1') e164 = `+${digits}`;
  if (!e164) throw new ServiceError(400, 'bad_phone', 'Enter a phone number the store can call, like (704) 555-0100.');
  return e164;
}

function cleanGuest(input = {}) {
  const name = String(input.name || '').trim().replace(/\s+/g, ' ').slice(0, GUEST_LIMITS.name);
  if (name.length < 2) throw new ServiceError(400, 'bad_name', 'Tell the store who the order is for.');
  const phone = normalizePhone(input.phone);
  const emailRaw = String(input.email || '').trim().toLowerCase().slice(0, GUEST_LIMITS.email);
  if (emailRaw && !EMAIL_RE.test(emailRaw)) throw new ServiceError(400, 'bad_email', 'That email doesn’t look right.');
  return { name, phone, email: emailRaw || null };
}

/** The limit key for a phone: an HMAC so the raw number never sits in an index. */
function guestKeyFor(phone, secret = jwtSecret()) {
  return crypto.createHmac('sha256', String(secret)).update(String(phone)).digest('hex').slice(0, 40);
}

/** '+17045550100' → '(704) 555-0100' for US numbers; others unchanged. */
function displayPhone(e164) {
  const m = /^\+1(\d{3})(\d{3})(\d{4})$/.exec(String(e164 || ''));
  return m ? `(${m[1]}) ${m[2]}-${m[3]}` : String(e164 || '');
}

module.exports = { GUEST_LIMITS, normalizePhone, cleanGuest, guestKeyFor, displayPhone };
