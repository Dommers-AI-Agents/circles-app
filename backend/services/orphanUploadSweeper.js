// backend/services/orphanUploadSweeper.js
//
// Moment uploads that never finished. Initiate writes the placeVideos doc
// (uploadStatus 'uploading', with the Storage paths it minted) and hands the
// phone signed write URLs; completion flips it to 'processing' then 'ready'.
// When the app dies, the user backs out, or completion crashes in between,
// the doc and whatever bytes already landed in Storage sit there forever —
// invisible (every feed reads uploadStatus == 'ready') but paid for.
//
// Viral-growth review 2026-10-01: at scale that is real Storage cost, so an
// hourly task sweeps them. A doc still 'uploading' or 'processing' two hours
// after it was created (the write URLs expire after 30 minutes) is marked
// 'abandoned' and its objects are deleted. Docs are kept, never deleted, so
// nothing that references one breaks. Bounded per run; the walk resumes from
// a cursor in jobCursors/orphan-uploads so young in-flight uploads never pin
// the sweep to the same first page.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { runResumableJob, forEachPage } = require('../utils/firestorePaging');

const STALE_AFTER_MS = 2 * 60 * 60 * 1000;
const MAX_PER_RUN = 200;
// Every status a doc can be stuck in short of 'ready'. 'error' is left alone:
// the only writer of it (an oversize completion) already deleted the objects.
const SWEEP_STATUSES = ['uploading', 'processing'];
const JOB = 'orphan-uploads';
// The three object slots initiate mints, and their folders for docs written
// before the paths were stored on the doc.
const SLOT_FOLDERS = { video: 'full', preview: 'preview', thumbnail: 'thumbnails' };

const toMillis = (value) => {
  if (!value) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const ms = new Date(value).getTime();
  return Number.isNaN(ms) ? null : ms;
};

// A stored path is only ever deleted when it sits in the uploader's own
// folder and names this video — a bad doc can never point the sweeper at
// somebody else's file.
const ownPath = (path, userId, videoId) =>
  typeof path === 'string' && !!userId &&
  path.startsWith(`videos/${userId}/`) && path.includes(String(videoId)) && !path.includes('..');

/**
 * Deletes whatever the upload left in Storage. Uses the paths stored at
 * initiate; for older docs without them, the objects are found by their
 * deterministic `videos/{uid}/{folder}/{videoId}_` prefix.
 * Returns { deleted, ok } — ok is false when any delete failed (retried later).
 */
async function deleteUploadObjects(bucket, videoId, data) {
  const userId = data.userId;
  let files = [];
  const stored = data.storagePaths && typeof data.storagePaths === 'object' ? data.storagePaths : null;
  if (stored && Object.values(stored).some(Boolean)) {
    files = Object.values(stored).filter((p) => ownPath(p, userId, videoId)).map((p) => bucket.file(p));
  } else if (userId) {
    for (const folder of Object.values(SLOT_FOLDERS)) {
      const [found] = await bucket.getFiles({ prefix: `videos/${userId}/${folder}/${videoId}_` });
      files.push(...found.filter((f) => ownPath(f.name, userId, videoId)));
    }
  }
  let ok = true;
  let deleted = 0;
  await Promise.all(files.map(async (file) => {
    try {
      await file.delete({ ignoreNotFound: true });
      deleted += 1;
    } catch (error) {
      ok = false;
      console.warn(`⚠️ Orphan sweep could not delete ${file.name}: ${error.message}`);
    }
  }));
  return { deleted, ok };
}

const defaultBucket = () => require('firebase-admin/storage').getStorage().bucket();

/**
 * One sweep. Options are for tests and manual runs:
 *   dryRun       report what would be abandoned; write and delete nothing
 *   maxPerRun    cap on uploads abandoned this run (default 200)
 *   staleAfterMs how old an unfinished upload must be (default 2 h)
 */
async function sweepOrphanUploads({
  db = getFirestore(), bucket = null, now = Date.now, dryRun = false,
  maxPerRun = MAX_PER_RUN, staleAfterMs = STALE_AFTER_MS, deadlineMs
} = {}) {
  const storage = bucket || (dryRun ? null : defaultBucket());
  const nowIso = () => new Date(now()).toISOString();
  const results = { dryRun, scanned: 0, abandoned: 0, objectsDeleted: 0, cleanupFailed: 0, retried: 0, skippedChanged: 0, sample: [] };
  const videos = db.collection(COLLECTIONS.PLACE_VIDEOS);

  // 1. Retry Storage cleanups that failed on an earlier run.
  if (!dryRun) {
    const pending = await videos.where('storageCleanupPending', '==', true).limit(maxPerRun).get();
    for (const doc of pending.docs) {
      const { deleted, ok } = await deleteUploadObjects(storage, doc.id, doc.data());
      results.retried += 1;
      results.objectsDeleted += deleted;
      if (ok) await doc.ref.update({ storageCleanupPending: false, storageCleanedAt: nowIso() });
      else results.cleanupFailed += 1;
    }
  }

  // 2. Find newly stale uploads.
  const cutoff = now() - staleAfterMs;
  const onPage = async (docs) => {
    for (const doc of docs) {
      // At the cap: stop. The cursor moves past this whole page, so its
      // remaining docs wait for the next lap of the sweep (it wraps).
      if (results.abandoned >= maxPerRun) return false;
      results.scanned += 1;
      const data = doc.data();
      const createdAt = toMillis(data.createdAt);
      if (createdAt === null || createdAt > cutoff) continue; // in flight (or unknown age): leave it
      if (results.sample.length < 20) results.sample.push({ videoId: doc.id, userId: data.userId || null, status: data.uploadStatus, createdAt: data.createdAt });
      if (dryRun) { results.abandoned += 1; continue; }

      // Mark first, only if nobody touched the doc since we read it (a
      // completion racing the sweep wins); then delete the bytes.
      const patch = {
        uploadStatus: 'abandoned',
        abandonedFromStatus: data.uploadStatus || null,
        abandonedAt: nowIso(),
        storageCleanupPending: true,
        updatedAt: nowIso()
      };
      try {
        if (doc.updateTime) await doc.ref.update(patch, { lastUpdateTime: doc.updateTime });
        else await doc.ref.update(patch);
      } catch (error) {
        if (error && (error.code === 9 || error.code === 5)) { results.skippedChanged += 1; continue; } // FAILED_PRECONDITION / NOT_FOUND
        throw error;
      }
      results.abandoned += 1;
      const { deleted, ok } = await deleteUploadObjects(storage, doc.id, data);
      results.objectsDeleted += deleted;
      if (ok) await doc.ref.update({ storageCleanupPending: false, storageCleanedAt: nowIso() });
      else results.cleanupFailed += 1;
    }
    return results.abandoned < maxPerRun;
  };

  const query = videos.where('uploadStatus', 'in', SWEEP_STATUSES);
  // A dry run reads from the top and leaves the cursor alone.
  const walk = dryRun
    ? await forEachPage(query, onPage, deadlineMs ? { deadlineMs, now } : { now })
    : await runResumableJob({ db, job: JOB, query, onPage, now, ...(deadlineMs ? { deadlineMs } : {}) });
  results.walk = walk;
  console.log(`🧹 Orphan uploads: ${results.abandoned} abandoned${dryRun ? ' (dry run)' : ''}, ${results.objectsDeleted} objects deleted, ${results.cleanupFailed} cleanups pending`);
  return results;
}

module.exports = { sweepOrphanUploads, deleteUploadObjects, STALE_AFTER_MS, MAX_PER_RUN, SWEEP_STATUSES };
