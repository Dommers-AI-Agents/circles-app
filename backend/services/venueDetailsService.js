// backend/services/venueDetailsService.js
//
// The ONE way a place's shared details change: name, address/location,
// category, description, phone, website, hours — what every saver sees on
// the place page. They live on the canonical globalPlaces record; saves keep
// only a query cache (name/address/location/geohash/category) refreshed here.
//
// Rule (Wes, 2026-10-01): "the truth layer should be the source we import
// from, Google and/or Apple, and an owner or Admin only can edit." So only a
// super-user or the venue's team (stickerVenues owner + managers) may change
// them — never an ordinary saver, whoever added the save. Personal fields
// (notes, privacy, tags, circle, rating) stay on each person's own save and
// are not this service's business.
//
// Callers: PATCH /places/global/:id/details (Edit Place, tap-to-edit),
// PUT /places/:id (shared fields routed here), PUT /places/:id/update-address,
// PATCH /rewards/venues/:venueId/place (hours screen, MCP store tools).

const geofire = require('geofire-common');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS, buildSearchTokens } = require('../models/GlobalPlace');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const placePhotos = require('./placePhotoService');

const db = getFirestore();

const DETAIL_FIELDS = ['name', 'address', 'location', 'category', 'subcategory', 'description', 'phone', 'website', 'openingHours'];
const VALID_CATEGORIES = ['restaurant', 'cafe', 'bar', 'hotel', 'retail', 'service', 'attraction',
  'entertainment', 'healthcare', 'fitness', 'education', 'outdoor', 'transport', 'finance', 'other'];
const TIME_RE = /^([01]?\d|2[0-3]):[0-5]\d$/;

const NOT_ALLOWED_MESSAGE = "Only the store's owner or an admin can change this place's details. If something's wrong, use Report a problem on the place page.";

// ---------- pure ----------

/** Owner-set hours, in the shape the place page renders. Throws on bad input. */
const cleanHours = (openingHours) => {
  if (!Array.isArray(openingHours) || openingHours.length === 0) {
    throw new ServiceError(400, 'INVALID_HOURS', 'Hours must list at least one day.');
  }
  const seen = new Set();
  return openingHours.map((h, i) => {
    const day = Number(h && h.day);
    if (!Number.isInteger(day) || day < 0 || day > 6) throw new ServiceError(400, 'INVALID_HOURS', `Day ${i + 1}: must be Sunday (0) through Saturday (6).`);
    if (seen.has(day)) throw new ServiceError(400, 'INVALID_HOURS', `Day ${day} appears twice.`);
    seen.add(day);
    const isClosed = h.isClosed === true;
    if (!isClosed && (!TIME_RE.test(h.open || '') || !TIME_RE.test(h.close || ''))) {
      throw new ServiceError(400, 'INVALID_HOURS', `Day ${day}: open and close must be times like 09:00.`);
    }
    return { day, open: isClosed ? null : h.open, close: isClosed ? null : h.close, isClosed };
  }).sort((a, b) => a.day - b.day);
};

const validLocation = (location) => {
  const c = location && Array.isArray(location.coordinates) ? location.coordinates : null;
  if (!c || c.length !== 2) return false;
  const [lng, lat] = c;
  return typeof lng === 'number' && typeof lat === 'number'
    && lng >= -180 && lng <= 180 && lat >= -90 && lat <= 90 && !(lng === -180 && lat === -180);
};

/**
 * Validated detail changes → { venue: globalPlaces update, cache: save-doc
 * cache update }. Only fields present in `fields` are touched. Pure.
 */
const buildDetailUpdates = (fields) => {
  const venue = {};
  const cache = {};
  if (fields.name !== undefined) {
    const name = String(fields.name || '').trim();
    if (!name) throw new ServiceError(400, 'INVALID_NAME', 'A place needs a name.');
    Object.assign(venue, { name, nameLower: name.toLowerCase(), searchTokens: buildSearchTokens(name) });
    cache.name = name;
  }
  if (fields.address !== undefined) {
    const address = String(fields.address || '').trim();
    if (!address) throw new ServiceError(400, 'INVALID_ADDRESS', 'Please enter an address.');
    venue.address = address;
    cache.address = address;
  }
  if (fields.location !== undefined) {
    if (!validLocation(fields.location)) throw new ServiceError(400, 'INVALID_LOCATION', 'That location is not valid.');
    const [lng, lat] = fields.location.coordinates;
    const location = { type: 'Point', coordinates: [lng, lat] };
    venue.location = location;
    venue.geohash = geofire.geohashForLocation([lat, lng]);
    cache.location = location;
    cache.geohash = venue.geohash;
  }
  if (fields.category !== undefined) {
    if (!VALID_CATEGORIES.includes(fields.category)) throw new ServiceError(400, 'INVALID_CATEGORY', 'Pick one of the listed categories.');
    venue.category = fields.category;
    cache.category = fields.category;
  }
  if (fields.subcategory !== undefined) venue.subcategory = fields.subcategory || null;
  if (fields.description !== undefined) {
    // Prose only — contact details have their own fields
    venue.description = String(fields.description || '')
      .split('\n').filter((line) => !/^\s*(Phone|Website):/i.test(line)).join('\n').trim() || null;
  }
  if (fields.phone !== undefined) venue['googleData.phone'] = String(fields.phone || '').trim() || null;
  if (fields.website !== undefined) venue['googleData.website'] = String(fields.website || '').trim() || null;
  if (fields.openingHours !== undefined) {
    venue['googleData.openingHours'] = cleanHours(fields.openingHours);
    // Owner-set hours survive any later Google refresh
    venue['googleData.hoursSource'] = 'owner';
  }
  return { venue, cache };
};

