// services/momentDeletion.js — removes a moment and everything hanging off it.
// One path for the owner's Delete and for disappearing moments that run out
// (2026-10-18). Besides the files, the moment and its upload activity row
// (what Delete always did), it now also removes the moment's likes, comments,
// views and the other activity rows that point at it ("X liked your moment"),
// which Delete used to leave behind.
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const VIDEO_COMMENTS = 'video_comments';
const BATCH_LIMIT = 400;

function bucketName() {
  return process.env.FIREBASE_STORAGE_BUCKET || 'circles-app-83b67.firebasestorage.app';
}

/** Storage path from a download URL, or null when it isn't one of ours. */
function storagePathFromUrl(url, bucket = bucketName()) {
  if (!url || typeof url !== 'string') return null;
  const patterns = [`https://firebasestorage.googleapis.com/v0/b/${bucket}/o/`, `https://${bucket}/`];
  for (const pattern of patterns) {
    if (url.includes(pattern)) return decodeURIComponent(url.split(pattern)[1].split('?')[0]);
  }
  return null;
}

/**
 * Every file the moment has: recorded paths first, then its URLs. Only paths
 * inside the owner's own `videos/<uid>/` folder, so a moment can never take
 * someone else's file with it.
 */
function storagePathsFor(video) {
  const paths = new Set();
  const recorded = video.storagePaths || {};
  for (const p of Object.values(recorded)) if (typeof p === 'string' && p) paths.add(p);
  for (const url of [video.videoUrl, video.previewUrl, video.thumbnailUrl]) {
    const p = storagePathFromUrl(url);
    if (p) paths.add(p);
  }
  const own = video.userId ? `videos/${video.userId}/` : null;
  return [...paths].filter(p => own && p.startsWith(own));
}

async function deleteAll(db, docs) {
  for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    docs.slice(i, i + BATCH_LIMIT).forEach(doc => batch.delete(doc.ref));
    await batch.commit();
  }
  return docs.length;
}

/**
 * Deletes moment `videoId` (its doc `video`) for good. Each step is
 * best-effort after the files: a failure is logged and the rest still runs,
 * so a moment never half-survives. Returns counts for the log.
 * `bucket` is a firebase-admin Storage bucket (injected for tests).
 */
async function removeMoment(videoId, video, { db = getFirestore(), bucket = null, reason = 'deleted' } = {}) {
  const counts = { files: 0, likes: 0, comments: 0, views: 0, activities: 0 };
  const step = async (label, fn) => {
    try { await fn(); } catch (e) { console.error(`moment ${videoId} (${reason}): ${label} failed:`, e.message); }
  };

  if (bucket) {
    await step('files', async () => {
      const paths = storagePathsFor(video);
      await Promise.all(paths.map(p => bucket.file(p).delete().catch(err => {
        if (err && err.code !== 404) console.log(`moment ${videoId}: could not delete ${p}: ${err.message}`);
      })));
      counts.files = paths.length;
    });
  }

  // The upload's activity row and its reactions/comments
  if (video.activityId) {
    await step('upload activity', async () => {
      const [reactions, comments] = await Promise.all([
        db.collection(COLLECTIONS.ACTIVITY_REACTIONS).where('activityId', '==', video.activityId).get(),
        db.collection(COLLECTIONS.ACTIVITY_COMMENTS).where('activityId', '==', video.activityId).get()
      ]);
      await deleteAll(db, [...reactions.docs, ...comments.docs]);
      await db.collection(COLLECTIONS.ACTIVITIES).doc(video.activityId).delete();
      counts.activities += 1;
    });
  }

  // Every other activity row about this moment ("liked your moment", …)
  await step('other activities', async () => {
    const snap = await db.collection(COLLECTIONS.ACTIVITIES).where('targetId', '==', videoId).get();
    // 'place_video' = the upload/link row (link moments never stored its id),
    // 'video' = likes and the like
    const rows = snap.docs.filter(d => d.id !== video.activityId
      && ['video', 'place_video'].includes(d.data().targetType || 'video'));
    counts.activities += await deleteAll(db, rows);
  });

  await step('likes', async () => {
    const snap = await db.collection(COLLECTIONS.VIDEO_LIKES).where('videoId', '==', videoId).get();
    counts.likes = await deleteAll(db, snap.docs);
  });
  await step('comments', async () => {
    const snap = await db.collection(VIDEO_COMMENTS).where('videoId', '==', videoId).get();
    counts.comments = await deleteAll(db, snap.docs);
  });
  await step('views', async () => {
    const snap = await db.collection(COLLECTIONS.VIDEO_VIEWS).where('videoId', '==', videoId).get();
    counts.views = await deleteAll(db, snap.docs);
  });

  await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).delete();

  if (video.userId) {
    await step('quota', () => db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(video.userId).set({
      videosUploaded: FieldValue.increment(-1),
      totalSize: FieldValue.increment(-(video.fileSize || 0)),
      updatedAt: new Date().toISOString()
    }, { merge: true }));
  }

  console.log(`🗑️ moment ${videoId} ${reason}: ${JSON.stringify(counts)}`);
  return counts;
}

module.exports = { removeMoment, storagePathsFor, storagePathFromUrl, VIDEO_COMMENTS };
