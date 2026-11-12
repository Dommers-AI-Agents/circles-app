// backend/services/emailTracking.js
//
// Did they click? Every email we send gets its links rewritten to
// ${APP_LINK_BASE}/e/c?… (a signed redirect) and a 1×1 pixel at the end of
// the body (/e/o?…). The redirect records the click, then forwards. Pure:
// no Firestore here (services/emailEngagement.js records; routes/
// emailTrackingRoutes.js serves). Wes, 2026-11-12: understanding what a
// person does with our email is not bothering them — no opt-out, no gating.
//
// The signature covers (sendId, recipient, kind, url): a link that doesn't
// verify is refused, so /e/c is never an open redirect off our domain.
//
// Left alone: mailto:, tel:, cid:, in-page anchors, links already under /e/,
// the unsubscribe link (RFC 8058 one-click posts straight to it) and every
// src= (images). The text part is untouched: a text link is a bare URL
// people read, not a button they tap.

const crypto = require('crypto');

const BASE = () => (process.env.APP_LINK_BASE || 'https://api.favcircles.com').replace(/\/$/, '');
const secret = () => process.env.JWT_SECRET || process.env.UNSUBSCRIBE_SECRET || '';

const b64url = (s) => Buffer.from(String(s), 'utf8').toString('base64url');
const fromB64url = (s) => Buffer.from(String(s || ''), 'base64url').toString('utf8');

function sign({ sendId, to, kind, url = '' }) {
  return crypto.createHmac('sha256', secret()).update(`${sendId}\n${to}\n${kind}\n${url}`).digest('base64url').slice(0, 32);
}

function verify(params) {
  if (!secret() || !params || !params.sig) return false;
  const expected = Buffer.from(sign(params));
  const given = Buffer.from(String(params.sig));
  return expected.length === given.length && crypto.timingSafeEqual(expected, given);
}

/** A short, log-safe name for an email from its subject when the sender gave none */
function kindFromSubject(subject) {
  return String(subject || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40) || 'email';
}

const SKIP = /^(mailto:|tel:|sms:|cid:|#|javascript:)/i;

function skips(url) {
  if (!url || SKIP.test(url)) return true;
  if (!/^https?:\/\//i.test(url)) return true;
  if (url.includes('/api/email/unsubscribe')) return true;
  if (url.startsWith(`${BASE()}/e/`)) return true;
  return false;
}

function clickUrl({ sendId, to, kind, url }) {
  const sig = sign({ sendId, to, kind, url });
  return `${BASE()}/e/c?i=${encodeURIComponent(sendId)}&t=${b64url(to)}&k=${encodeURIComponent(kind)}&u=${b64url(url)}&s=${sig}`;
}

function pixelUrl({ sendId, to, kind }) {
  const sig = sign({ sendId, to, kind, url: '' });
  return `${BASE()}/e/o?i=${encodeURIComponent(sendId)}&t=${b64url(to)}&k=${encodeURIComponent(kind)}&s=${sig}`;
}

const unescapeAttr = (s) => s.replace(/&amp;/g, '&');
const escapeAttr = (s) => s.replace(/&/g, '&amp;');

/**
 * Pure: the html with every trackable href rewritten and the pixel appended.
 * @returns {{ html: string, links: number }}
 */
function instrumentHtml(html, { sendId, to, kind }) {
  if (!html || !sendId || !to) return { html, links: 0 };
  let links = 0;
  const out = String(html).replace(/(<a\b[^>]*?\shref=)(["'])([^"']*)\2/gi, (m, pre, q, raw) => {
    const url = unescapeAttr(raw.trim());
    if (skips(url)) return m;
    links += 1;
    return `${pre}${q}${escapeAttr(clickUrl({ sendId, to, kind, url }))}${q}`;
  });
  const pixel = `<img src="${escapeAttr(pixelUrl({ sendId, to, kind }))}" width="1" height="1" alt="" style="display:block;width:1px;height:1px;border:0;opacity:0.01">`;
  const withPixel = /<\/body>/i.test(out) ? out.replace(/<\/body>/i, `${pixel}</body>`) : `${out}\n${pixel}`;
  return { html: withPixel, links };
}

/** The mail options nodemailer gets: html instrumented, our own keys removed. */
function instrumentMail(mailOptions, { now = Date.now } = {}) {
  const { kind: givenKind, ...rest } = mailOptions || {};
  const to = String(rest.to || '').trim().toLowerCase();
  if (!rest.html || !to || to.includes(',')) return { mailOptions: rest, sendId: null, kind: null, links: 0 };
  const kind = givenKind || kindFromSubject(rest.subject);
  const sendId = `${now().toString(36)}${crypto.randomBytes(4).toString('hex')}`;
  const { html, links } = instrumentHtml(rest.html, { sendId, to, kind });
  return { mailOptions: { ...rest, html }, sendId, kind, links };
}

/** The click/open params from a request's query, or null when the signature fails. */
function readParams(query) {
  const params = {
    sendId: String(query.i || ''),
    to: fromB64url(query.t),
    kind: String(query.k || ''),
    url: query.u ? fromB64url(query.u) : '',
    sig: String(query.s || '')
  };
  if (!params.sendId || !params.to || !params.kind) return null;
  if (params.url && !/^https?:\/\//i.test(params.url)) return null;
  return verify(params) ? params : null;
}

module.exports = { instrumentHtml, instrumentMail, readParams, sign, verify, kindFromSubject, clickUrl, pixelUrl, skips };
