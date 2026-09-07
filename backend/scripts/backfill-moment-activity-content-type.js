// backend/scripts/backfill-moment-activity-content-type.js
//
// Photo moments ride the video pipeline, so their feed activities are typed
// `video_uploaded` — and until 2026-09-07 the row didn't record whether the
// moment was a photo or a video, so the feed said "uploaded a video" for
// photos. New activities stamp metadata.contentType at creation; this stamps
// the existing rows by looking up each activity's placeVideos doc. Idempotent.
//
//   DRY_RUN=true node scripts/backfill-moment-activity-content-type.js
//   node scripts/backfill-moment-activity-content-type.js

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();

const DRY_RUN = process.env.DRY_RUN === 'true';

async function run() {
  const snap = await db.collection('activities').where('type', '==', 'video_uploaded').get();
  console.log(`🔎 ${snap.size} video_uploaded activities`);
  let stamped = 0, skipped = 0, missing = 0;

  for (const doc of snap.docs) {
    const a = doc.data();
    if (a.metadata && a.metadata.contentType) { skipped++; continue; }
    const videoDoc = await db.collection('placeVideos').doc(a.targetId).get();
    if (!videoDoc.exists) { missing++; continue; }
    const contentType = videoDoc.data().contentType || 'video';
    if (DRY_RUN) {
      console.log(`  • would stamp ${doc.id} (${a.targetName}) contentType=${contentType}`);
    } else {
      await doc.ref.update({ 'metadata.contentType': contentType });
    }
    stamped++;
  }
  console.log(`✅ stamped ${stamped}, already-had ${skipped}, missing video doc ${missing}${DRY_RUN ? ' (DRY RUN)' : ''}`);
  process.exit(0);
}

run().catch(e => { console.error(e); process.exit(1); });
