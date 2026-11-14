// Venues saved without a Google id (Apple Maps places, typed names) never got
// Google's rating, hours, phone or editorial summary: only share-extension
// saves looked them up (Wes, 2026-11-14: RA Sushi Bar). New saves look now
// (placeSaveService); this fills the ones saved before, through the same
// enrichSaveFromGoogle, held to Google's listing of that very name nearby.
//
//   DRY_RUN=true node scripts/backfill-bare-venue-google.js   # list, no Google calls
//   ONLY=<venueId> node scripts/backfill-bare-venue-google.js # one venue
//   LIMIT=20 node scripts/backfill-bare-venue-google.js       # the first 20
//   RETRY=true node scripts/backfill-bare-venue-google.js     # again, after the match rule changed
//   node scripts/backfill-bare-venue-google.js                # all
//
// Idempotent: each venue is tried once (googleBackfillAt); a venue whose
// Google listing another record already holds is reported for a merge, not changed.
require('dotenv').config();
require('../config/firebase').initializeFirebase();
const admin = require('firebase-admin');
const db = admin.firestore();
const { enrichSaveFromGoogle } = require('../services/googleEnrichment');
const { findCanonicalByNameAndLocation, findVenueByGooglePlaceId } = require('../services/globalPlaceResolver');
const { isHiddenVenue } = require('../services/placeApproval');
const { isStreetLineName } = require('../services/googleAddressGuard');

const DRY_RUN = process.env.DRY_RUN === 'true';
const ONLY = process.env.ONLY || null;
const LIMIT = Number(process.env.LIMIT) || Infinity;
const RETRY = process.env.RETRY === 'true'; // try venues an earlier run found no listing for

(async () => {
  const docs = ONLY
    ? [await db.collection('globalPlaces').doc(ONLY).get()]
    : (await db.collection('globalPlaces').where('googlePlaceId', '==', null).get()).docs;
  const counts = { eligible: 0, enriched: 0, noMatch: 0, duplicate: 0, skipped: 0 };
  for (const doc of docs) {
    const v = doc.exists ? doc.data() : null;
    const coords = v && v.location && v.location.coordinates;
    if (!v || v.deletedAt || v.googlePlaceId || isHiddenVenue(v) || isStreetLineName(v.name, v.address)
      || !Array.isArray(coords) || coords.length !== 2 || (v.googleBackfillAt && !ONLY && !RETRY)) { counts.skipped++; continue; }
    if (counts.eligible >= LIMIT) break;
    counts.eligible++;
    if (DRY_RUN) { console.log(`would look up ${doc.id} ${v.name}`); continue; }

    // The resolver must land on this very record, so the upgrade happens in place
    const canonical = await findCanonicalByNameAndLocation(v.name, { coordinates: coords });
    if (!canonical || canonical.id !== doc.id) { console.log(`skip ${doc.id} ${v.name}: resolves to ${canonical ? canonical.id : 'nothing'}`); counts.skipped++; continue; }

    // A placeholder photo: the venue's library is the photo flow's job, not a billed re-host here
    const draft = { name: v.name, address: v.address, location: { type: 'Point', coordinates: coords }, photos: ['(kept)'] };
    const found = await enrichSaveFromGoogle(draft, { mustMatchName: true });
    await doc.ref.update({ googleBackfillAt: new Date().toISOString() });
    if (!found) { counts.noMatch++; console.log(`no listing  ${doc.id} ${v.name}`); continue; }
    const after = (await doc.ref.get()).data();
    if (after.googlePlaceId === draft.googlePlaceId) {
      counts.enriched++; console.log(`enriched    ${doc.id} ${v.name} → ${after.name} (${draft.googlePlaceId})`);
    } else {
      const holder = await findVenueByGooglePlaceId(draft.googlePlaceId);
      counts.duplicate++; console.log(`DUPLICATE   ${doc.id} ${v.name} = ${holder ? holder.id : '?'} (${draft.googlePlaceId}) — merge`);
    }
  }
  console.log(DRY_RUN ? 'DRY RUN' : 'DONE', counts);
  process.exit(0);
})();
