// services/placeVenueSync.js
// Canonical-venue write propagation shared by placeController and
// placeVenueMaintenanceController (split out of firebasePlaceController.js).

const { getFirestore } = require('../config/firebase');
const { GLOBAL_COLLECTIONS, buildSearchTokens, geohashForLocation } = require('../models/GlobalPlace');
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
  // A moved venue moves in distance-first search too
  if (updates.location !== undefined) {
    updates.geohash = geohashForLocation(updates.location);
  }
  return updates;
};

// Push venue-level changes to the canonical record. Shared details (name,
// address, location, category, description, phone, website, hours) go
// through THE write path — venueDetailsService.applyVenueDetails — so every
// save's cache and the store record follow; Google's numbers and service
// flags (rating, review count, delivery, …) are written to the canonical
// record here. Callers decide who may: both strip client detail fields first
// (PUT /places/:id routes them through updateVenueDetails; a Google refresh
// sends only ratings/flags). Best-effort: never throws.
const propagateVenueUpdates = async (placeId, globalPlaceId, updateData) => {
  if (!globalPlaceId) return;
  const venueDetails = require('./venueDetailsService');
  const details = venueDetails.pickDetailFields(updateData);
  const rest = { ...updateData };
  [...venueDetails.DETAIL_FIELDS, 'geohash'].forEach((field) => delete rest[field]);

  if (Object.keys(details).length > 0) {
    await venueDetails.applyVenueDetails(globalPlaceId, details)
      .catch(err => console.error('⚠️ Failed to update venue details:', err.message));
  }

  const globalUpdates = buildGlobalVenueUpdates(rest);
  if (Object.keys(globalUpdates).length === 0) return;
  await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId)
    .update({ ...globalUpdates, updatedAt: new Date().toISOString() })
    .catch(err => console.error('⚠️ Failed to update canonical venue:', err.message));
};

module.exports = {
  buildGlobalVenueUpdates,
  propagateVenueUpdates
};
