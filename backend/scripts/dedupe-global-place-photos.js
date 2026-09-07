// Remove duplicate photos from globalPlaces records.
//
// Two duplicate classes (both found on Turnstile Coffee Roasters, 2026-09-07):
//   1. Same URL twice in the photos array — the legacy migration appended a
//      photo the array already held (no URL guard at the time).
//   2. Different URLs, byte-identical images — each saver's enrichment
//      re-hosted the same Google photo into its own Firebase Storage file
//      before the canonical-first gates (2026-08-22) stopped that.
//
// For every venue with 2+ photos:
//   - collapse same-URL entries (keep the attributed one, else the first)
//   - download + SHA-1 the survivors, collapse byte-identical entries
//   - rewrite linked save docs whose photos point at a dropped URL to the
//     kept URL instead (otherwise overlayVenuePhotos still merges venue photo
//     + save photo into two identical tiles), then URL-dedupe the save array
//   - set userContributions.totalPhotos to the kept count (matches
//     createGlobalPlaceFromLegacy semantics)
//
// NEVER deletes the Storage files behind dropped URLs: activity rows, widget
// snapshots, and old notification payloads still reference them and must keep
// rendering. Only the arrays are trimmed. Do not "finish the job" with a
// storage sweep.
//
// Idempotent. Dry-run by default (downloads still happen — hashing is how we
// know what WOULD be removed):
//
//   node scripts/dedupe-global-place-photos.js          # report only
//   node scripts/dedupe-global-place-photos.js --apply  # write changes

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const crypto = require('crypto');
const { initializeApp, cert } = require('firebase-admin/app');
initializeApp({ credential: cert(require('../config/firebase-service-account.json')) });

const { getFirestore } = require('../config/firebase');
const db = getFirestore();

const APPLY = process.argv.includes('--apply');

const urlOf = (photo) => (typeof photo === 'string' ? photo : photo?.url) || null;
const isAttributed = (photo) => typeof photo === 'object' && !!photo?.uploadedBy;

// Within a duplicate group, keep the user-attributed entry if there is one
// (the "Photo by" chip is worth preserving), else the first.
const pickKeeper = (entries) => entries.find(isAttributed) || entries[0];

const hashCache = new Map(); // url -> sha1 | 'FAILED'
let bytesDownloaded = 0;

async function sha1OfUrl(url) {
  if (hashCache.has(url)) return hashCache.get(url);
  try {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const buf = Buffer.from(await response.arrayBuffer());
    bytesDownloaded += buf.length;
    const hash = crypto.createHash('sha1').update(buf).digest('hex');
    hashCache.set(url, hash);
    return hash;
  } catch (e) {
    hashCache.set(url, 'FAILED');
    return 'FAILED';
  }
}

// Rewrite save docs whose photos reference a dropped URL. droppedToKept maps
// dropped URL -> the byte-identical URL the venue kept.
async function rewriteSaveDocs(venueId, legacyPlaceIds, droppedToKept, label) {
  const saveDocs = new Map();
  const linked = await db.collection('places').where('globalPlaceId', '==', venueId).get();
  linked.docs.forEach(d => saveDocs.set(d.id, d));
  for (const legacyId of legacyPlaceIds) {
    if (saveDocs.has(legacyId)) continue;
    const doc = await db.collection('places').doc(legacyId).get();
    if (doc.exists) saveDocs.set(doc.id, doc);
  }

  let rewritten = 0;
  for (const doc of saveDocs.values()) {
    const place = doc.data();
    if (place.deletedAt || !Array.isArray(place.photos) || place.photos.length === 0) continue;

    let changed = false;
    const seen = new Set();
    const newPhotos = [];
    for (const photo of place.photos) {
      let url = urlOf(photo);
      if (!url) continue;
      if (droppedToKept.has(url)) {
        url = droppedToKept.get(url);
        changed = true;
      }
      if (seen.has(url)) { changed = true; continue; }
      seen.add(url);
      // Save-doc photos are plain URL strings (the create-place shape)
      newPhotos.push(typeof photo === 'string' ? url : { ...photo, url });
    }
    if (!changed) continue;

    rewritten++;
    if (APPLY) {
      await doc.ref.update({ photos: newPhotos, updatedAt: new Date().toISOString() });
    }
    console.log(`  SAVE-DOC ${APPLY ? '' : '(dry) '}places/${doc.id} rewritten (${label})`);
  }
  return rewritten;
}

