// backend/services/placePhotoService.js
//
// One photo library per place: the canonical globalPlaces/{id}.photos array.
// Every photo of a venue lives there, in display order (the array order IS the
// order; the first visible public photo is the cover). This service owns who
// may see, add, reorder, hide and delete them, so every endpoint agrees.
//
// Rules (Wes, 2026-09-30):
// - A photo added from a PRIVATE save is visible to its uploader only.
// - Customer photos show immediately, appended after the owner's arrangement.
// - The venue's owner, its managers and super-users manage everything: order,
//   cover, removal. Free for every verified owner.
// - An owner/admin removal is a soft remove (removedAt/removedBy): the entry
//   stays so the same URL can't come back by being re-added. An uploader
//   deleting their own photo removes it for real.
//
// Entry shape (createAttributedPhoto + the fields added here):
//   { id, url, uploadedBy, uploadedByName, uploadedAt, source, width, height,
//     fileSize, likes?, likesCount?, private?, removedAt?, removedBy? }
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { isSameUser } = require('./idService');
const { normalizePrivacy, PRIVACY } = require('./visibility');
const { ServiceError } = require('../utils/serviceError');

const db = getFirestore();
const { newId } = require('../utils/ids');

/** A library entry, the createAttributedPhoto() shape, with our own id. */
const createAttributedPhoto = ({ url, uploadedBy = null, uploadedByName = null, source = 'user_upload' }) => ({
  id: newId(),
  url,
  uploadedBy,
  uploadedByName,
  uploadedAt: new Date().toISOString(),
  source,
  width: null,
  height: null,
  fileSize: null
});

// ---------- Pure rules (unit-tested) ----------

const urlOf = (photo) => (typeof photo === 'string' ? photo : (photo && photo.url) || null);
const isRemoved = (photo) => !!(photo && typeof photo === 'object' && photo.removedAt);

/** Whether `viewerId` sees this pool entry at all. */
const canSee = (photo, viewerId) => {
  if (!photo || !urlOf(photo)) return false;
  if (isRemoved(photo)) return false;
  if (typeof photo === 'object' && photo.private === true) {
    return !!viewerId && isSameUser(photo.uploadedBy, viewerId);
  }
  return true;
};

/** The pool as `viewerId` sees it: visible entries, stored order, one per URL. */
const visiblePhotos = (photos, viewerId) => {
  const seen = new Set();
  return (photos || []).filter((photo) => {
    if (!canSee(photo, viewerId)) return false;
    const url = urlOf(photo);
    if (seen.has(url)) return false;
    seen.add(url);
    return true;
  });
};

/**
 * URLs this viewer must NOT see even if they turn up somewhere else (a save
 * doc's own photos array still holding a mirrored copy): removed photos and
 * other people's private ones.
 */
const hiddenUrls = (photos, viewerId) => new Set(
  (photos || []).filter((photo) => photo && typeof photo === 'object' && !canSee(photo, viewerId))
    .map(urlOf).filter(Boolean)
);

/** The cover: the first photo everyone can see, or null. */
const coverUrl = (photos) => {
  const first = (photos || []).find((photo) => canSee(photo, null));
  return first ? urlOf(first) : null;
};

/**
 * New array order: `orderedIds` first, in that order; every other entry
 * (unlisted, private, removed) keeps its relative place after them. Unknown
 * ids are ignored; nothing is dropped.
 */
const reordered = (photos, orderedIds) => {
  const list = photos || [];
  const byId = new Map(list.filter((p) => p && p.id).map((p) => [p.id, p]));
  const picked = [];
  const used = new Set();
  for (const id of orderedIds || []) {
    if (byId.has(id) && !used.has(id)) {
      picked.push(byId.get(id));
      used.add(id);
    }
  }
  return [...picked, ...list.filter((p) => !(p && p.id && used.has(p.id)))];
};

const movedToFront = (photos, photoId) => reordered(photos, [photoId]);

