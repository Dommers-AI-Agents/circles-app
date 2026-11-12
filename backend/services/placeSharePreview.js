// services/placeSharePreview.js
//
// What the public /place/:placeId share page (server.js) may say about a
// place. The page answers to anyone — browsers, link-preview crawlers,
// whoever was forwarded the link — so it only describes a place an anonymous
// viewer could see: a live save whose circle is public and whose own privacy
// doesn't narrow it. It used to print the name, address and photo of ANY
// place id, private ones included (security audit 2026-10-01).

const { canViewCircle, isPlaceVisibleToViewer, canSeePlace } = require('./visibility');
const { isHiddenVenue } = require('./placeApproval');
const { isStreetLineName } = require('./googleAddressGuard');

const isLive = (data) => !!data && (data.deletedAt === null || data.deletedAt === undefined);

const firstPhotoUrl = (photos) => {
  const first = (photos || [])[0];
  return typeof first === 'string' ? first : (first && first.url) || null;
};

/**
 * @param {object} db  Firestore
 * @param {string} placeId  a save id (`places`) or a venue id (`globalPlaces`)
 * @returns {Promise<{name, address, photoUrl}|null>} null → generic page
 */
async function publicPlacePreview(db, placeId) {
  const isPublicSave = async (save) => {
    if (!isLive(save) || !save.circleId) return false;
    const circleDoc = await db.collection('circles').doc(String(save.circleId)).get();
    // Public to anyone with the link: the place's own privacy, else its
    // circle's (Wes, 2026-11-03: a place's privacy always wins)
    return circleDoc.exists && isLive(circleDoc.data()) && canSeePlace(save, circleDoc.data(), null, null);
  };

  let shown = null;
  const saveDoc = await db.collection('places').doc(placeId).get();
  if (saveDoc.exists) {
    if (await isPublicSave(saveDoc.data())) shown = saveDoc.data();
  } else {
    // A venue id: describe it only if someone saved it publicly — a venue
    // record can be a private address that only private saves point at.
    const venueDoc = await db.collection('globalPlaces').doc(placeId).get();
    if (venueDoc.exists) {
      const saves = await db.collection('places').where('globalPlaceId', '==', placeId).limit(10).get();
      for (const d of saves.docs) {
        if (await isPublicSave(d.data())) {
          shown = { ...venueDoc.data(), photos: d.data().photos };
          break;
        }
      }
      // A business with a Google listing that nobody has saved yet (a shared
      // farmers market or event venue, 2026-11-12) is public already. Once
      // anyone saves it, their privacy decides, as above. Never a venue
      // waiting for approval, and never one that is just a street address.
      const venue = venueDoc.data();
      if (!shown && saves.empty && isLive(venue) && venue.googlePlaceId
          && !isHiddenVenue(venue) && !isStreetLineName(venue.name, venue.address)) {
        shown = venue;
      }
    }
  }
  if (!shown) return null;
  return {
    name: (shown.name || '').trim() || null,
    address: (shown.address || '').trim() || null,
    photoUrl: firstPhotoUrl(shown.photos)
  };
}

module.exports = { publicPlacePreview };
