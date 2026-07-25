// backend/controllers/placeFollowController.js
// Follow-a-place: any user can follow any venue. Following state lives on the
// canonical globalPlaces record (followers[]/followersCount — one transaction,
// same rule as likes); the followed place is projected into an auto-created
// "Places I Follow" circle so it shows up in the user's normal circles UI.
const { getFirestore, FieldValue } = require('../config/firebase');
const {
  COLLECTIONS,
  createCircle,
  createPlace,
  serializeDoc
} = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { resolveGlobalPlace, ensureGlobalPlaceLink } = require('../services/globalPlaceResolver');

const db = getFirestore();

const FOLLOW_CIRCLE_NAME = 'Places I Follow';

// Find or create the user's "Places I Follow" circle. Mirrors
// findOrCreateCheckInCircle (checkInController.js) — flag query first, then
// adopt-by-name so a stripped-flag copy can never spawn duplicates.
async function findOrCreateFollowCircle(userId) {
  const flaggedSnapshot = await db.collection(COLLECTIONS.CIRCLES)
    .where('owner', '==', userId)
    .where('isFollowedPlacesCircle', '==', true)
    .get();
  const flagged = flaggedSnapshot.docs.find(doc => !doc.data().deletedAt);
  if (flagged) {
    return serializeDoc(flagged);
  }

  const byNameSnapshot = await db.collection(COLLECTIONS.CIRCLES)
    .where('owner', '==', userId)
    .where('name', '==', FOLLOW_CIRCLE_NAME)
    .get();
  const candidates = byNameSnapshot.docs.filter(doc => !doc.data().deletedAt);
  if (candidates.length > 0) {
    candidates.sort((a, b) => (a.data().createdAt || '').localeCompare(b.data().createdAt || ''));
    const keeper = candidates[0];
    await keeper.ref.update({ isFollowedPlacesCircle: true, updatedAt: new Date().toISOString() });
    return serializeDoc(await keeper.ref.get());
  }

  // System circle: created outside the subscription circle cap on purpose,
  // same as the check-in circle
  const circle = createCircle({
    name: FOLLOW_CIRCLE_NAME,
    description: 'Stores and places I follow',
    privacy: 'public',
    isFollowedPlacesCircle: true,
    isSystemCircle: true,
    icon: '🔔'
  }, userId);
  const circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circle);
  console.log(`✅ Created "${FOLLOW_CIRCLE_NAME}" circle for user ${userId}`);
  return serializeDoc(await circleRef.get());
}

// Resolve any place identifier (globalPlaces doc id, legacy places doc id, or
// raw Google place id) to a linked globalPlaces doc ref, creating the global
// record from the legacy doc when needed.
async function resolveFollowTarget(placeId) {
  const { globalPlaceDoc, legacyPlaceDoc } = await resolveGlobalPlace(placeId);
  let globalPlaceId = globalPlaceDoc ? globalPlaceDoc.id : null;
  if (!globalPlaceId && legacyPlaceDoc && legacyPlaceDoc.exists) {
    // ensureGlobalPlaceLink resolves-or-creates and stamps the save doc
    globalPlaceId = await ensureGlobalPlaceLink(legacyPlaceDoc);
  }
  if (!globalPlaceId) return null;
  return db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId);
}

// Toggle membership in globalPlaces.followers[] transactionally. Returns the
// updated follower list. Idempotent in both directions.
async function updateFollowers(globalPlaceRef, userId, shouldFollow) {
  return db.runTransaction(async (transaction) => {
    const globalDoc = await transaction.get(globalPlaceRef);
    if (!globalDoc.exists) {
      const err = new Error('Global place record not found');
      err.statusCode = 404;
      throw err;
    }
    const followers = globalDoc.data().followers || [];
    const isFollower = followers.includes(userId);
    if (shouldFollow === isFollower) {
      return { followers, globalData: globalDoc.data(), changed: false };
    }
    const newFollowers = shouldFollow
      ? [...followers, userId]
      : followers.filter(id => id !== userId);
    transaction.update(globalPlaceRef, {
      followers: newFollowers,
      followersCount: newFollowers.length,
      updatedAt: new Date().toISOString()
    });
    return { followers: newFollowers, globalData: globalDoc.data(), changed: true };
  });
}

