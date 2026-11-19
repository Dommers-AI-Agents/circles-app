// backend/services/activityVenueFill.js
//
// The two batched reads behind activityFeedOverlay.withCurrentVenue: the
// saves a page of feed rows point at, then the venues those saves (or the
// rows themselves) name. Only rows missing a picture or a pin are read for,
// so a page of fully stamped rows costs nothing. Never throws: a failed
// read means the rows stay as stored.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { wantsVenueFill, withCurrentVenue } = require('./activityFeedOverlay');

const CHUNK = 100;

async function readAll(db, collection, ids) {
  const asked = [...new Set([...(ids || [])].filter(Boolean).map(String))];
  const out = new Map();
  for (let i = 0; i < asked.length; i += CHUNK) {
    const slice = asked.slice(i, i + CHUNK);
    const docs = await db.getAll(...slice.map((id) => db.collection(collection).doc(id)));
    docs.forEach((doc, index) => { if (doc && doc.exists) out.set(slice[index], doc.data()); });
  }
  return out;
}

/** @returns {Promise<{savesById: Map, venuesById: Map}>} for `withCurrentVenue` */
async function venueFillFor(rows) {
  const empty = { savesById: new Map(), venuesById: new Map() };
  const wanting = (rows || []).filter(wantsVenueFill);
  if (wanting.length === 0) return empty;
  try {
    const db = getFirestore();
    const saveIds = wanting.map((a) => (a.metadata && a.metadata.placeId) || (a.targetType === 'place' ? a.targetId : null));
    const savesById = await readAll(db, COLLECTIONS.PLACES, saveIds);
    const venueIds = wanting.map((a) => (a.metadata && a.metadata.globalPlaceId) || null)
      .concat([...savesById.values()].map((s) => s.globalPlaceId || null));
    const venuesById = await readAll(db, 'globalPlaces', venueIds);
    return { savesById, venuesById };
  } catch (error) {
    console.error('[activity] venue fill failed:', error.message);
    return empty;
  }
}

/** The rows with their venue's picture and pin filled in (one batched read pass). */
async function fillVenues(rows) {
  const maps = await venueFillFor(rows);
  return (rows || []).map((row) => withCurrentVenue(row, maps));
}

module.exports = { venueFillFor, fillVenues };