async function main() {
  console.log(`Mode: ${APPLY ? 'APPLY' : 'DRY-RUN (pass --apply to write)'}\n`);

  const snapshot = await db.collection('globalPlaces').get();
  const targets = snapshot.docs.filter(d => {
    const p = d.data();
    return !p.deletedAt && Array.isArray(p.photos) && p.photos.length >= 2;
  });
  console.log(`globalPlaces total: ${snapshot.size}, with 2+ photos: ${targets.length}\n`);

  const stats = { urlDupes: 0, contentDupes: 0, venuesChanged: 0, saveDocsRewritten: 0, fetchSkipped: 0 };

  for (const doc of targets) {
    const venue = doc.data();
    const label = `${venue.name || '(unnamed)'} (${doc.id})`;

    // Pass 1: same-URL collapse
    const byUrl = new Map();
    for (const photo of venue.photos) {
      const url = urlOf(photo);
      if (!url) continue;
      if (!byUrl.has(url)) byUrl.set(url, []);
      byUrl.get(url).push(photo);
    }
    let kept = [...byUrl.values()].map(pickKeeper);
    const urlDropCount = venue.photos.length - kept.length;
    stats.urlDupes += urlDropCount;

    // Pass 2: byte-identical collapse (only if still 2+ candidates)
    const droppedToKept = new Map();
    let contentDropCount = 0;
    if (kept.length >= 2) {
      const hashes = new Map(); // url -> sha1
      let anyFailed = false;
      for (const photo of kept) {
        const url = urlOf(photo);
        const hash = await sha1OfUrl(url);
        if (hash === 'FAILED') { anyFailed = true; break; }
        hashes.set(url, hash);
      }
      if (anyFailed) {
        stats.fetchSkipped++;
        console.log(`SKIP-HASH  ${label} — a photo failed to download; keeping its array as-is`);
      } else {
        const byHash = new Map();
        for (const photo of kept) {
          const hash = hashes.get(urlOf(photo));
          if (!byHash.has(hash)) byHash.set(hash, []);
          byHash.get(hash).push(photo);
        }
        const survivors = [];
        for (const group of byHash.values()) {
          const keeper = pickKeeper(group);
          survivors.push(keeper);
          for (const photo of group) {
            if (photo !== keeper) droppedToKept.set(urlOf(photo), urlOf(keeper));
          }
        }
        contentDropCount = kept.length - survivors.length;
        stats.contentDupes += contentDropCount;
        kept = survivors;
      }
    }

    if (urlDropCount === 0 && contentDropCount === 0) continue;
    stats.venuesChanged++;
    console.log(`DEDUPE     ${label}: ${venue.photos.length} -> ${kept.length} photos` +
      ` (${urlDropCount} same-URL, ${contentDropCount} same-bytes)`);

    if (APPLY) {
      await doc.ref.update({
        photos: kept,
        'userContributions.totalPhotos': kept.length,
        updatedAt: new Date().toISOString()
      });
    }

    if (droppedToKept.size > 0) {
      stats.saveDocsRewritten +=
        await rewriteSaveDocs(doc.id, venue.legacyPlaceIds || [], droppedToKept, venue.name || doc.id);
    }
  }

  console.log(`\nDone. Venues changed: ${stats.venuesChanged}` +
    ` | same-URL dupes removed: ${stats.urlDupes}` +
    ` | same-bytes dupes removed: ${stats.contentDupes}` +
    ` | save docs rewritten: ${stats.saveDocsRewritten}` +
    ` | venues skipped (fetch failure): ${stats.fetchSkipped}` +
    ` | downloaded for hashing: ${(bytesDownloaded / 1048576).toFixed(1)} MB`);
  if (!APPLY) console.log('DRY-RUN — nothing was written. Re-run with --apply.');
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