/** What `rights` let this user do to one photo. */
const permissionsFor = (photo, userId, rights) => {
  const own = !!photo && !!userId && isSameUser(photo.uploadedBy, userId);
  return {
    // An owner/admin removes (soft); an uploader deletes their own (hard)
    remove: !!(rights && rights.canManage),
    delete: own,
    own
  };
};

// ---------- Firestore ----------

const placeRef = (globalPlaceId) => db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(String(globalPlaceId));

/** The rewards venue claimed for this place, if any (by globalPlaceId, else googlePlaceId). */
async function venueForPlace(globalPlaceId, placeData) {
  const venues = db.collection(STICKER_COLLECTIONS.STICKER_VENUES);
  const direct = await venues.where('globalPlaceId', '==', String(globalPlaceId)).limit(1).get();
  if (!direct.empty) return { venueId: direct.docs[0].id, ...direct.docs[0].data() };
  const googleId = placeData && (placeData.googlePlaceId || (placeData.googleData && placeData.googleData.placeId));
  if (!googleId) return null;
  const byGoogle = await venues.where('googlePlaceId', '==', googleId).limit(1).get();
  return byGoogle.empty ? null : { venueId: byGoogle.docs[0].id, ...byGoogle.docs[0].data() };
}

/**
 * Who manages this place's photos: its venue's owner and managers, and every
 * super-user. `user` is req.user (uid + isSuperUser).
 */
async function rightsFor(user, globalPlaceId, placeData) {
  const userId = user && (user.uid || user.id);
  if (!userId) return { canManage: false, isSuperUser: false, isVenueTeam: false };
  const isSuperUser = user.isSuperUser === true;
  let isVenueTeam = false;
  try {
    const venue = await venueForPlace(globalPlaceId, placeData);
    if (venue) {
      const team = [venue.ownerUserId, ...(Array.isArray(venue.managerUserIds) ? venue.managerUserIds : [])].filter(Boolean);
      isVenueTeam = team.some((id) => isSameUser(id, userId));
    }
  } catch (e) {
    console.error('[place-photos] venue lookup failed', e.message);
  }
  return { canManage: isSuperUser || isVenueTeam, isSuperUser, isVenueTeam };
}

/**
 * A save is private when its own tier says so, or when it has no tier of its
 * own (it follows its circle) and the circle is Private.
 */
const effectivelyPrivate = (placePrivacy, circlePrivacy) => {
  const own = normalizePrivacy(placePrivacy);
  if (own) return own === PRIVACY.PRIVATE;
  return normalizePrivacy(circlePrivacy) === PRIVACY.PRIVATE;
};

/** A save doc's effective privacy, reading its circle when it follows one. */
async function saveIsPrivate(save) {
  if (normalizePrivacy(save.privacy)) return effectivelyPrivate(save.privacy, null);
  if (!save.circleId) return false;
  const circle = await db.collection(COLLECTIONS.CIRCLES).doc(String(save.circleId)).get();
  return effectivelyPrivate(null, circle.exists ? circle.data().privacy : null);
}

/**
 * Whether a photo this user adds should be private: they have a save of the
 * place and every one of their saves is (effectively) Private. No save
 * (adding from a venue page) = public.
 */
async function uploaderSaveIsPrivate(globalPlaceId, userId) {
  const saves = await db.collection(COLLECTIONS.PLACES).where('globalPlaceId', '==', String(globalPlaceId)).get();
  const mine = saves.docs.map((d) => d.data()).filter((p) => !p.deletedAt && isSameUser(p.addedBy, userId));
  if (mine.length === 0) return false;
  for (const save of mine) {
    if (!(await saveIsPrivate(save))) return false;
  }
  return true;
}

/**
 * Read-modify-write of the photos array in a transaction, so a like, a
 * reorder, an upload and a delete arriving together don't erase each other.
 * `change(photos, data)` returns the new array (or throws a ServiceError).
 * Keeps coverPhotoUrl in step with the order (first public visible photo).
 */
async function mutatePhotos(globalPlaceId, change) {
  const ref = placeRef(globalPlaceId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new ServiceError(404, 'not_found', 'Place not found');
    const data = snap.data();
    const next = change(Array.isArray(data.photos) ? [...data.photos] : [], data);
    const cover = coverUrl(next);
    tx.update(ref, { photos: next, coverPhotoUrl: cover, updatedAt: new Date().toISOString() });
    return { photos: next, coverPhotoUrl: cover, data };
  });
}

