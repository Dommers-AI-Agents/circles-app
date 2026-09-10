// services/placeVenueSync.js
// Canonical-venue write propagation shared by placeController and
// placeVenueMaintenanceController (split out of firebasePlaceController.js).

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS, buildSearchTokens } = require('../models/GlobalPlace');
const { sanitizeVenueDescription } = require('../utils/venueDescriptionSanitizer');
const { VENUE_TOP_FIELDS, VENUE_GOOGLE_FIELDS } = require('../services/placeReadService');
const db = getFirestore();

// Translate legacy-shaped venue updates into a globalPlaces update payload
const buildGlobalVenueUpdates = (updateData) => {
  const updates = {};
  VENUE_TOP_FIELDS.forEach(field => {
    if (updateData[field] !== undefined) updates[field] = updateData[field];
  });
  // Old iOS builds echo their synthesized placeholder description ("A dining
  // establishment in …") on every edit — scrub it, and if nothing real
  // remains, leave the canonical description alone rather than nulling it
  if (typeof updates.description === 'string') {
    const sanitized = sanitizeVenueDescription(updates.description);
    if (sanitized !== updates.description) {
      if (sanitized) updates.description = sanitized;
      else delete updates.description;
    }
  }
  VENUE_GOOGLE_FIELDS.forEach(field => {
    if (updateData[field] !== undefined) updates[`googleData.${field}`] = updateData[field];
  });
  if (updates.name !== undefined) {
    updates.nameLower = (updates.name || '').toLowerCase();
    updates.searchTokens = buildSearchTokens(updates.name);
  }
  return updates;
};

// Push venue-field changes to the canonical record and keep the denormalized
// query cache (name/address/location/geohash/category) in sync on the venue's
// other saved copies. Runs on venue EDITS only — rare and bounded.
const propagateVenueUpdates = async (placeId, globalPlaceId, updateData) => {
  if (!globalPlaceId) return;
  const globalUpdates = buildGlobalVenueUpdates(updateData);
  if (Object.keys(globalUpdates).length === 0) return;
  const now = new Date().toISOString();

  await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId)
    .update({ ...globalUpdates, updatedAt: now })
    .catch(err => console.error('⚠️ Failed to update canonical venue:', err.message));

  const CACHE_FIELDS = ['name', 'address', 'location', 'geohash', 'category'];
  const cacheUpdates = {};
  CACHE_FIELDS.forEach(field => {
    if (updateData[field] !== undefined) cacheUpdates[field] = updateData[field];
  });
  if (Object.keys(cacheUpdates).length === 0) return;

  try {
    const siblings = await db.collection(COLLECTIONS.PLACES)
      .where('globalPlaceId', '==', globalPlaceId)
      .get();
    const batch = db.batch();
    let pending = 0;
    siblings.docs.forEach(doc => {
      if (doc.id !== placeId) {
        batch.update(doc.ref, { ...cacheUpdates, updatedAt: now });
        pending++;
      }
    });
    if (pending > 0) await batch.commit();
  } catch (err) {
    console.error('⚠️ Failed to sync venue cache to copies:', err.message);
  }
};

module.exports = {
  buildGlobalVenueUpdates,
  propagateVenueUpdates
};
