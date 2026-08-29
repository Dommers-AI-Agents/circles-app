// backend/scripts/backfill-lookaround-photos.js
//
// Give imported places a free Apple Look Around photo from a Mac (the app's
// ImportPhotoQueue does the same on-device, 40 per app-open). Renders with
// scripts/lookaround/lookaround (MapKit on macOS), uploads through the normal
// storage path, attaches to the place, and defaults the circle cover.
//
//   node scripts/backfill-lookaround-photos.js --circle <circleId>
//   node scripts/backfill-lookaround-photos.js --user <uid>      # all their photo-less imports
//   DRY_RUN=true …                                               # render only, write nothing
//
const path = require('path');
const fs = require('fs');
const os = require('os');
const { execFileSync } = require('child_process');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const { COLLECTIONS } = require('../models/FirestoreModels');
const { uploadImage } = require('../services/storage');
const { ensureCircleCoverImage } = require('../services/circleCover');

const DRY_RUN = process.env.DRY_RUN === 'true';
const argIndex = (flag) => process.argv.indexOf(flag);
const circleId = argIndex('--circle') > 0 ? process.argv[argIndex('--circle') + 1] : null;
const userId = argIndex('--user') > 0 ? process.argv[argIndex('--user') + 1] : null;
if (!circleId && !userId) {
  console.error('usage: --circle <circleId> | --user <uid>   [DRY_RUN=true]');
  process.exit(2);
}

const BIN = path.join(__dirname, 'lookaround', 'lookaround');

async function loadCandidates() {
  let query = db.collection(COLLECTIONS.PLACES);
  query = circleId ? query.where('circleId', '==', circleId) : query.where('addedBy', '==', userId);
  const snap = await query.get();
  const out = [];
  snap.forEach(doc => {
    const p = doc.data();
    if (p.deletedAt) return;
    if (!circleId && !p.importSource) return;
    if (Array.isArray(p.photos) && p.photos.length > 0) return;
    const coords = p.location && p.location.coordinates;
    if (!Array.isArray(coords) || coords.length !== 2) return;
    out.push({ id: doc.id, name: p.name, circleId: p.circleId, lat: coords[1], lng: coords[0] });
  });
  return out;
}

(async () => {
  if (!fs.existsSync(BIN)) {
    console.error(`Renderer missing — build it first:\n  cd ${path.dirname(BIN)} && swiftc -O -framework MapKit -framework AppKit -o lookaround lookaround.swift`);
    process.exit(2);
  }
  const candidates = await loadCandidates();
  console.log(`${candidates.length} photo-less place(s) ${circleId ? `in circle ${circleId}` : `imported by ${userId}`}${DRY_RUN ? ' [DRY RUN]' : ''}`);
  if (candidates.length === 0) process.exit(0);

  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'lookaround-'));
  const listPath = path.join(work, 'candidates.json');
  fs.writeFileSync(listPath, JSON.stringify(candidates.map(c => ({ id: c.id, lat: c.lat, lng: c.lng }))));
  const summary = JSON.parse(execFileSync(BIN, [listPath, work], { stdio: ['ignore', 'pipe', 'inherit'], maxBuffer: 10 * 1024 * 1024 }).toString());
  console.log(`rendered ${summary.rendered.length}, no coverage ${summary.unavailable.length}, failed ${summary.failed.length}`);

  const byId = new Map(candidates.map(c => [c.id, c]));
  let attached = 0;
  const touchedCircles = new Set();
  for (const id of summary.rendered) {
    const c = byId.get(id);
    const jpg = fs.readFileSync(path.join(work, `${id}.jpg`));
    if (DRY_RUN) { console.log(`  would attach ${(jpg.length / 1024).toFixed(0)} KB → ${c.name}`); continue; }
    const url = await uploadImage(jpg.toString('base64'), `lookaround-${id}.jpg`);
    const ref = db.collection(COLLECTIONS.PLACES).doc(id);
    const fresh = await ref.get();
    if (Array.isArray(fresh.data().photos) && fresh.data().photos.length > 0) continue; // someone got there first
    await ref.update({
      photos: [url],
      photoSource: 'apple_look_around',
      photoFallbackAttempts: (fresh.data().photoFallbackAttempts || 0) + 1,
      updatedAt: new Date().toISOString()
    });
    attached++;
    if (c.circleId) touchedCircles.add(c.circleId);
    console.log(`  ✓ ${c.name}`);
  }
  if (!DRY_RUN) {
    for (const id of summary.unavailable) {
      const ref = db.collection(COLLECTIONS.PLACES).doc(id);
      const cur = (await ref.get()).data() || {};
      await ref.update({ photoFallbackAttempts: (cur.photoFallbackAttempts || 0) + 2 }); // retire: no coverage
    }
    for (const cid of touchedCircles) {
      const cover = await ensureCircleCoverImage(cid);
      console.log(`  circle ${cid} cover: ${cover ? 'set' : 'unchanged'}`);
    }
  }
  console.log(`done — ${attached} photo(s) attached${DRY_RUN ? ' (dry run: 0 written)' : ''}`);
  fs.rmSync(work, { recursive: true, force: true });
  process.exit(0);
})().catch(e => { console.error('❌', e); process.exit(1); });