// Project the followed venue into the follow circle as a thin save doc.
// Restores a previously soft-deleted copy instead of creating a duplicate.
async function addPlaceToFollowCircle(circle, globalPlaceRef, globalData, userId) {
  const existingSnapshot = await db.collection(COLLECTIONS.PLACES)
    .where('circleId', '==', circle.id)
    .where('globalPlaceId', '==', globalPlaceRef.id)
    .get();

  const active = existingSnapshot.docs.find(doc => !doc.data().deletedAt);
  if (active) return active.id;

  const softDeleted = existingSnapshot.docs[0];
  const now = new Date().toISOString();
  if (softDeleted) {
    await softDeleted.ref.update({ deletedAt: null, updatedAt: now });
    await db.collection(COLLECTIONS.CIRCLES).doc(circle.id).update({
      placesCount: FieldValue.increment(1),
      updatedAt: now
    });
    return softDeleted.id;
  }

  const photoUrls = (globalData.photos || [])
    .map(photo => (typeof photo === 'string' ? photo : photo && photo.url))
    .filter(Boolean)
    .slice(0, 3);

  const placeData = createPlace({
    name: globalData.name || 'Unknown Place',
    address: globalData.address || '',
    location: globalData.location || null,
    category: globalData.category || 'other',
    googlePlaceId: globalData.googlePlaceId || null,
    photos: photoUrls
  }, circle.id, userId);
  const placeRef = await db.collection(COLLECTIONS.PLACES).add(placeData);
  // createPlace's allowlist doesn't carry globalPlaceId — stamp it so the save
  // doc is linked without re-running resolution
  await placeRef.update({ globalPlaceId: globalPlaceRef.id });
  await db.collection(COLLECTIONS.CIRCLES).doc(circle.id).update({
    placesCount: FieldValue.increment(1),
    updatedAt: now
  });
  return placeRef.id;
}

// @desc    Follow a place
// @route   POST /api/places/:id/follow
// @access  Private
exports.followPlace = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const globalPlaceRef = await resolveFollowTarget(req.params.id);
    if (!globalPlaceRef) {
      return res.status(404).json({ success: false, message: 'Place not found' });
    }

    const { followers, globalData } = await updateFollowers(globalPlaceRef, userId, true);

    await db.collection(COLLECTIONS.USERS).doc(userId).update({
      followedPlaces: FieldValue.arrayUnion(globalPlaceRef.id),
      updatedAt: new Date().toISOString()
    });

    const circle = await findOrCreateFollowCircle(userId);
    await addPlaceToFollowCircle(circle, globalPlaceRef, globalData, userId);

    res.status(200).json({
      success: true,
      following: true,
      followersCount: followers.length,
      globalPlaceId: globalPlaceRef.id,
      circleId: circle.id
    });
  } catch (error) {
    if (error.statusCode === 404) {
      return res.status(404).json({ success: false, message: error.message });
    }
    console.error('Error following place:', error);
    next(error);
  }
};

// @desc    Unfollow a place
// @route   DELETE /api/places/:id/follow
// @access  Private
exports.unfollowPlace = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const globalPlaceRef = await resolveFollowTarget(req.params.id);
    if (!globalPlaceRef) {
      return res.status(404).json({ success: false, message: 'Place not found' });
    }

    const { followers } = await updateFollowers(globalPlaceRef, userId, false);

    await db.collection(COLLECTIONS.USERS).doc(userId).update({
      followedPlaces: FieldValue.arrayRemove(globalPlaceRef.id),
      updatedAt: new Date().toISOString()
    });

    // Remove the projection from the follow circle. globalPlaces is the source
    // of truth — if the circle or copy is already gone, that's fine.
    const circleSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .where('isFollowedPlacesCircle', '==', true)
      .get();
    const circleDoc = circleSnapshot.docs.find(doc => !doc.data().deletedAt);
    if (circleDoc) {
      const savedSnapshot = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleDoc.id)
        .where('globalPlaceId', '==', globalPlaceRef.id)
        .get();
      const now = new Date().toISOString();
      const activeDocs = savedSnapshot.docs.filter(doc => !doc.data().deletedAt);
      for (const doc of activeDocs) {
        await doc.ref.update({ deletedAt: now, updatedAt: now });
      }
      if (activeDocs.length > 0) {
        await circleDoc.ref.update({
          placesCount: FieldValue.increment(-activeDocs.length),
          updatedAt: now
        });
      }
    }

    res.status(200).json({
      success: true,
      following: false,
      followersCount: followers.length,
      globalPlaceId: globalPlaceRef.id
    });
  } catch (error) {
    if (error.statusCode === 404) {
      return res.status(404).json({ success: false, message: error.message });
    }
    console.error('Error unfollowing place:', error);
    next(error);
  }
};

// @desc    List a place's followers (profiles)
// @route   GET /api/places/:id/followers
// @access  Private
exports.getPlaceFollowers = async (req, res, next) => {
  try {
    const globalPlaceRef = await resolveFollowTarget(req.params.id);
    if (!globalPlaceRef) {
      return res.status(404).json({ success: false, message: 'Place not found' });
    }
    const globalDoc = await globalPlaceRef.get();
    const followerIds = (globalDoc.exists && globalDoc.data().followers) || [];
    if (followerIds.length === 0) {
      return res.status(200).json({ success: true, followers: [], followersCount: 0 });
    }

    const userDocs = await db.getAll(
      ...followerIds.map(id => db.collection(COLLECTIONS.USERS).doc(id))
    );
    const followers = userDocs
      .filter(doc => doc.exists)
      .map(doc => {
        const data = doc.data();
        return {
          id: doc.id,
          displayName: data.displayName || null,
          username: data.username || null,
          profilePicture: data.profilePicture || null
        };
      });

    res.status(200).json({ success: true, followers, followersCount: followerIds.length });
  } catch (error) {
    console.error('Error fetching place followers:', error);
    next(error);
  }
};

exports.findOrCreateFollowCircle = findOrCreateFollowCircle;
