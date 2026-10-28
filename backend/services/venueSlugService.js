// backend/services/venueSlugService.js — the store's web address:
// order.favcircles.com/<slug> (Wes, 2026-10-28). One slug per store, minted
// from its name, owner-editable. Firestore has no unique constraint, so a
// reservation doc venueSlugs/{slug} = { venueId, createdAt, retiredAt } is
// claimed in a transaction; a renamed store keeps its old slug as a retired
// alias so links already printed or published still land (301).
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { nowIso } = require('../utils/ids');

const SLUGS = 'venueSlugs';
const ORDER_PAGE_BASE = process.env.ORDER_PAGE_BASE_URL || 'https://order.favcircles.com';

// Paths the ordering host serves itself, and words that would mislead
const RESERVED = new Set([
  'o', 'api', 'public', 'admin', 'app', 's', 'place', 'user', 'connect', 'circle', 'video', 'share',
  'static', 'assets', 'health', 'order', 'orders', 'favcircles', 'www', 'demo', 'test', 'menu',
  'favicon.ico', 'robots.txt', 'well-known', 'login', 'signup'
]);
const SLUG_RE = /^[a-z0-9](?:[a-z0-9-]{1,46}[a-z0-9])?$/;
const MIN = 3;
const MAX = 48;

/** "Café & Co." → "cafe-and-co". Empty when nothing usable is left. */
function slugify(name) {
  return String(name || '')
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, MAX)
    .replace(/-+$/g, '');
}

/** "123 Main St, Charlotte, NC 28202, USA" → "charlotte" (the segment before the state). */
function cityFromAddress(address) {
  const parts = String(address || '').split(',').map((p) => p.trim()).filter(Boolean);
  if (parts.length < 3) return parts.length === 2 ? slugify(parts[1].replace(/\s+[A-Z]{2}\s*\d{5}(-\d{4})?$/, '')) : '';
  // Drop a trailing country, then the "NC 28202" segment, and take what's left at the end
  const tail = /^(usa|united states|us|canada)$/i.test(parts[parts.length - 1]) ? parts.slice(0, -1) : parts;
  const city = tail.length >= 2 ? tail[tail.length - 2] : tail[tail.length - 1];
  return slugify(city);
}

/** The names to try, best first. */
function slugCandidates(venue, { attempts = 6 } = {}) {
  const base = slugify(venue.venueName || venue.placeName) || 'store';
  const padded = base.length < MIN ? `${base}-store` : base;
  const city = cityFromAddress(venue.placeAddress);
  const out = [padded];
  if (city && !padded.endsWith(`-${city}`)) out.push(`${padded}-${city}`.slice(0, MAX).replace(/-+$/g, ''));
  for (let n = 2; out.length < attempts + 2; n += 1) out.push(`${padded.slice(0, MAX - String(n).length - 1)}-${n}`);
  return out.filter((s) => !RESERVED.has(s));
}

function validateSlug(slug) {
  const s = String(slug || '').trim().toLowerCase();
  if (!SLUG_RE.test(s) || s.length < MIN) {
    throw new ServiceError(400, 'bad_slug', 'Use 3 to 48 letters, numbers and dashes, like wooden-robot-brewery.');
  }
  if (RESERVED.has(s)) throw new ServiceError(400, 'bad_slug', 'That address is reserved. Try another.');
  return s;
}

const pageUrl = (slug) => `${ORDER_PAGE_BASE}/${slug}`;

/** { venueId, retired } for a slug or a retired alias; null when unknown. */
async function resolve(slug, { db = getFirestore() } = {}) {
  const s = String(slug || '').toLowerCase();
  if (!SLUG_RE.test(s)) return null;
  const doc = await db.collection(SLUGS).doc(s).get();
  if (!doc.exists) return null;
  const data = doc.data();
  return { venueId: data.venueId, retired: !!data.retiredAt };
}

/**
 * Reserve `slug` for the venue in one transaction: free (or already this
 * venue's), retire the venue's old slug, stamp the venue. Throws
 * ServiceError 409 slug_taken when another store holds it.
 */
async function claim(venueId, slug, { db = getFirestore(), now = nowIso() } = {}) {
  const venueRef = db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venueId);
  const slugRef = db.collection(SLUGS).doc(slug);
  return db.runTransaction(async (tx) => {
    const [venueDoc, slugDoc] = await Promise.all([tx.get(venueRef), tx.get(slugRef)]);
    if (!venueDoc.exists) throw new ServiceError(404, 'store_not_found', 'That store wasn’t found.');
    const current = venueDoc.data().slug || null;
    if (slugDoc.exists && slugDoc.data().venueId !== venueId) {
      throw new ServiceError(409, 'slug_taken', 'Another store already has that address. Try another.');
    }
    if (current === slug) return slug;
    tx.set(slugRef, { venueId, createdAt: (slugDoc.exists && slugDoc.data().createdAt) || now, retiredAt: null });
    if (current && current !== slug) {
      tx.set(db.collection(SLUGS).doc(current), { venueId, retiredAt: now }, { merge: true });
    }
    tx.update(venueRef, { slug, slugUpdatedAt: now, updatedAt: now });
    return slug;
  });
}

/** The venue's slug, minting one from its name when it has none. Null for virtual stores. */
async function ensureSlug(venue, { db = getFirestore() } = {}) {
  if (!venue || !venue.venueId) return null;
  if (venue.slug) return venue.slug;
  if (venue.isVirtual === true) return null;
  for (const candidate of slugCandidates(venue)) {
    try {
      const slug = await claim(venue.venueId, candidate, { db });
      venue.slug = slug;
      return slug;
    } catch (error) {
      if (!(error instanceof ServiceError && error.code === 'slug_taken')) throw error;
    }
  }
  return null;
}

/** Owner picks the address. Returns { slug, url }. */
async function setSlug(venue, requested, { db = getFirestore() } = {}) {
  const slug = validateSlug(requested);
  await claim(venue.venueId, slug, { db });
  venue.slug = slug;
  return { slug, url: pageUrl(slug) };
}

module.exports = { SLUGS, RESERVED, slugify, cityFromAddress, slugCandidates, validateSlug, pageUrl, resolve, claim, ensureSlug, setSlug };
