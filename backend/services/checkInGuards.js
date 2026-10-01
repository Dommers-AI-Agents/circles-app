// backend/services/checkInGuards.js
//
// What a check-in may reach and what it may spend. Security audit 2026-10-01:
//
// - `notifiedGroups` was written straight into the messages collection, so a
//   check-in could drop a message into ANY conversation id — other people's
//   chats included. Only conversations the person is part of survive.
// - `notifiedUsers` pushed to any user id. The iOS picker
//   (CheckInRecipientSelectionViewController) offers accepted connections
//   only, so that's the rule here too, minus anyone blocked either way.
// - A check-in at a venue new to the platform runs Google Find Place +
//   Details + Photo. A script inventing place names (with no location to
//   anchor them) billed all three per call. Lookups now need a location, are
//   capped per person per day, and a miss is remembered so the same fake
//   name at the same spot never bills twice.

const crypto = require('crypto');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { isSameUser } = require('./idService');
const { excludedUserIds } = require('./moderationService');
const dailyBudget = require('./dailyBudget');

const MAX_RECIPIENTS = 50;      // per list (groups, people)
const MAX_PLACE_NAME = 200;
const MAX_PLACE_ADDRESS = 300;
const MISS_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MISSES = 'placesLookupMisses';

const idList = (value) => {
  if (!Array.isArray(value)) return [];
  const ids = value.filter(id => typeof id === 'string' && id.trim()).map(id => id.trim());
  return [...new Set(ids)].slice(0, MAX_RECIPIENTS);
};

/**
 * Returns { notifiedGroups, notifiedUsers } trimmed to what `userId` may
 * actually reach. Unreachable ids are dropped silently (an old client's
 * stale pick shouldn't fail the whole check-in).
 */
async function sanitizeCheckInRecipients(userId, userData, { notifiedGroups, notifiedUsers } = {}) {
  const db = getFirestore();
  const groups = idList(notifiedGroups);
  const people = idList(notifiedUsers).filter(id => !isSameUser(id, userId));

  const groupSnaps = await Promise.all(groups.map(id => db.collection(COLLECTIONS.CONVERSATIONS).doc(id).get()));
  const allowedGroups = groupSnaps
    .filter(snap => snap.exists && Array.isArray(snap.data().participants)
      && snap.data().participants.some(p => isSameUser(p, userId)))
    .map(snap => snap.id);

  let allowedPeople = [];
  if (people.length > 0) {
    const { getConnectedUserIds } = require('../utils/networkAccess');
    const connected = [...await getConnectedUserIds(userId)];
    const blocked = excludedUserIds(userData);
    allowedPeople = people.filter(id => !blocked.has(id) && connected.some(c => isSameUser(c, id)));
  }

  return { notifiedGroups: allowedGroups, notifiedUsers: allowedPeople };
}

/** Caps free-text venue fields that end up in pushes and chat messages. */
function capPlaceText(checkInData) {
  if (typeof checkInData.placeName === 'string') checkInData.placeName = checkInData.placeName.slice(0, MAX_PLACE_NAME);
  if (typeof checkInData.placeAddress === 'string') checkInData.placeAddress = checkInData.placeAddress.slice(0, MAX_PLACE_ADDRESS);
  return checkInData;
}

const missKey = (placeName, location) => {
  const name = String(placeName || '').trim().toLowerCase().replace(/\s+/g, ' ');
  const key = `${name}|${Number(location.latitude).toFixed(3)}|${Number(location.longitude).toFixed(3)}`;
  return crypto.createHash('sha1').update(key).digest('hex');
};

/**
 * Runs the paid Google lookup (`lookup(placeName, location)`, e.g. the
 * check-in controller's enrichPlaceWithGoogleData) only when it can be
 * anchored and paid for. Returns the lookup's result, or {} when skipped —
 * the check-in then saves with what the client sent, exactly as when Google
 * finds nothing.
 */
async function gatedPlacesLookup({ userId, placeName, location, lookup, now = new Date() }) {
  if (!location || !Number.isFinite(Number(location.latitude)) || !Number.isFinite(Number(location.longitude))) {
    return {};
  }
  const db = getFirestore();
  const missRef = db.collection(MISSES).doc(missKey(placeName, location));
  try {
    const miss = await missRef.get();
    if (miss.exists && now.getTime() - Date.parse(miss.data().at) < MISS_TTL_MS) return {};
  } catch (error) {
    console.error('⚠️ Places miss-cache read failed:', error.message);
  }

  const budget = await dailyBudget.consumePlacesLookup(userId);
  if (!budget.allowed) {
    console.warn(`💸 Places lookup skipped for ${userId}: daily cap (${budget.limit}) reached`);
    return {};
  }

  const result = (await lookup(placeName, location)) || {};
  // Only a definite miss is remembered; a Google error ({}) may succeed later.
  if (result.noMatch) {
    missRef.set({ at: now.toISOString() }).catch((error) =>
      console.error('⚠️ Places miss-cache write failed:', error.message));
  }
  return result;
}

module.exports = {
  sanitizeCheckInRecipients,
  capPlaceText,
  gatedPlacesLookup,
  MAX_RECIPIENTS,
  MAX_PLACE_NAME
};