const findIndex = (photos, photoId) => photos.findIndex((p) => p && typeof p === 'object' && p.id === photoId);

/** Owner/admin: new order. `photoIds` are the visible photos, front first. */
async function reorder(globalPlaceId, photoIds, rights) {
  if (!rights.canManage) throw new ServiceError(403, 'forbidden', 'Only the place\'s owner can arrange its photos.');
  if (!Array.isArray(photoIds) || photoIds.length === 0) throw new ServiceError(400, 'bad_order', 'Send the photo ids in order.');
  return mutatePhotos(globalPlaceId, (photos) => reordered(photos, photoIds.map(String)));
}

/** Owner/admin: make this photo the cover (moves it to the front). */
async function setCover(globalPlaceId, photoId, rights) {
  if (!rights.canManage) throw new ServiceError(403, 'forbidden', 'Only the place\'s owner can choose its cover.');
  return mutatePhotos(globalPlaceId, (photos) => {
    const index = findIndex(photos, photoId);
    if (index === -1 || !canSee(photos[index], null)) throw new ServiceError(404, 'not_found', 'Photo not found');
    return movedToFront(photos, photoId);
  });
}

/**
 * Remove a photo. The uploader deletes their own outright; the owner, a
 * manager or a super-user removes anyone's (soft, so it stays gone).
 * Returns { url, mode: 'deleted' | 'removed' }.
 */
async function remove(globalPlaceId, photoId, userId, rights) {
  let outcome = null;
  const result = await mutatePhotos(globalPlaceId, (photos) => {
    const index = findIndex(photos, photoId);
    if (index === -1 || isRemoved(photos[index])) throw new ServiceError(404, 'not_found', 'Photo not found');
    const photo = photos[index];
    const may = permissionsFor(photo, userId, rights);
    if (may.remove && !may.own) {
      photos[index] = { ...photo, removedAt: new Date().toISOString(), removedBy: userId };
      outcome = { url: photo.url, mode: 'removed' };
      return photos;
    }
    if (may.delete || may.remove) {
      photos.splice(index, 1);
      outcome = { url: photo.url, mode: 'deleted' };
      return photos;
    }
    throw new ServiceError(403, 'forbidden', 'You can only remove photos you added.');
  });
  return { ...outcome, coverPhotoUrl: result.coverPhotoUrl };
}

/** Like / unlike in the transaction. Returns { photo, liked, changed }. */
async function setLiked(globalPlaceId, photoId, userId, liked) {
  let out = null;
  await mutatePhotos(globalPlaceId, (photos, data) => {
    const index = findIndex(photos, photoId);
    if (index === -1 || !canSee(photos[index], userId)) throw new ServiceError(404, 'not_found', 'Photo not found');
    const photo = photos[index];
    const likes = Array.isArray(photo.likes) ? photo.likes : [];
    const has = likes.some((id) => isSameUser(id, userId));
    if (has === liked) {
      out = { photo, changed: false, likesCount: likes.length, placeName: data.name };
      return photos;
    }
    const nextLikes = liked ? [...likes, userId] : likes.filter((id) => !isSameUser(id, userId));
    photos[index] = { ...photo, likes: nextLikes, likesCount: nextLikes.length };
    out = { photo, changed: true, likesCount: nextLikes.length, placeName: data.name };
    return photos;
  });
  return out;
}

/**
 * Add a photo to the pool (append, after the owner's arrangement). A URL
 * already there — including a removed one — returns the existing entry and
 * adds nothing. `entry` is a createAttributedPhoto() result.
 */
async function append(globalPlaceId, entry) {
  let existing = null;
  let added = false;
  await mutatePhotos(globalPlaceId, (photos) => {
    existing = photos.find((p) => urlOf(p) === entry.url) || null;
    if (existing) return photos;
    added = true;
    return [...photos, entry];
  });
  return { entry: existing || entry, added };
}

