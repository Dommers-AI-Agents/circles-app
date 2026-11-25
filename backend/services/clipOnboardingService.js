// backend/services/clipOnboardingService.js
//
// The App Clip's steps after the save (Wes, 2026-11-24): where they live,
// a few first favorites, people to follow — all before the install. This
// service holds the two pieces the clip can't do with existing endpoints:
//
// - saveFavoritesForClip: up to three places picked from Apple Maps go on
//   the map through the core save (services/placeSaveService), the same path
//   as Add Place — venue link, duplicate check across all circles, FavCoins
//   and activity. Into Favorite Local Spots, like the store itself.
// - recordClipOnboarding: what the clip finished, kept on the user so the
//   app's first run (and the dashboard) know; the clip also hands the same
//   summary to the app through its mailbox.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { favoriteLocalCircle } = require('./clipStoreSave');
const { isPlaceCategory } = require('../config/placeCategories');
const { nowIso } = require('../utils/ids');

const MAX_FAVORITES = 3;
const STEPS = ['neighborhood', 'favorites', 'people'];

const cleanText = (value, max) => (typeof value === 'string' ? value.trim().slice(0, max) : '');
const coordinate = (pick, key) => Number(pick[key] ?? (pick.location && pick.location[key]));
const clampInt = (value, min, max) => {
  const n = Number(value);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, Math.round(n))) : min;
};

/** A pick the save can use: a name and a real spot */
function validPick(pick) {
  if (!pick || typeof pick !== 'object') return false;
  const lat = coordinate(pick, 'lat');
  const lng = coordinate(pick, 'lng');
  return cleanText(pick.name, 120).length > 0
    && Number.isFinite(lat) && Number.isFinite(lng)
    && Math.abs(lat) <= 90 && Math.abs(lng) <= 180
    && !(lat === 0 && lng === 0);
}

/** The core save's body for one Apple Maps pick */
function favoriteBody(pick, circleId) {
  const lat = coordinate(pick, 'lat');
  const lng = coordinate(pick, 'lng');
  const optional = (key, max, as = key) => {
    const value = cleanText(pick[key], max);
    return value ? { [as]: value } : {};
  };
  return {
    circleId,
    name: cleanText(pick.name, 120),
    // The core save needs an address; a bare POI gets its spot
    address: cleanText(pick.address, 200) || `${lat.toFixed(5)}, ${lng.toFixed(5)}`,
    location: { type: 'Point', coordinates: [lng, lat] },
    // The clip maps Apple's POI category; the server's derivation refines it
    category: isPlaceCategory(pick.category) ? pick.category : 'other',
    ...optional('phone', 40),
    ...optional('website', 300),
    ...optional('neighborhood', 80),
    ...optional('applePoiCategory', 80),
    ...optional('applePlaceId', 128),
    appleMatched: true,
    // A resend on a weak signal never saves twice
    ...optional('clientSaveId', 64)
  };
}

/**
 * Saves up to three picks for `user` (req.user).
 * @returns {Promise<{saved: Array<{placeId, name}>, alreadySaved: Array<{placeId, name}>,
 *   failed: Array<{name, reason}>, coins: number, circleId: string|null}>}
 */
async function saveFavoritesForClip(user, picks, { saveImpl, circleImpl } = {}) {
  const wanted = (Array.isArray(picks) ? picks : []).filter(validPick).slice(0, MAX_FAVORITES);
  const out = { saved: [], alreadySaved: [], failed: [], coins: 0, circleId: null };
  if (wanted.length === 0) return out;

  const circle = await (circleImpl || favoriteLocalCircle)(user.uid);
  if (!circle) {
    console.warn(`[clip-favorites] no Favorite Local Spots yet for ${user.uid}`);
    out.failed = wanted.map((pick) => ({ name: cleanText(pick.name, 120), reason: 'no_circle' }));
    return out;
  }
  out.circleId = circle.id;

  const save = saveImpl || require('./placeSaveService').savePlace;
  for (const pick of wanted) {
    const name = cleanText(pick.name, 120);
    try {
      const result = await save(user, favoriteBody(pick, circle.id));
      const payload = result.payload || {};
      if (result.status === 201 && payload.place) {
        out.saved.push({ placeId: payload.place.id, name });
        const credit = payload.piggyBank;
        if (credit && credit.credited && Number.isFinite(credit.coins)) out.coins += credit.coins;
        // Activity, FavCoins and pushes, after the clip has its answer
        if (result.afterResponse) {
          setImmediate(() => result.afterResponse().catch((err) => console.error('[clip-favorites] after-save work failed:', err.message)));
        }
      } else if (payload.code === 'DUPLICATE_PLACE') {
        out.alreadySaved.push({ placeId: payload.existingPlaceId || null, name });
      } else {
        console.warn(`[clip-favorites] save refused for ${user.uid}: ${result.status} ${payload.message || ''}`);
        out.failed.push({ name, reason: payload.code || String(result.status) });
      }
    } catch (error) {
      console.error(`[clip-favorites] save failed for ${user.uid}:`, error.message);
      out.failed.push({ name, reason: 'error' });
    }
  }
  return out;
}

/** What the clip finished, on the user doc (merge; the newest clip run wins) */
async function recordClipOnboarding(uid, summary = {}, { db = getFirestore() } = {}) {
  const clean = {
    zipcodeSet: summary.zipcodeSet === true,
    favoritesSaved: clampInt(summary.favoritesSaved, 0, 10),
    followed: clampInt(summary.followed, 0, 50),
    skipped: (Array.isArray(summary.skipped) ? summary.skipped : []).filter((step) => STEPS.includes(step)),
    code: cleanText(summary.code, 16) || null,
    completedAt: nowIso()
  };
  await db.collection(COLLECTIONS.USERS).doc(uid).set({ clipOnboarding: clean }, { merge: true });
  return clean;
}

module.exports = { saveFavoritesForClip, favoriteBody, validPick, recordClipOnboarding, MAX_FAVORITES };
