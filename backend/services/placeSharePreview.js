// services/placeSharePreview.js
//
// What the public /place/:placeId share page (server.js) may say about a
// place. The page answers to anyone — browsers, link-preview crawlers,
// whoever was forwarded the link — so it only describes a place an anonymous
// viewer could see: a live save whose circle is public and whose own privacy
// doesn't narrow it. It used to print the name, address and photo of ANY
// place id, private ones included (security audit 2026-10-01).

const { canViewCircle, isPlaceVisibleToViewer } = require('./visibility');

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
    if (!isLive(save) || !save.circleId || !isPlaceVisibleToViewer(save, null, null)) return false;
    const circleDoc = await db.collection('circles').doc(String(save.circleId)).get();
    return circleDoc.exists && isLive(circleDoc.data()) && canViewCircle(circleDoc.data(), null, null);
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