/**
 * Bring photos that arrived on a SAVE (Add Place, Edit Place, Street View,
 * an import's Look Around fill, a Google refresh) into the place's library,
 * so there is one set of photos no matter which screen added them.
 *
 * - ownUrls: what this user uploaded — attributed to them (private when
 *   their save is), appended after the owner's arrangement; a copy already
 *   in the library with no uploader (an older merge) is attributed to them.
 * - other photos (stock Google / Look Around): only fill an EMPTY library,
 *   unattributed, so they never crowd a place that has real photos.
 * - removedUrls: this user's own library photos are deleted; anyone's are
 *   removed when the user manages the place; other people's are left alone
 *   (not yours to remove).
 * Best-effort: never throws. Returns { added, removed }.
 */
async function adoptSavePhotos({ globalPlaceId, user, photos = [], ownUrls = [], removedUrls = [], isPrivate = false }) {
  const userId = user && (user.uid || user.id);
  const out = { added: 0, removed: 0 };
  if (!globalPlaceId || !userId) return out;
  const own = new Set((ownUrls || []).filter((u) => typeof u === 'string' && u));
  const incoming = (photos || []).map(urlOf).filter(Boolean);
  try {
    await mutatePhotos(globalPlaceId, (list) => {
      const hasPublic = list.some((p) => canSee(p, null));
      for (const url of new Set([...own, ...incoming])) {
        const index = list.findIndex((p) => urlOf(p) === url);
        if (index !== -1) {
          const entry = list[index];
          if (own.has(url) && typeof entry === 'object' && !entry.uploadedBy && !entry.removedAt) {
            list[index] = { ...entry, uploadedBy: userId, uploadedByName: user.displayName || null,
              source: 'user_upload', ...(isPrivate ? { private: true } : {}) };
          }
          continue;
        }
        if (own.has(url)) {
          const entry = createAttributedPhoto({ url, uploadedBy: userId, uploadedByName: user.displayName || null, source: 'user_upload' });
          if (isPrivate) entry.private = true;
          list.push(entry);
          out.added += 1;
        } else if (!hasPublic && !isPrivate) {
          list.push(createAttributedPhoto({ url, uploadedBy: null, source: 'auto' }));
          out.added += 1;
        }
      }
      return list;
    });
  } catch (e) {
    console.error('[place-photos] adopt failed', e.message);
  }
  if ((removedUrls || []).length > 0) {
    try {
      const snap = await placeRef(globalPlaceId).get();
      const data = snap.exists ? snap.data() : {};
      const rights = await rightsFor(user, globalPlaceId, data);
      for (const url of removedUrls) {
        const entry = (data.photos || []).find((p) => urlOf(p) === url && !isRemoved(p));
        if (!entry || !entry.id) continue;
        const may = permissionsFor(entry, userId, rights);
        if (!may.delete && !may.remove) continue;
        await remove(globalPlaceId, entry.id, userId, rights);
        out.removed += 1;
      }
    } catch (e) {
      console.error('[place-photos] removal sync failed', e.message);
    }
  }
  return out;
}

// ---------- Moments at a place ----------

/**
 * Every save-doc id that belongs to this venue (moments are keyed by the
 * uploader's own save id, not by the venue).
 */
async function saveIdsForPlace(globalPlaceId, placeData) {
  const ids = new Set((placeData && placeData.legacyPlaceIds) || []);
  const saves = await db.collection(COLLECTIONS.PLACES).where('globalPlaceId', '==', String(globalPlaceId)).select().get();
  saves.docs.forEach((doc) => ids.add(doc.id));
  ids.add(String(globalPlaceId));
  return [...ids];
}

module.exports = {
  // rules
  urlOf, isRemoved, canSee, visiblePhotos, hiddenUrls, coverUrl, reordered, movedToFront, permissionsFor,
  // data
  effectivelyPrivate, saveIsPrivate, venueForPlace, rightsFor, uploaderSaveIsPrivate, mutatePhotos, reorder, setCover, remove, setLiked, append, adoptSavePhotos, saveIdsForPlace
};
