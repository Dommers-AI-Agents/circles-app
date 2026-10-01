// backend/services/uploadSizeGuard.js
//
// Moment uploads go straight from the phone to Cloud Storage through v4
// signed write URLs. Those URLs carry no size cap (current iOS builds can't
// send the x-goog-content-length-range header a capped URL would require),
// and the quota used to trust the client-declared fileSize. So the real
// object sizes are checked when the upload is completed: anything over the
// cap is deleted and refused, and quota is counted from the bytes actually
// stored (security audit 2026-10-01).

const MAX_VIDEO_BYTES = 100 * 1024 * 1024; // full + preview MP4
const MAX_IMAGE_BYTES = 10 * 1024 * 1024; // thumbnail, or the photo itself for photo moments

const CAPS = {
  video: MAX_VIDEO_BYTES,
  preview: MAX_VIDEO_BYTES,
  thumbnail: MAX_IMAGE_BYTES
};

/**
 * Pure verdict over measured object sizes.
 * @param {{video?: number|null, preview?: number|null, thumbnail?: number|null}} sizes
 *   bytes per slot; null/undefined = object absent or unreadable
 * @returns {{ok: boolean, offenders: string[], totalBytes: number}}
 */
function checkUploadSizes(sizes = {}) {
  const offenders = [];
  let totalBytes = 0;
  for (const [slot, cap] of Object.entries(CAPS)) {
    const size = sizes[slot];
    if (typeof size !== 'number' || !Number.isFinite(size)) continue;
    totalBytes += size;
    if (size > cap) offenders.push(slot);
  }
  return { ok: offenders.length === 0, offenders, totalBytes };
}

/**
 * Which storage paths a completion may touch. Paths minted at initiate are
 * stored on the video doc and win; the client's copy is only accepted for
 * uploads initiated before that field existed, and then only inside the
 * caller's own videos/{uid}/ folder and naming this video — otherwise a
 * completion could point at (and, when oversize, delete) someone else's file.
 * @returns {{video: string|null, preview: string|null, thumbnail: string|null}|null}
 */
function resolveStoragePaths(storedPaths, clientPaths, userId, videoId) {
  if (storedPaths && typeof storedPaths === 'object' && storedPaths.thumbnail) {
    return {
      video: storedPaths.video || null,
      preview: storedPaths.preview || null,
      thumbnail: storedPaths.thumbnail
    };
  }
  if (!clientPaths || typeof clientPaths !== 'object') return null;
  const prefix = `videos/${userId}/`;
  const ok = (p) => p == null || (
    typeof p === 'string' &&
    p.startsWith(prefix) &&
    p.includes(String(videoId)) &&
    !p.includes('..')
  );
  const { video = null, preview = null, thumbnail } = clientPaths;
  if (!thumbnail || !ok(thumbnail) || !ok(video) || !ok(preview)) return null;
  return { video, preview, thumbnail };
}

/** Real stored size per slot via object metadata; null when unreadable. */
async function readObjectSizes(bucket, paths) {
  const sizes = {};
  await Promise.all(Object.entries(paths).map(async ([slot, path]) => {
    if (!path) { sizes[slot] = null; return; }
    try {
      const [meta] = await bucket.file(path).getMetadata();
      const size = parseInt(meta && meta.size, 10); // GCS reports size as a string
      sizes[slot] = Number.isFinite(size) ? size : null;
    } catch (_) {
      sizes[slot] = null;
    }
  }));
  return sizes;
}

/** Best-effort delete of every uploaded object for a refused completion. */
async function deleteObjects(bucket, paths) {
  await Promise.all(Object.values(paths).filter(Boolean).map((path) =>
    bucket.file(path).delete({ ignoreNotFound: true }).catch((error) => {
      console.warn(`⚠️ Could not delete oversize upload ${path}: ${error.message}`);
    })
  ));
}

module.exports = {
  MAX_VIDEO_BYTES,
  MAX_IMAGE_BYTES,
  checkUploadSizes,
  resolveStoragePaths,
  readObjectSizes,
  deleteObjects
};
