// backend/scripts/queue-address-venues-for-approval.js — one-time (2026-11-05):
// venues still tied to Google's street-address entry after
// relink-address-google-ids.js found no business for them go into the admin's
// approval queue (services/placeApproval). The address id comes off the venue
// (kept as googleAddressPlaceId): an address is never a venue's Google listing.
// People's saves keep the privacy they chose; only the place leaves search
// until it's approved.
//   DRY_RUN=true  node scripts/queue-address-venues-for-approval.js
//   DRY_RUN=false node scripts/queue-address-venues-for-approval.js
require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const { isAddressOnly } = require('../services/googleAddressGuard');

const DRY_RUN = String(process.env.DRY_RUN || 'true').toLowerCase() !== 'false';

(async () => {
  const db = getFirestore();
  const snap = await db.collection('globalPlaces').get();
  const todo = snap.docs.filter((d) => {
    const v = d.data();
    return v.googlePlaceId && !v.deletedAt && !v.mergedInto && !v.approvalStatus && isAddressOnly(v.googleTypes);
  });
  console.log(`${todo.length} venues to queue (${DRY_RUN ? 'dry run' : 'live'})`);
  const now = new Date().toISOString();
  for (const doc of todo) {
    const v = doc.data();
    console.log(`  ${doc.id} "${v.name}" ${v.address}`);
    if (DRY_RUN) continue;
    await doc.ref.update({
      approvalStatus: 'pending', pendingSince: now,
      googleAddressPlaceId: v.googlePlaceId, googlePlaceId: null, updatedAt: now
    });
  }
  process.exit(0);
})();
