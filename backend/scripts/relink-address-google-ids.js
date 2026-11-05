// backend/scripts/relink-address-google-ids.js — one-time (2026-11-05, 300 East):
// venues whose googlePlaceId is Google's entry for the street address, not
// the business (googleTypes premise/street_address/route…). Google enrichment
// then has nothing: no photos, stars, hours, website or phone. For each, find
// the business on Google at that spot (services/googleAddressGuard) and
// re-link the venue and its saves; then fill the empty details and, when the
// library has no public photo, one Google photo.
//   DRY_RUN=true  node scripts/relink-address-google-ids.js   (lookups only, no writes)
//   DRY_RUN=false node scripts/relink-address-google-ids.js
// A match must be a business within 250 m sharing a distinctive name word.
// Venues already holding the business id elsewhere are reported for a merge
// (scripts/merge-venue-pair.js), never re-linked. No match → reported, left as is.
require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const { Client } = require('@googlemaps/google-maps-services-js');
const { distanceBetween } = require('geofire-common');
const { isAddressOnly, venueCandidates } = require('../services/googleAddressGuard');
const { namesLikelySameVenue } = require('../services/venueNameMatch');
const { findVenueByGooglePlaceId } = require('../services/globalPlaceResolver');

const DRY_RUN = String(process.env.DRY_RUN || 'true').toLowerCase() !== 'false';
const ONLY = process.env.ONLY ? new Set(process.env.ONLY.split(',')) : null;
const MAX_METERS = 250;
const key = process.env.GOOGLE_MAPS_API_KEY;
const client = new Client({});

async function findBusiness(venue) {
  const [lng, lat] = venue.location.coordinates;
  const res = await client.findPlaceFromText({
    params: {
      input: venue.name, inputtype: 'textquery',
      fields: ['place_id', 'name', 'types', 'geometry', 'formatted_address'],
      locationbias: `circle:${MAX_METERS}@${lat},${lng}`, key
    },
    timeout: 8000
  });
  return venueCandidates(res.data.candidates).find((c) => {
    const at = c.geometry && c.geometry.location;
    if (!at) return false;
    const meters = distanceBetween([lat, lng], [at.lat, at.lng]) * 1000;
    const sameName = namesLikelySameVenue(c.name, venue.name)
      || String(c.name).toLowerCase().includes(String(venue.name).toLowerCase().trim());
    return meters <= MAX_METERS && sameName;
  }) || null;
}

(async () => {
  const db = getFirestore();
  const snap = await db.collection('globalPlaces').get();
  const todo = snap.docs.filter((d) => {
    const v = d.data();
    return (!ONLY || ONLY.has(d.id)) && v.googlePlaceId && !v.deletedAt && !v.mergedInto
      && isAddressOnly(v.googleTypes) && v.location && Array.isArray(v.location.coordinates);
  });
  console.log(`${todo.length} venues tied to an address entry (${DRY_RUN ? 'dry run' : 'live'})`);
  const r = { relinked: [], merge: [], noMatch: [] };
  for (const doc of todo) {
    const venue = doc.data();
    let match;
    try { match = await findBusiness(venue); } catch (e) { console.log(`  ⚠️ ${venue.name}: ${e.message}`); continue; }
    if (!match) { r.noMatch.push(`${doc.id} "${venue.name}" ${venue.address}`); continue; }
    const holder = await findVenueByGooglePlaceId(match.place_id);
    if (holder && holder.id !== doc.id) {
      r.merge.push(`${doc.id} "${venue.name}" → already ${holder.id} "${holder.data().name}" (${match.place_id})`);
      continue;
    }
    r.relinked.push(`${doc.id} "${venue.name}" → "${match.name}" ${match.formatted_address} (${match.place_id})`);
    if (DRY_RUN) continue;

    const oldId = venue.googlePlaceId;
    const now = new Date().toISOString();
    await doc.ref.update({
      googlePlaceId: match.place_id, deduplicationKey: `google:${match.place_id}`,
      googleTypes: match.types || [], 'googleData.detailsCheckedAt': null, updatedAt: now
    });
    const saves = await db.collection('places').where('globalPlaceId', '==', doc.id).get();
    for (const s of saves.docs) {
      if (!s.data().googlePlaceId || s.data().googlePlaceId === oldId) {
        await s.ref.update({ googlePlaceId: match.place_id, googleTypes: match.types || [], updatedAt: now });
      }
    }
    const filled = await require('../services/venueGoogleDetails').fillVenue(doc.id, { force: true });
    const photoService = require('../services/placePhotoService');
    let photo = 'kept';
    if (!photoService.hasVisiblePhotos(venue.photos)) {
      const url = await require('../services/googlePlacePhoto').fetchGooglePhotoUrl({ googlePlaceId: match.place_id });
      const saver = saves.docs.find((s) => !s.data().deletedAt);
      if (url && saver) {
        await photoService.adoptSavePhotos({ globalPlaceId: doc.id, user: { uid: saver.data().addedBy }, photos: [url], ownUrls: [] });
        photo = 'added';
      } else photo = 'none';
    }
    console.log(`  ✅ ${venue.name}: filled ${JSON.stringify(filled)}, photo ${photo}, ${saves.size} saves`);
  }
  console.log(`\nRE-LINK (${r.relinked.length})\n  ${r.relinked.join('\n  ')}`);
  console.log(`\nMERGE CANDIDATES (${r.merge.length})\n  ${r.merge.join('\n  ')}`);
  console.log(`\nNO BUSINESS FOUND (${r.noMatch.length})\n  ${r.noMatch.join('\n  ')}`);
  process.exit(0);
})();