/** The detail fields present in a request body (others ignored). */
const pickDetailFields = (body) => {
  const out = {};
  DETAIL_FIELDS.forEach((f) => { if (body && body[f] !== undefined) out[f] = body[f]; });
  return out;
};

// Loose comparison so an unchanged value an older app echoes back (address
// reformatted with commas, "USA" vs "United States", phone punctuation)
// doesn't read as an edit.
const looseText = (v) => String(v == null ? '' : v).toLowerCase()
  .replace(/\bunited states\b/g, 'usa').replace(/[^a-z0-9]/g, '');

// "+1 (704) 555-0100" and "704-555-0100" are the same number
const phoneDigits = (v) => {
  const digits = String(v == null ? '' : v).replace(/\D/g, '');
  return digits.length === 11 && digits.startsWith('1') ? digits.slice(1) : digits;
};

/**
 * Which of `fields` actually differ from the venue as people see it. Used
 * by PUT /places/:id, where builds up to 1.3.6 resend name/address/category
 * with every save even when only notes changed.
 */
const changedDetailFields = (fields, venue) => {
  const g = (venue && venue.googleData) || {};
  const current = {
    name: venue && venue.name, address: venue && venue.address, category: venue && venue.category,
    subcategory: venue && venue.subcategory, description: venue && venue.description,
    phone: g.phone, website: g.website
  };
  return Object.keys(fields).filter((f) => {
    if (f === 'location') {
      const a = fields.location && fields.location.coordinates;
      const b = venue && venue.location && venue.location.coordinates;
      if (!Array.isArray(a) || !Array.isArray(b)) return !!a;
      return Math.abs(a[0] - b[0]) > 1e-5 || Math.abs(a[1] - b[1]) > 1e-5;
    }
    if (f === 'openingHours') return JSON.stringify(fields.openingHours) !== JSON.stringify(g.openingHours || null);
    if (f === 'phone') return phoneDigits(fields.phone) !== phoneDigits(current.phone);
    return looseText(fields[f]) !== looseText(current[f]);
  });
};

// ---------- Firestore ----------

/** Super-user or the venue's team. */
const canEditDetails = async (user, globalPlaceId, venueData) =>
  (await placePhotos.rightsFor(user, globalPlaceId, venueData)).canManage;

/**
 * Apply detail changes to a venue. Throws ServiceError 403 unless the user
 * may edit, 404 for an unknown venue, 400 for bad values.
 * Returns the venue's details after the change.
 */
async function updateVenueDetails({ globalPlaceId, user, fields }) {
  const ref = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(String(globalPlaceId || ''));
  const doc = globalPlaceId ? await ref.get() : null;
  if (!doc || !doc.exists || doc.data().deletedAt) throw new ServiceError(404, 'PLACE_NOT_FOUND', 'Place not found.');
  if (!(await canEditDetails(user, doc.id, doc.data()))) {
    throw new ServiceError(403, 'DETAILS_LOCKED', NOT_ALLOWED_MESSAGE);
  }
  const { venue, cache } = buildDetailUpdates(pickDetailFields(fields));
  if (Object.keys(venue).length === 0) throw new ServiceError(400, 'NOTHING_TO_UPDATE', 'Nothing to change.');

  const now = new Date().toISOString();
  await ref.update({ ...venue, updatedAt: now });

  // Every save's query cache follows the canonical record
  if (Object.keys(cache).length > 0) {
    const saves = await db.collection(COLLECTIONS.PLACES).where('globalPlaceId', '==', doc.id).get();
    for (let i = 0; i < saves.docs.length; i += 400) {
      const batch = db.batch();
      saves.docs.slice(i, i + 400).forEach((d) => batch.update(d.ref, { ...cache, updatedAt: now }));
      await batch.commit();
    }
  }
  // The store's copy of the place name (the rewards brand name stays the owner's own)
  if (venue.name) {
    const store = await placePhotos.venueForPlace(doc.id, doc.data()).catch(() => null);
    if (store && store.venueId) {
      await db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(store.venueId)
        .update({ placeName: venue.name, updatedAt: now })
        .catch((e) => console.error('⚠️ [venue-details] store name sync failed:', e.message));
    }
  }

  const g = (await ref.get()).data();
  return detailsOf(doc.id, g);
}

const detailsOf = (globalPlaceId, g) => ({
  globalPlaceId,
  name: g.name || null,
  address: g.address || null,
  location: g.location || null,
  category: g.category || null,
  subcategory: g.subcategory || null,
  description: g.description || null,
  phone: (g.googleData || {}).phone || null,
  website: (g.googleData || {}).website || null,
  openingHours: (g.googleData || {}).openingHours || null
});

module.exports = {
  DETAIL_FIELDS,
  VALID_CATEGORIES,
  NOT_ALLOWED_MESSAGE,
  cleanHours,
  buildDetailUpdates,
  pickDetailFields,
  changedDetailFields,
  canEditDetails,
  updateVenueDetails,
  detailsOf
};
