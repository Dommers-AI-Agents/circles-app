// backend/services/activity/hiddenPlaceGate.js
//
// An activity about a place hidden from the public (approvalStatus pending or
// rejected: a home, a hand-named spot) reaches nobody but the person who did
// it (Wes, 2026-11-16: Brittany didn't want her mom's and dad's houses on the
// feed). The row is still written, owner-only, so their own Activity tab and
// history keep it.
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');

/** The venue id an activity is about, without reading anything. Pure. */
function directVenueId(targetType, targetId, metadata = {}) {
  if (metadata.globalPlaceId) return String(metadata.globalPlaceId);
  if (targetType === 'global_place') return targetId ? String(targetId) : null;
  return null;
}

/**
 * True when the activity is about a hidden venue. Reads at most two docs;
 * a failed read never hides (and never breaks) the activity.
 */
async function isAboutHiddenVenue(targetType, targetId, metadata = {}, { db = getFirestore() } = {}) {
  try {
    const { isHiddenVenue } = require('../placeApproval');
    let venueId = directVenueId(targetType, targetId, metadata);
    const saveId = metadata.placeId || (targetType === 'place' ? targetId : null);
    if (!venueId && targetType === 'place' && targetId) {
      // A place row's target is a venue id or a save id
      const venue = await db.collection('globalPlaces').doc(String(targetId)).get();
      if (venue.exists) return isHiddenVenue(venue.data());
    }
    if (!venueId && saveId) {
      const save = await db.collection(COLLECTIONS.PLACES).doc(String(saveId)).get();
      venueId = save.exists ? save.data().globalPlaceId || null : null;
    }
    if (!venueId) return false;
    const venue = await db.collection('globalPlaces').doc(venueId).get();
    return venue.exists && isHiddenVenue(venue.data());
  } catch (error) {
    console.warn('⚠️ Hidden-place check skipped:', error.message);
    return false;
  }
}

module.exports = { isAboutHiddenVenue, directVenueId };
