// backend/services/eventVideoService.js
//
// Videos in the Events widget (Wes, 2026-10-10). A clip goes straight from
// the phone to Cloud Storage through signed write URLs, like Moments:
//   1. startVideo checks the viewer's limits and reserves a row in
//      eventPhotos (kind 'video', status 'uploading') with server-minted
//      storage paths;
//   2. the phone uploads the MP4, a poster frame and a small poster;
//   3. finishVideo measures what actually landed, refuses (and deletes) a
//      file too big for the viewer's clip length, and publishes the row.
// Limits: free clips up to 15 s and 5 per person per event; Premium (and
// trial) up to 60 s and 20 per person per event. Members only, like photos.
// A video row's imageUrl/thumbUrl are its poster, so apps that predate
// videos show it as a still photo.

const ev = require('./eventService');
const { ServiceError } = require('../utils/serviceError');
const { clean } = require('../utils/text');
const { getTierForStatus } = require('../config/subscriptionLimits');
const { maxEventVideoBytes, readObjectSizes, deleteObjects } = require('./uploadSizeGuard');
const notifyQuiet = require('./notifyQuiet');

/** An upload not finished within this long no longer counts or shows. */
const UPLOAD_TTL_MS = 2 * 60 * 60 * 1000;
const SIGNED_URL_TTL_MS = 30 * 60 * 1000;
const CAPTION_MAX = 200;
const PUSH_COOLDOWN_MS = 15 * 60 * 1000;
/** What a free user is told Premium allows */
const PREMIUM_MAX_SECONDS = 60;

const bucket = () => require('firebase-admin/storage').getStorage().bucket();
const bucketName = () => process.env.FIREBASE_STORAGE_BUCKET || bucket().name;
const publicUrl = (path) =>
  `https://firebasestorage.googleapis.com/v0/b/${bucketName()}/o/${encodeURIComponent(path)}?alt=media`;

/** The viewer's video limits from their subscription. */
async function limitsFor(uid) {
  const subs = require('./subscriptionLimitService');
  const { subscriptionStatus } = await subs.getUserSubscriptionData(uid);
  const tier = getTierForStatus(subscriptionStatus);
  return {
    isPremium: tier.EVENT_VIDEO_MAX_SECONDS >= PREMIUM_MAX_SECONDS,
    maxSeconds: tier.EVENT_VIDEO_MAX_SECONDS,
    perEvent: tier.EVENT_VIDEOS_PER_EVENT,
    premiumMaxSeconds: PREMIUM_MAX_SECONDS
  };
}

/** Whether a row is a video that counts toward the uploader's cap. Pure. */
const countsTowardCap = (row, uid, now) => {
  if (!row || row.kind !== 'video' || row.uploaderId !== uid) return false;
  if (row.status !== 'uploading') return true;
  return now - (Date.parse(row.createdAt) || 0) < UPLOAD_TTL_MS;
};

/** Whether a row should be shown: finished uploads only. Pure. */
const isVisible = (row) => !(row && row.status === 'uploading');

async function videosUsed(eventId, uid, now = Date.now()) {
  // eventId equality is the indexed pattern; the rest is filtered here
  const snap = await ev.photosCol().where('eventId', '==', eventId).get();
  return snap.docs.filter(d => countsTowardCap(d.data(), uid, now)).length;
}

/** Limits plus how many the viewer has used in this event, for the picker. */
async function viewerVideoLimits(eventId, uid) {
  const [limits, used] = await Promise.all([limitsFor(uid), videosUsed(eventId, uid)]);
  return { ...limits, used };
}

async function startVideo(eventId, uid, body = {}) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const limits = await limitsFor(uid);
  const seconds = Number(body.durationSec);
  if (!Number.isFinite(seconds) || seconds <= 0) {
    throw new ServiceError(400, 'invalid_duration', 'That video has no length');
  }
  // Half a second of slack for how phones round a clip's length
  if (seconds > limits.maxSeconds + 0.5) {
    throw new ServiceError(403, 'video_too_long',
      limits.isPremium
        ? `Videos can be up to ${limits.maxSeconds} seconds`
        : `Videos can be up to ${limits.maxSeconds} seconds. Premium allows up to ${PREMIUM_MAX_SECONDS}.`,
      { ...limits, upgradeRequired: !limits.isPremium });
  }
  const used = await videosUsed(ref.id, uid);
  if (used >= limits.perEvent) {
    throw new ServiceError(403, 'video_limit',
      limits.isPremium
        ? `You've added ${limits.perEvent} videos to this event, the most anyone can`
        : `You've added ${limits.perEvent} videos to this event. Premium allows more and longer ones.`,
      { ...limits, used, upgradeRequired: !limits.isPremium });
  }

  const docRef = ev.photosCol().doc();
  const base = `events/${ref.id}/videos/${uid}/${docRef.id}`;
  const storagePaths = { video: `${base}.mp4`, poster: `${base}.jpg`, thumb: `${base}_thumb.jpg` };
  const me = (data.members && data.members[uid]) || {};
  const now = Date.now();
  await docRef.set({
    eventId: ref.id,
    uploaderId: uid,
    uploaderName: me.name || 'Member',
    kind: 'video',
    status: 'uploading',
    durationSec: Math.round(seconds * 10) / 10,
    caption: clean(body.caption, CAPTION_MAX) || '',
    challengeId: null,
    imageUrl: null,
    thumbUrl: null,
    storagePaths,
    ...ev.parsePhotoCapture(body, now),
    likes: [],
    createdAt: new Date(now).toISOString()
  });

  const sign = (path, contentType) => bucket().file(path).getSignedUrl({
    version: 'v4', action: 'write', expires: now + SIGNED_URL_TTL_MS, contentType
  }).then(([url]) => url);
  const [video, poster, thumb] = await Promise.all([
    sign(storagePaths.video, 'video/mp4'),
    sign(storagePaths.poster, 'image/jpeg'),
    sign(storagePaths.thumb, 'image/jpeg')
  ]);
  return { videoId: docRef.id, uploadUrls: { video, poster, thumb }, limits: { ...limits, used: used + 1 } };
}

