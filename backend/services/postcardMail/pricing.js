// backend/services/postcardMail/pricing.js
//
// Postcard specials ("$1.99 today only", Wes 2026-10-08). The regular price
// stays POSTCARD_PRICE_CENTS_US; specials live in one Firestore doc that
// super-users edit from the app (no deploy), each a price, a label and a
// time window. The lowest special running right now wins.
//
// The price someone saw is the price they pay: config() hands the app a
// signed quote (price + expiry + user; refreshed by the address check just
// before sending), and an order presenting a valid quote is held at that price even if the special ended while they wrote
// the card. Without one, the order is priced at that moment.
const crypto = require('crypto');
const { ServiceError } = require('../../utils/serviceError');

const DOC = ['appConfig', 'postcardPricing'];
// Long enough for a slow card: Apple Pay opens on the Send tap with no
// network first, so the app can't re-price at that moment
const QUOTE_MINUTES = 120;
const LABEL_MAX = 40;
const MAX_SPECIALS = 20;
const CACHE_MS = 60 * 1000;
// Below this a card costs more to print, mail and process than it brings in
const minPriceCents = () => Number(process.env.POSTCARD_MIN_PRICE_CENTS) || 149;

let cache = null;

const secret = () => `${process.env.JWT_SECRET || ''}:postcard-price`;
const sign = (payload) => crypto.createHmac('sha256', secret()).update(payload).digest('base64url');

/** The price right now: the lowest special running at `now`, else regular. Pure. */
function currentPrice(regularCents, specials, now = new Date()) {
  const t = now.getTime();
  const running = (specials || [])
    .filter((s) => Date.parse(s.startsAt) <= t && t < Date.parse(s.endsAt) && s.priceCents < regularCents)
    .sort((a, b) => a.priceCents - b.priceCents)[0];
  return running
    ? { priceCents: running.priceCents, regularPriceCents: regularCents,
        special: { id: running.id, label: running.label, endsAt: running.endsAt } }
    : { priceCents: regularCents, regularPriceCents: regularCents, special: null };
}

/** "199.1791234567890.<sig>" for this user, valid QUOTE_MINUTES. */
function issueQuote(userId, priceCents, now = new Date()) {
  const expires = now.getTime() + QUOTE_MINUTES * 60 * 1000;
  const body = `${priceCents}.${expires}`;
  return `${body}.${sign(`${body}.${userId}`)}`;
}

/** The quoted price if the token is genuine, this user's and unexpired; else null. */
function verifyQuote(token, userId, now = new Date()) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return null;
  const [price, expires, sig] = parts;
  const expected = sign(`${price}.${expires}.${userId}`);
  if (sig.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  if (Number(expires) < now.getTime()) return null;
  const cents = Number(price);
  return Number.isInteger(cents) && cents > 0 ? cents : null;
}

/** Validates one special from the admin form. Pure; throws ServiceError. */
function normalizeSpecial(input, regularCents, now = new Date()) {
  const priceCents = Math.round(Number(input && input.priceCents));
  if (!Number.isFinite(priceCents) || priceCents < minPriceCents()) {
    throw new ServiceError(400, 'price_too_low', `A special can't go below $${(minPriceCents() / 100).toFixed(2)}.`);
  }
  if (priceCents >= regularCents) {
    throw new ServiceError(400, 'not_a_special', `A special has to be under the regular $${(regularCents / 100).toFixed(2)}.`);
  }
  const startsAt = Date.parse(input.startsAt || now.toISOString());
  const endsAt = Date.parse(input.endsAt);
  if (!Number.isFinite(startsAt) || !Number.isFinite(endsAt) || endsAt <= startsAt) {
    throw new ServiceError(400, 'bad_window', 'Pick an end time after the start.');
  }
  if (endsAt <= now.getTime()) throw new ServiceError(400, 'bad_window', 'That special would already be over.');
  const label = String(input.label || '').trim().slice(0, LABEL_MAX) || 'Special';
  return {
    id: crypto.randomBytes(6).toString('hex'),
    priceCents,
    label,
    startsAt: new Date(startsAt).toISOString(),
    endsAt: new Date(endsAt).toISOString()
  };
}

class PostcardPricing {
  constructor(getDb) { this.getDb = getDb; }
  get ref() { return this.getDb().collection(DOC[0]).doc(DOC[1]); }

  async specials({ fresh = false } = {}) {
    if (!fresh && cache && Date.now() - cache.at < CACHE_MS) return cache.specials;
    const snap = await this.ref.get();
    const specials = snap.exists && Array.isArray(snap.data().specials) ? snap.data().specials : [];
    cache = { at: Date.now(), specials };
    return specials;
  }

  async current(regularCents, now = new Date()) {
    return currentPrice(regularCents, await this.specials(), now);
  }

  /** Admin list: running and upcoming first, then the last few that ended. */
  async list(now = new Date()) {
    const all = await this.specials({ fresh: true });
    const t = now.getTime();
    return all.slice().sort((a, b) => {
      const aOver = Date.parse(a.endsAt) <= t, bOver = Date.parse(b.endsAt) <= t;
      if (aOver !== bOver) return aOver ? 1 : -1;
      return Date.parse(a.startsAt) - Date.parse(b.startsAt);
    });
  }

  async add(input, regularCents, { createdBy, now = new Date() } = {}) {
    const special = { ...normalizeSpecial(input, regularCents, now), createdBy: createdBy || null, createdAt: now.toISOString() };
    const t = now.getTime();
    // Old ones drop off: keep the running/upcoming and a short history
    const kept = (await this.specials({ fresh: true }))
      .sort((a, b) => Date.parse(b.endsAt) - Date.parse(a.endsAt))
      .filter((s, i) => Date.parse(s.endsAt) > t || i < 5)
      .slice(0, MAX_SPECIALS - 1);
    await this.ref.set({ specials: [...kept, special], updatedAt: now.toISOString() }, { merge: true });
    cache = null;
    return special;
  }

  /** Ends a special now (kept in the list as history). */
  async end(id, now = new Date()) {
    const all = await this.specials({ fresh: true });
    const target = all.find((s) => s.id === id);
    if (!target) throw new ServiceError(404, 'not_found', 'That special is gone.');
    const nowIso = now.toISOString();
    const next = all.map((s) => (s.id === id && Date.parse(s.endsAt) > now.getTime()
      ? { ...s, endsAt: nowIso, startsAt: Date.parse(s.startsAt) > now.getTime() ? nowIso : s.startsAt } : s));
    await this.ref.set({ specials: next, updatedAt: nowIso }, { merge: true });
    cache = null;
  }
}

module.exports = { PostcardPricing, currentPrice, issueQuote, verifyQuote, normalizeSpecial, minPriceCents, QUOTE_MINUTES,
  _resetCache: () => { cache = null; } };
