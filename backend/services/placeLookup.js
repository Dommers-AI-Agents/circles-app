// backend/services/placeLookup.js
//
// A place's CURRENT name, address and cover photo for anything that shows a
// stored copy (a moment's place line, a suggestion's place card, a share
// link). The canonical venue record (globalPlaces) is the one source; a
// record keeps the place's id, and a stored name is only a fallback for a
// venue that is gone (Wes, 2026-10-31: "make sure data points like store
// name are stored in the db and pulled from one place").
//
// One batched read per response (db.getAll in chunks), never one per row.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');

const CHUNK = 100;

const getAllChunked = async (db, collection, ids) => {
  const docs = [];
  for (let i = 0; i < ids.length; i += CHUNK) {
    const slice = ids.slice(i, i + CHUNK);
    docs.push(...await db.getAll(...slice.map((id) => db.collection(collection).doc(id))));
  }
  return docs;
};

const cardOf = (id, g) => ({
  globalPlaceId: id,
  name: g.name || null,
  address: g.address || null,
  photo: require('./placePhotoService').coverUrl(g.photos)
});

/** @returns {Promise<Map<string, {globalPlaceId, name, address, photo}>>} live venues by id */
async function fetchVenuesById(globalPlaceIds) {
  const db = getFirestore();
  const asked = [...new Set([...(globalPlaceIds || [])].filter(Boolean).map(String))];
  const out = new Map();
  const docs = await getAllChunked(db, GLOBAL_COLLECTIONS.GLOBAL_PLACES, asked);
  docs.forEach((doc) => {
    if (!doc || !doc.exists) return;
    const g = doc.data();
    if (g.deletedAt) return;
    out.set(doc.id, cardOf(doc.id, g));
  });
  return out;
}

/**
 * Saves (places) → their venue's card. A moment or suggestion stores the
 * save id it was made from; the venue is the save's globalPlaceId. An id
 * that is not a save is tried as a venue id. Unlinked saves are absent.
 * @returns {Promise<Map<string, {globalPlaceId, name, address, photo}>>} keyed by the id given
 */
async function fetchVenuesForSaves(placeIds) {
  const db = getFirestore();
  const asked = [...new Set([...(placeIds || [])].filter(Boolean).map(String))];
  const venueOf = new Map();
  const saves = await getAllChunked(db, COLLECTIONS.PLACES, asked);
  saves.forEach((doc, i) => {
    const gid = doc && doc.exists ? doc.data().globalPlaceId : asked[i];
    if (gid) venueOf.set(asked[i], String(gid));
  });
  const venues = await fetchVenuesById(venueOf.values());
  const out = new Map();
  venueOf.forEach((gid, placeId) => { if (venues.has(gid)) out.set(placeId, venues.get(gid)); });
  return out;
}

/**
 * A row with the venue's current name/address (and photo, when asked)
 * written over its stored copies. Returns a NEW object; the row as it was
 * when no venue is known. `fields` maps card fields to row field names.
 */
function withCurrentPlace(row, venue, { name, address, photo } = {}) {
  if (!row || !venue) return row;
  const out = { ...row };
  if (name && venue.name) out[name] = venue.name;
  if (address && venue.address) out[address] = venue.address;
  if (photo && venue.photo) out[photo] = venue.photo;
  return out;
}

/** Moments: placeName/placeAddress from the venue of each moment's save. */
async function withCurrentMomentPlaces(videos) {
  const list = (videos || []).filter(Boolean);
  if (list.length === 0) return videos;
  const venues = await fetchVenuesForSaves(list.map((v) => v.placeId)).catch((e) => {
    console.error('⚠️ [placeLookup] moment places lookup failed:', e.message);
    return new Map();
  });
  return videos.map((v) => (v ? withCurrentPlace(v, venues.get(String(v.placeId || '')), { name: 'placeName', address: 'placeAddress' }) : v));
}

module.exports = { fetchVenuesById, fetchVenuesForSaves, withCurrentPlace, withCurrentMomentPlaces };