async function finishVideo(eventId, uid, videoId) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const rowRef = ev.photosCol().doc(String(videoId));
  const doc = await rowRef.get();
  const row = doc.exists ? doc.data() : null;
  if (!row || row.eventId !== ref.id || row.kind !== 'video' || row.uploaderId !== uid) {
    throw new ServiceError(404, 'not_found', 'That video is gone');
  }
  // A retry after success answers with the video as it stands
  if (row.status !== 'uploading') return ev.toClientPhoto(doc, uid, data.hostId);
  if (Date.now() - (Date.parse(row.createdAt) || 0) >= UPLOAD_TTL_MS) {
    throw new ServiceError(409, 'upload_expired', 'This upload took too long. Please add the video again.');
  }

  const paths = row.storagePaths || {};
  const sizes = await readObjectSizes(bucket(), paths);
  if (!sizes.video || !sizes.poster) {
    throw new ServiceError(400, 'upload_missing', 'The video didn’t finish uploading. Please try again.');
  }
  // The cap follows the viewer's allowed length, not the declared one
  const limits = await limitsFor(uid);
  if (sizes.video > maxEventVideoBytes(limits.maxSeconds) || sizes.poster > 10 * 1024 * 1024 || (sizes.thumb || 0) > 10 * 1024 * 1024) {
    console.warn(`🚫 Oversize event video ${videoId} by ${uid}: ${JSON.stringify(sizes)}`);
    await deleteObjects(bucket(), paths);
    await rowRef.delete();
    throw new ServiceError(413, 'video_too_large', 'That video is too large. Try a shorter clip.');
  }

  const now = Date.now();
  const at = new Date(now).toISOString();
  const ready = {
    status: 'ready',
    videoUrl: publicUrl(paths.video),
    imageUrl: publicUrl(paths.poster),
    thumbUrl: sizes.thumb ? publicUrl(paths.thumb) : publicUrl(paths.poster),
    fileSize: sizes.video,
    readyAt: at
  };
  await rowRef.update(ready);
  const me = (data.members && data.members[uid]) || {};
  const { FieldValue, FieldPath } = require('firebase-admin/firestore');
  await ref.update({
    photoCount: FieldValue.increment(1), lastPhotoAt: at, updatedAt: at,
    lastPhoto: { by: me.name || 'Member', count: 1, at, kind: 'video' }
  });
  require('./eventLiveActivityService').refreshSoon(ref.id);

  // "Sal added a video" — sharing the photo push's cooldown per uploader
  const lastPush = (data.photoPushAt && data.photoPushAt[uid]) || 0;
  if (now - lastPush > PUSH_COOLDOWN_MS) {
    await ref.update(new FieldPath('photoPushAt', String(uid)), now).catch(() => {});
    for (const id of (data.memberIds || []).filter(m => m !== uid)) {
      notifyQuiet.sendInBackground(id, {
        type: 'event_photos',
        title: `${data.emoji || ev.DEFAULT_EMOJI} ${me.name || 'Someone'} added a video`,
        body: `See it in ${data.name}`,
        data: { eventId: ref.id }
      }, 'event_photos');
    }
  }
  return ev.toClientPhoto({ id: doc.id, data: () => ({ ...row, ...ready }) }, uid, data.hostId);
}

/** Storage cleanup when a video row is deleted. Best effort. */
async function deleteVideoFiles(row) {
  if (!row || row.kind !== 'video' || !row.storagePaths) return;
  await deleteObjects(bucket(), row.storagePaths).catch(() => {});
}

module.exports = {
  startVideo, finishVideo, viewerVideoLimits, deleteVideoFiles,
  // pure (tested)
  countsTowardCap, isVisible, UPLOAD_TTL_MS, PREMIUM_MAX_SECONDS
};
