// backend/services/workoutPlace.js
//
// Where a shared workout happened: the gym the author checked into around
// the workout's time. Its main photo becomes the workout row's picture,
// replacing the plain blue card (Wes, 2026-11-19: "This image for workouts
// is boring. Use the ymca main page image instead.").
//
// Only a check-in shared at least as widely as the workout counts, so a
// workout never tells anyone where its author was who couldn't already see
// that check-in. A private check-in, or one kept off the feed, never counts.
// No check-in nearby means no place, and the row keeps its blue Workouts card.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { resolvePlacePhoto } = require('./placePhoto');

// You check in on the way in, before the workout starts, and maybe a
// little after it ends
const BEFORE_MS = 2 * 60 * 60 * 1000;
const AFTER_MS = 30 * 60 * 1000;

// How widely each one is shared: followers (and connections) > all
// connections > the Inner Circle
const CHECK_IN_WIDTH = { public: 3, innerCircle: 1 };
const WORKOUT_WIDTH = { followers: 3, connections: 2, innerCircle: 1 };

/** Pure. May everyone who sees the workout also see this check-in? */
function checkInCovers(checkIn, { audience = 'innerCircle', audienceListId = null } = {}) {
  if (!checkIn || checkIn.isPrivate === true || checkIn.showInActivityFeed === false) return false;
  const checkInWidth = CHECK_IN_WIDTH[checkIn.audience] || 2; // none = connections (the feed)
  const workoutWidth = WORKOUT_WIDTH[audience] || 1;
  if (checkInWidth !== workoutWidth || checkInWidth !== 1) return checkInWidth >= workoutWidth;
  // Both Inner Circle: a check-in to every list covers any workout; one list
  // covers only a workout to that same list
  return !checkIn.audienceListId || checkIn.audienceListId === audienceListId;
}

/**
 * Pure. The shared check-in closest to the workout's start, inside the window
 * from 2 hours before the start to 30 minutes after the end. Null when there
 * isn't one.
 */
function pickWorkoutCheckIn(checkIns, { startedAt, durationSeconds = 0 }, audience = {}) {
  const start = Date.parse(startedAt);
  if (!Number.isFinite(start)) return null;
  const end = start + Math.max(0, Number(durationSeconds) || 0) * 1000;
  let best = null;
  let bestGap = Infinity;
  for (const c of Array.isArray(checkIns) ? checkIns : []) {
    if (!checkInCovers(c, audience)) continue;
    const at = Date.parse(c.startTime || c.createdAt);
    if (!Number.isFinite(at) || at < start - BEFORE_MS || at > end + AFTER_MS) continue;
    const gap = Math.abs(at - start);
    if (gap < bestGap) { best = c; bestGap = gap; }
  }
  return best;
}

/**
 * The place fields a workout row carries (placePhoto, placeName,
 * globalPlaceId, placeId), or {} when no shared check-in matches or the
 * place has no photo. Never throws: a missing picture never blocks a share.
 */
async function workoutPlaceFor(userId, summary, audience = {}, { db = getFirestore(), resolvePhoto = resolvePlacePhoto } = {}) {
  try {
    const snap = await db.collection(COLLECTIONS.CHECK_INS).where('userId', '==', userId)
      .select('startTime', 'createdAt', 'isPrivate', 'showInActivityFeed', 'audience', 'audienceListId',
      'placeId', 'globalPlaceId', 'placeName').get();
    const checkIn = pickWorkoutCheckIn(snap.docs.map((d) => d.data()), summary || {}, audience);
    if (!checkIn) return {};
    const photo = await resolvePhoto({ placeId: checkIn.placeId || null, globalPlaceId: checkIn.globalPlaceId || null });
    if (!photo) return {};
    return {
      placePhoto: photo,
      placeName: checkIn.placeName || null,
      globalPlaceId: checkIn.globalPlaceId || null,
      placeId: checkIn.placeId || null
    };
  } catch (e) {
    console.error('workoutPlaceFor:', e.message);
    return {};
  }
}

module.exports = { pickWorkoutCheckIn, checkInCovers, workoutPlaceFor, BEFORE_MS, AFTER_MS };
