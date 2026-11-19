#!/usr/bin/env node
// backend/scripts/backfill-workout-place-photos.js
//
// Gives already-shared workout rows the gym's photo, the way new shares get
// it (services/workoutPlace; Wes, 2026-11-19: "Use the ymca main page image
// instead"). Rows without a matching shared check-in are left as they are.
// Idempotent: rows that already have a photo are skipped.
//   DRY_RUN=false node scripts/backfill-workout-place-photos.js   (default: dry run)
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const { COLLECTIONS } = require('../models/FirestoreModels');
const { workoutPlaceFor } = require('../services/workoutPlace');

const DRY_RUN = process.env.DRY_RUN !== 'false';
const db = getFirestore();

async function main() {
  console.log(DRY_RUN ? '🔍 DRY RUN (DRY_RUN=false to write)' : '✍️  WRITING');
  const rows = await db.collection(COLLECTIONS.ACTIVITIES).where('type', '==', 'workout_shared').get();
  const stats = { rows: rows.size, alreadyHasPhoto: 0, noPost: 0, noGym: 0, fixed: 0 };
  for (const row of rows.docs) {
    const a = row.data();
    const meta = a.metadata || {};
    if (meta.placePhoto) { stats.alreadyHasPhoto++; continue; }
    const post = meta.workoutPostId ? await db.collection(COLLECTIONS.WORKOUT_POSTS).doc(meta.workoutPostId).get() : null;
    if (!post || !post.exists) { stats.noPost++; continue; }
    const p = post.data();
    const place = await workoutPlaceFor(a.actorId, p.summary, { audience: p.audience, audienceListId: p.audienceListId });
    if (!place.placePhoto) { stats.noGym++; continue; }
    stats.fixed++;
    console.log(`${row.id}  ${a.targetName}  → ${place.placeName}`);
    if (DRY_RUN) continue;
    await row.ref.update({ 'metadata.placePhoto': place.placePhoto, 'metadata.workoutPlaceName': place.placeName || null });
  }
  console.log(stats);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
