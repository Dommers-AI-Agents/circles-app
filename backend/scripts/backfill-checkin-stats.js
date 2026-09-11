// Backfill: rebuild users/{uid}/checkInStats/{globalPlaceId} from raw checkIns
// docs, and stamp globalPlaceId on check-ins that predate the stamp.
//
// Idempotent — every bucket is recomputed from scratch and overwritten, so
// re-running after new check-ins (which the live path already counted) lands
// on the same numbers. Venue resolution: check-in's stamped globalPlaceId →
// the referenced save doc's globalPlaceId → name+coords match on globalPlaces.
//
// Usage:
//   DRY_RUN=true node scripts/backfill-checkin-stats.js            # report only
//   node scripts/backfill-checkin-stats.js                         # live run
//   USER_ID=<uid> node scripts/backfill-checkin-stats.js           # one user
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const { COLLECTIONS } = require('../models/FirestoreModels');
const { applyCheckIn, resolveCheckInVenue, statsRef } = require('../services/checkInStatsService');

const DRY_RUN = process.env.DRY_RUN === 'true';
const ONLY_USER = process.env.USER_ID || null;

(async () => {
  console.log(`🚀 Backfilling check-in stats (${DRY_RUN ? 'DRY RUN' : 'LIVE'})${ONLY_USER ? ' for ' + ONLY_USER : ''}`);
  let query = db.collection(COLLECTIONS.CHECK_INS);
  if (ONLY_USER) query = query.where('userId', '==', ONLY_USER);
  const snap = await query.get();
  console.log(`📥 ${snap.size} check-ins`);

  const buckets = new Map(); // `${uid}|${gpid}` -> aggregate
  const placeCache = new Map(); // placeId -> globalPlaceId|null
  const stamps = []; // [ref, {globalPlaceId, placeId?}]
  let unresolved = 0;

  for (const doc of snap.docs) {
    const c = doc.data();
    if (!c.userId) continue;
    let gpid = c.globalPlaceId || null;
    if (!gpid) {
      const cacheKey = c.placeId || null;
      if (cacheKey && placeCache.has(cacheKey)) {
        gpid = placeCache.get(cacheKey);
      } else {
        const loc = c.location && typeof c.location.latitude === 'number'
          ? { latitude: c.location.latitude, longitude: c.location.longitude }
          : null;
        gpid = await resolveCheckInVenue({
          placeId: c.placeId || null,
          placeName: c.placeName,
          location: loc,
          allowWrites: !DRY_RUN
        });
        if (cacheKey) placeCache.set(cacheKey, gpid);
      }
      if (gpid) stamps.push([doc.ref, { globalPlaceId: gpid }]);
    }
    if (!gpid) {
      unresolved++;
      console.log(`  ⚠️ unresolved: ${doc.id} ${c.userId} "${c.placeName}" placeId=${c.placeId || '-'} hasLocation=${!!c.location}`);
      continue;
    }
    const key = `${c.userId}|${gpid}`;
    buckets.set(key, applyCheckIn(buckets.get(key) || null, {
      at: c.createdAt || c.startTime,
      placeName: c.placeName,
      placeId: c.placeId || null,
      checkInId: doc.id
    }));
  }

  console.log(`📊 ${buckets.size} user/venue buckets, ${stamps.length} check-ins to stamp, ${unresolved} unresolvable (no venue match)`);
  if (ONLY_USER || buckets.size <= 40) {
    for (const [key, b] of buckets) {
      const [uid, gpid] = key.split('|');
      console.log(`  ${uid} ${gpid} ${b.placeName} ×${b.count} first=${b.firstCheckInAt} last=${b.lastCheckInAt}`);
    }
  }
  if (DRY_RUN) { console.log('DRY RUN — no writes'); process.exit(0); }

  let batch = db.batch();
  let ops = 0;
  const flush = async () => { if (ops > 0) { await batch.commit(); batch = db.batch(); ops = 0; } };
  const now = new Date().toISOString();
  for (const [key, b] of buckets) {
    const [uid, gpid] = key.split('|');
    batch.set(statsRef(uid, gpid), { ...b, globalPlaceId: gpid, updatedAt: now, backfilledAt: now });
    if (++ops >= 400) await flush();
  }
  for (const [ref, stamp] of stamps) {
    batch.update(ref, stamp);
    if (++ops >= 400) await flush();
  }
  await flush();
  console.log(`✅ Wrote ${buckets.size} stats docs, stamped ${stamps.length} check-ins`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
