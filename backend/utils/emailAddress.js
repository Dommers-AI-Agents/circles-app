// backend/utils/emailAddress.js — one rule for "is this ONE email address".
//
// Security audit 2026-10-01: contact invites passed whatever the client sent
// straight to nodemailer, which reads "a@x.com, b@y.com" (or a value with a
// newline) as several recipients — one invite became a mailing list. Every
// user-supplied recipient goes through here: a single address, no commas,
// semicolons, angle brackets, whitespace or control characters.

const EMAIL_RE = /^[^\s@,;<>"()[\]\\]+@[^\s@,;<>"()[\]\\]+\.[^\s@,;<>"()[\]\\]{2,}$/;
const MAX_LENGTH = 254;

/** Trimmed, lower-cased candidate; '' for anything that isn't a string. */
const normalizeEmail = (value) => (typeof value === 'string' ? value.trim().toLowerCase() : '');

/** True only for exactly one plausible address (already normalized or not). */
function isValidEmailAddress(value) {
  const email = normalizeEmail(value);
  if (!email || email.length > MAX_LENGTH) return false;
  // eslint-disable-next-line no-control-regex
  if (/[\x00-\x1F\x7F]/.test(email)) return false;
  return EMAIL_RE.test(email);
}

module.exports = { isValidEmailAddress, normalizeEmail, MAX_LENGTH };
