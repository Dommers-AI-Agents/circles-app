// controllers/places/placeSocialController.js
// Place likes, savers, comments, replies and view tracking (social data lives on globalPlaces)
// Split out of firebasePlaceController.js (handlers unchanged).
// backend/controllers/firebasePlaceController.js
const admin = require('firebase-admin');
const { projectPublicUser } = require('../../services/publicUserProjection');
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');
const { normalizeUserId, isSameUser } = require('../../services/idService');
const { ensureGlobalPlaceLink } = require('../../services/globalPlaceResolver');
const { GLOBAL_COLLECTIONS } = require('../../models/GlobalPlace');
const notificationService = require('../../services/notificationService');
const { trackPlaceView, trackPlaceLiked } = require('../../services/activityService');
const rewardService = require('../../services/rewardService');
const piggyBankService = require('../../services/piggyBankService');
const { getGlobalSocial } = require('../../services/placeReadService');
const db = getFirestore();

// @desc    Like a place
// @route   POST /api/places/:id/like
// @access  Private
exports.likePlace = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    
    // Get the place
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check if user has permission to view this place
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    const circle = serializeDoc(circleDoc);
    
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    // Check if users are connected for myNetwork privacy
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to like this place'
      });
    }
    
    // Likes live on the canonical venue record: one transaction, no matter
    // how many saved copies of the place exist
    const globalPlaceId = place.globalPlaceId || await ensureGlobalPlaceLink(placeDoc);
    if (!globalPlaceId) {
      return res.status(500).json({
        success: false,
        message: 'Place is not linked to a global place record'
      });
    }

    const globalPlaceRef = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId);
    const { alreadyLiked, updatedLikes } = await db.runTransaction(async (transaction) => {
      const globalDoc = await transaction.get(globalPlaceRef);
      const likes = (globalDoc.exists && globalDoc.data().likes) || [];
      const liked = likes.includes(userId);
      const newLikes = liked ? likes.filter(id => id !== userId) : [...likes, userId];
      transaction.update(globalPlaceRef, {
        likes: newLikes,
        likesCount: newLikes.length,
        updatedAt: new Date().toISOString()
      });
      return { alreadyLiked: liked, updatedLikes: newLikes };
    });

    const updatedPlace = {
      ...place,
      globalPlaceId,
      likes: updatedLikes,
      likesCount: updatedLikes.length
    };
    
    // Send notification to place owner if someone liked their place (not unliked, and not their own place)
    if (!alreadyLiked && place.addedBy !== userId) {
      await notificationService.sendPlaceLikeNotification(
        place.addedBy,
        userId,
        placeId,
        place.name
      );
    }

    // Piggy bank: a nickel for your first like on this venue (not unlikes,
    // not your own places; per-venue dedup means a relike can't re-mint).
    // Awaited so the response can carry the credit and the app can play the
    // coin-drop — credit() never throws.
    let piggyBank = null;
    if (!alreadyLiked && place.addedBy !== userId) {
      piggyBank = await piggyBankService.credit({
        userId,
        eventType: 'place_liked',
        sourceRef: { globalPlaceId }
      });
    }

    res.status(200).json({
      success: true,
      liked: !alreadyLiked,
      place: updatedPlace,
      piggyBank
    });
    
    // Track comprehensive activity for likes (not unlikes) with connection notifications
    if (!alreadyLiked) {
      await trackPlaceLiked(
        placeId,
        place.name || 'Unknown Place',
        place.circleId,
        circle.name || 'Unknown Circle',
        userId,
        place.addedBy
      );
    }
    
  } catch (error) {
    console.error('Error liking place:', error);
    next(error);
  }
};

// @desc    Get likes for a place
// @route   GET /api/places/:id/likes
// @access  Private
exports.getPlaceLikes = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    
    // Get the place
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check if user has permission to view this place (same logic as likePlace)
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    const circle = serializeDoc(circleDoc);
    
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    // Check if users are connected for myNetwork privacy
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view likes for this place'
      });
    }
    
    // Likes live on the canonical venue record
    const { likes } = await getGlobalSocial(placeDoc);

    if (likes.length === 0) {
      return res.status(200).json({
        success: true,
        likes: [],
        count: 0
      });
    }
    
    // Fetch user details for each user who liked the place
    const userPromises = likes.map(async (likeUserId) => {
      // Handle complex ID format if needed
      let actualUserId = likeUserId;
      if (likeUserId && likeUserId.includes('.')) {
        const parts = likeUserId.split('.');
        if (parts.length >= 2) {
          actualUserId = parts[1]; // Use the middle part as Firebase UID
        }
      }
      
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(actualUserId).get();
      if (userDoc.exists) {
        const userData = serializeDoc(userDoc);
        return {
          _id: userData.id,
          displayName: userData.displayName,
          profilePicture: userData.profilePicture,
          bio: userData.bio
        };
      }
      return null;
    });
    
    const users = await Promise.all(userPromises);
    const validUsers = users.filter(user => user !== null);
    
    res.status(200).json({
      success: true,
      likes: validUsers,
      count: validUsers.length
    });
    
  } catch (error) {
    console.error('Error fetching place likes:', error);
    next(error);
  }
};

// @desc    Get users who saved this place (across all circles containing it)
// @route   GET /api/places/:id/savers
// @access  Private
exports.getPlaceSavers = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;

    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    const place = serializeDoc(placeDoc);

    // Find every saved copy of this place via its canonical venue link
    // (googlePlaceId fallback for any doc the backfill missed)
    let placeDocs = [placeDoc];
    const saversGlobalId = place.globalPlaceId || await ensureGlobalPlaceLink(placeDoc);
    if (saversGlobalId) {
      const snapshot = await db.collection(COLLECTIONS.PLACES)
        .where('globalPlaceId', '==', saversGlobalId)
        .get();
      if (!snapshot.empty) {
        placeDocs = snapshot.docs;
      }
    } else if (place.googlePlaceId) {
      const snapshot = await db.collection(COLLECTIONS.PLACES)
        .where('googlePlaceId', '==', place.googlePlaceId)
        .get();
      if (!snapshot.empty) {
        placeDocs = snapshot.docs;
      }
    }

    // Group circle IDs by saver
    const circleIdsBySaver = new Map();
    for (const doc of placeDocs) {
      const data = doc.data();
      const saverId = normalizeUserId(data.addedBy);
      if (!saverId) continue;
      if (!circleIdsBySaver.has(saverId)) {
        circleIdsBySaver.set(saverId, new Set());
      }
      if (data.circleId) {
        circleIdsBySaver.get(saverId).add(data.circleId);
      }
    }

    const totalCount = circleIdsBySaver.size;
    if (totalCount === 0) {
      return res.status(200).json({
        success: true,
        savers: [],
        count: 0,
        totalCount: 0
      });
    }

    // Load all involved circles in one batch to check visibility
    const circleIds = [...new Set([...circleIdsBySaver.values()].flatMap(set => [...set]))];
    const circleRefs = circleIds.map(id => db.collection(COLLECTIONS.CIRCLES).doc(id));
    const circleDocs = circleRefs.length ? await db.getAll(...circleRefs) : [];
    const circlesById = new Map();
    circleDocs.forEach(doc => {
      if (doc.exists) circlesById.set(doc.id, serializeDoc(doc));
    });

    // Requester's connections (stored per-direction, so check both).
    // Keep outgoing statuses so pending requests render as 'pending'.
    const [outgoing, incomingAccepted] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    const connectionStatusById = new Map();
    outgoing.forEach(doc => {
      const conn = doc.data();
      connectionStatusById.set(normalizeUserId(conn.connectedUserId), conn.status);
    });
    incomingAccepted.forEach(doc => {
      connectionStatusById.set(normalizeUserId(doc.data().userId), 'accepted');
    });
    const connectedIds = new Set(
      [...connectionStatusById.entries()]
        .filter(([, status]) => status === 'accepted')
        .map(([id]) => id)
    );

    // A saver is visible if at least one circle holding their save is visible
    // to the requester
    const isCircleVisible = (circle, saverId) => {
      if (!circle) return false;
      if (saverId === userId || circle.owner === userId) return true;
      if (circle.privacy === 'public') return true;
      if (circle.sharedWith && circle.sharedWith.includes(userId)) return true;
      if (circle.privacy === 'myNetwork' && connectedIds.has(normalizeUserId(circle.owner))) return true;
      return false;
    };

    const visibleSaverIds = [...circleIdsBySaver.entries()]
      .filter(([saverId, ids]) =>
        [...ids].some(circleId => isCircleVisible(circlesById.get(circleId), saverId)))
      .map(([saverId]) => saverId);

    if (visibleSaverIds.length === 0) {
      return res.status(200).json({
        success: true,
        savers: [],
        count: 0,
        totalCount
      });
    }

    // Follow state for the requester, to render Follow/Connect buttons
    const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userFollowing = new Set((currentUserDoc.data() || {}).following || []);

    const userRefs = visibleSaverIds.map(id => db.collection(COLLECTIONS.USERS).doc(id));
    const userDocs = await db.getAll(...userRefs);
    const savers = userDocs
      .filter(doc => doc.exists)
      .map(doc => {
        const userData = serializeDoc(doc);
        return {
          _id: userData.id,
          displayName: userData.displayName,
          profilePicture: userData.profilePicture,
          bio: userData.bio,
          connectionStatus: userData.id === userId
            ? 'self'
            : (connectionStatusById.get(userData.id) || 'none'),
          isFollowing: userFollowing.has(userData.id)
        };
      });

    res.status(200).json({
      success: true,
      savers,
      count: savers.length,
      totalCount
    });

  } catch (error) {
    console.error('Error fetching place savers:', error);
    next(error);
  }
};

// @desc    Get comments for a place
// @route   GET /api/places/:id/comments
// @access  Private
exports.getPlaceComments = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    
    console.log('🔍 getPlaceComments called:', {
      placeId,
      userId,
      timestamp: new Date().toISOString()
    });
    
    // Get the place to check permissions
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Skip circle permission checks for places without circleId
    // (these are check-in places that already passed security checks to be displayed)
    if (place.circleId) {
      // Check permissions (same as likePlace)
      const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
      const circleDoc = await circleRef.get();
      const circle = serializeDoc(circleDoc);
      
      const isOwner = circle.owner === userId;
      const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
      const isPublic = circle.privacy === 'public';
      
      let isConnected = false;
      if (circle.privacy === 'myNetwork' && !isOwner) {
        const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', userId)
          .where('connectedUserId', '==', circle.owner)
          .where('status', '==', 'accepted')
          .get();
          
        const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', circle.owner)
          .where('connectedUserId', '==', userId)
          .where('status', '==', 'accepted')
          .get();
          
        isConnected = !connection1.empty || !connection2.empty;
      }
      
      if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
        return res.status(403).json({
          success: false,
          message: 'Not authorized to view comments for this place'
        });
      }
    }
    
    // Comments are keyed by the canonical venue record, shared by every copy
    console.log('📋 Fetching top-level comments for global place of:', placeId);
    const { globalPlaceId } = await getGlobalSocial(placeDoc);
    const commentsSnapshot = globalPlaceId
      ? await db.collection('placeComments').where('globalPlaceId', '==', globalPlaceId).get()
      : await db.collection('placeComments').where('placeId', '==', placeId).get();
    const commentDocs = [...commentsSnapshot.docs];
    commentDocs.sort((a, b) => String(b.data().createdAt || '').localeCompare(String(a.data().createdAt || '')));

    console.log(`✅ Found ${commentDocs.length} comments for place ${placeId}`);

    // Blocked authors (either direction) and moderation-hidden comments are
    // invisible to this viewer
    const viewerDocForComments = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const { excludedUserIds: excludedForComments } = require('../../services/moderationService');
    const commentExcluded = excludedForComments(viewerDocForComments.exists ? viewerDocForComments.data() : {});

    const comments = [];
    for (const doc of commentDocs) {
      const comment = serializeDoc(doc);
      if (commentExcluded.has(comment.userId)) continue;
      if (comment.moderationStatus === 'under_review' || comment.moderationStatus === 'removed') continue;

      // Only include top-level comments (no parentCommentId or parentCommentId is null/undefined)
      if (!comment.parentCommentId) {
        // Get user details
        const userDoc = await db.collection(COLLECTIONS.USERS).doc(comment.userId).get();
        if (userDoc.exists) {
          comment.user = projectPublicUser(serializeDoc(userDoc));
        }
        
        // Ensure replyCount is included (default to 0 if not present)
        if (comment.replyCount === undefined || comment.replyCount === null) {
          comment.replyCount = 0;
        }
        
        comments.push(comment);
      }
    }
    
    // Owner badge: comments written by the venue's verified owner render as
    // the store speaking (one venue lookup per request)
    try {
      const placeData = placeDoc.data();
      const venue = await rewardService.findVenueByPlace(
        globalPlaceId || placeId, placeData.googlePlaceId || null);
      if (venue && (venue.ownerUserId || (venue.managerUserIds || []).length)) {
        const team = [venue.ownerUserId, ...(venue.managerUserIds || [])].filter(Boolean);
        comments.forEach((c) => {
          if (team.some((id) => isSameUser(c.userId, id))) c.isVenueOwner = true;
        });
      }
    } catch (badgeError) {
      console.error('⚠️ Owner-badge decoration failed (non-fatal):', badgeError.message);
    }

    console.log(`📤 Returning ${comments.length} comments with user details`);
    res.status(200).json({
      success: true,
      comments: comments
    });

  } catch (error) {
    console.error('Error getting place comments:', error);
    next(error);
  }
};

// @desc    Add comment to a place
// @route   POST /api/places/:id/comments
// @access  Private
exports.addPlaceComment = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    const { text } = req.body;
    
    console.log('💬 addPlaceComment called:', {
      placeId,
      userId,
      text: text?.substring(0, 50) + (text?.length > 50 ? '...' : ''),
      timestamp: new Date().toISOString()
    });
    
    if (!text || text.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'Comment text is required'
      });
    }
    
    // Get the place to check permissions
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check permissions (same as likePlace)
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    const circle = serializeDoc(circleDoc);
    
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to comment on this place'
      });
    }
    
    // Create comment using the model function. Comments are keyed by the
    // canonical venue record (placeId kept for legacy readers like the digest)
    const { createPlaceComment } = require('../../models/FirestoreModels');
    const commentGlobalPlaceId = place.globalPlaceId || await ensureGlobalPlaceLink(placeDoc);
    const commentData = {
      ...createPlaceComment({
        placeId: placeId,
        userId: userId,
        text: text.trim()
      }),
      globalPlaceId: commentGlobalPlaceId || null
    };

    console.log('💾 Saving comment to placeComments collection');
    const commentRef = await db.collection('placeComments').add(commentData);

    // Keep the venue's comment counter current
    if (commentGlobalPlaceId) {
      await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(commentGlobalPlaceId).update({
        commentsCount: admin.firestore.FieldValue.increment(1)
      }).catch(err => console.error('⚠️ Failed to bump commentsCount:', err.message));
    }
    const commentDoc = await commentRef.get();
    const comment = serializeDoc(commentDoc);
    console.log('✅ Comment saved successfully with ID:', comment.id);

    // Piggy bank: 1 FavCoin for your first comment on this venue (not your
    // own places; thread-padding pays nothing — per-venue dedup). Awaited so
    // the response carries the credit for the coin-drop; credit() never throws.
    let piggyBank = null;
    if (place.addedBy !== userId) {
      piggyBank = await piggyBankService.credit({
        userId,
        eventType: 'place_comment',
        sourceRef: {
          commentId: commentRef.id,
          globalPlaceId: commentGlobalPlaceId || null,
          placeId
        }
      });
    }
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      comment.user = projectPublicUser(serializeDoc(userDoc));
    }
    
    // Send notification to place owner if it's not the commenter
    if (place.addedBy !== userId) {
      await notificationService.sendPlaceCommentNotification(
        place.addedBy,
        userId,
        placeId,
        place.name,
        text.trim()
      );
    }
    
    res.status(201).json({
      success: true,
      data: comment,
      piggyBank
    });
    
    // Track comment activity
    const { createActivity } = require('../activityController');
    await createActivity(
      'place_commented',
      userId,
      'place',
      placeId,
      place.name || 'Unknown Place',
      {
        circleId: place.circleId,
        circleName: circle.name || 'Unknown Circle',
        comment: text.trim(),
        commentId: commentRef.id,
        placePhoto: place.photos && place.photos.length > 0 ? place.photos[0] : null,
        placeAddress: place.address || null
      }
    );
    
  } catch (error) {
    console.error('Error adding place comment:', error);
    next(error);
  }
};

// @desc    Delete a comment from a place
// @route   DELETE /api/places/:placeId/comments/:commentId
// @access  Private (comment owner or place owner)
exports.deletePlaceComment = async (req, res, next) => {
  try {
    const { placeId, commentId } = req.params;
    const userId = req.user.uid;
    
    // Get the comment
    const commentRef = db.collection('placeComments').doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = serializeDoc(commentDoc);

    // Get the place to check ownership
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();

    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Comments are global per venue: the comment belongs here if it was made
    // on this copy OR on any copy of the same venue
    const sameVenue = comment.globalPlaceId && place.globalPlaceId &&
      comment.globalPlaceId === place.globalPlaceId;
    if (comment.placeId !== placeId && !sameVenue) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this place'
      });
    }

    // Check if user can delete the comment
    // User can delete if they are:
    // 1. The comment author
    // 2. The place owner
    const isCommentAuthor = comment.userId === userId;
    const isPlaceOwner = place.addedBy === userId;

    if (!isCommentAuthor && !isPlaceOwner) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this comment'
      });
    }

    // Delete the comment
    await commentRef.delete();

    // Keep the venue's comment counter current
    const counterGlobalId = comment.globalPlaceId || place.globalPlaceId;
    if (counterGlobalId) {
      await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(counterGlobalId).update({
        commentsCount: admin.firestore.FieldValue.increment(-1)
      }).catch(err => console.error('⚠️ Failed to decrement commentsCount:', err.message));
    }

    // A deleted comment must not live on in the home feed: remove the
    // place_commented activity addPlaceComment created for it. New activities
    // carry metadata.commentId; older ones are matched by comment text.
    try {
      const activityHits = await db.collection('activities')
        .where('type', '==', 'place_commented')
        .where('actorId', '==', String(comment.userId))
        .where('targetId', '==', comment.placeId)
        .get();
      const byId = activityHits.docs.filter((doc) => doc.data().metadata?.commentId === commentId);
      const matches = byId.length > 0
        ? byId
        : activityHits.docs.filter((doc) =>
            !doc.data().metadata?.commentId &&
            (doc.data().metadata?.comment || null) === (comment.text || null));
      await Promise.all(matches.map((doc) => doc.ref.delete()));
      if (matches.length > 0) {
        console.log(`🧹 Removed ${matches.length} place_commented activity for deleted comment ${commentId}`);
      }
    } catch (activityError) {
      console.error('⚠️ Failed to remove place_commented activity:', activityError.message);
    }
    
    res.status(200).json({
      success: true,
      message: 'Comment deleted successfully'
    });
    
  } catch (error) {
    console.error('Error deleting place comment:', error);
    next(error);
  }
};

// @desc    Like or unlike a comment
// @route   POST /api/places/:placeId/comments/:commentId/like
// @access  Private
exports.likeComment = async (req, res, next) => {
  try {
    const { placeId, commentId } = req.params;
    const userId = req.user.uid;
    
    // Get the comment
    const commentRef = db.collection('placeComments').doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = serializeDoc(commentDoc);

    // Get the place to check permissions
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();

    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Comments are global per venue: the comment belongs here if it was made
    // on this copy OR on any copy of the same venue
    const likeSameVenue = comment.globalPlaceId && place.globalPlaceId &&
      comment.globalPlaceId === place.globalPlaceId;
    if (comment.placeId !== placeId && !likeSameVenue) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this place'
      });
    }

    // Check permissions (same as viewing place)
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    const circle = serializeDoc(circleDoc);
    
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !isConnected) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to like comments on this place'
      });
    }
    
    // Toggle like
    const currentLikes = comment.likes || [];
    const alreadyLiked = currentLikes.includes(userId);
    
    let updatedLikes;
    let updatedLikesCount;
    
    if (alreadyLiked) {
      // Unlike - remove user from likes array
      updatedLikes = currentLikes.filter(id => id !== userId);
      updatedLikesCount = Math.max(0, (comment.likesCount || 0) - 1);
    } else {
      // Like - add user to likes array
      updatedLikes = [...currentLikes, userId];
      updatedLikesCount = (comment.likesCount || 0) + 1;
    }
    
    // Update comment
    await commentRef.update({
      likes: updatedLikes,
      likesCount: updatedLikesCount,
      updatedAt: new Date().toISOString()
    });
    
    // Track activity if liking (not unliking). Unlike/re-like cycles used to
    // mint a NEW activity every time (and unliking left the old one) — the
    // feed showed "liked a comment" rows two and three deep for one comment.
    const existingActivity = await db.collection('activities')
      .where('type', '==', 'comment_liked')
      .where('actorId', '==', userId)
      .where('targetId', '==', commentId)
      .get();
    if (alreadyLiked) {
      // Unliking: retire the activity row(s)
      for (const doc of existingActivity.docs) {
        await doc.ref.delete().catch(() => {});
      }
    }
    if (!alreadyLiked && existingActivity.empty) {
      const { createActivity } = require('../activityController');
      await createActivity(
        'comment_liked',
        userId,
        'comment',
        commentId,
        // Plain place name: iOS renders "liked a comment on <targetName>",
        // so "Comment on X" here doubled into "a comment on Comment on X"
        place.name,
        {
          placeId: placeId,
          placeName: place.name,
          circleId: place.circleId,
          circleName: circle.name || 'Unknown Circle',
          commentText: comment.text,
          commentAuthorId: comment.userId
        }
      );
    }
    
    // Piggy bank: a nickel for hearting a comment — not your own, one per
    // comment ever (dedup key), unlike/relike can't re-mint. Awaited so the
    // response carries the credit and the app can play the deposit animation.
    let piggyBank = null;
    if (!alreadyLiked && comment.userId !== userId) {
      piggyBank = await require('../../services/piggyBankService').credit({
        userId,
        eventType: 'comment_liked',
        sourceRef: { commentId }
      });
    }

    res.status(200).json({
      success: true,
      liked: !alreadyLiked,
      likesCount: updatedLikesCount,
      piggyBank
    });
    
  } catch (error) {
    console.error('Error liking/unliking comment:', error);
    next(error);
  }
};

// @desc    Add reply to a place comment
// @route   POST /api/places/:id/comments/:commentId/replies
// @access  Private
exports.addPlaceCommentReply = async (req, res, next) => {
  try {
    const { id: placeId, commentId } = req.params;
    const userId = req.user.uid;
    const { text } = req.body;
    
    console.log('💬 addPlaceCommentReply called:', {
      placeId,
      commentId,
      userId,
      text: text?.substring(0, 50) + (text?.length > 50 ? '...' : ''),
      timestamp: new Date().toISOString()
    });
    
    if (!text || text.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'Reply text is required'
      });
    }
    
    // Get the parent comment to validate it exists
    const parentCommentRef = db.collection('placeComments').doc(commentId);
    const parentCommentDoc = await parentCommentRef.get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = serializeDoc(parentCommentDoc);

    // Get the place to check permissions
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();

    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Comments are global per venue: the parent belongs here if it was made
    // on this copy OR on any copy of the same venue
    const parentSameVenue = parentComment.globalPlaceId && place.globalPlaceId &&
      parentComment.globalPlaceId === place.globalPlaceId;
    if (parentComment.placeId !== placeId && !parentSameVenue) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this place'
      });
    }
    
    // Check if user can reply to comments on this place (same permissions as commenting)
    // Get the circle to check permissions
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Check permissions
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    // Check if users are connected for myNetwork privacy
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to reply to comments on this place'
      });
    }
    
    // Create reply data using the new model function. Replies inherit the
    // parent's venue key so they surface on every copy of the place
    const { createPlaceComment } = require('../../models/FirestoreModels');
    const replyGlobalPlaceId = parentComment.globalPlaceId || place.globalPlaceId || null;
    const replyData = {
      ...createPlaceComment({
        placeId: placeId,
        userId: userId,
        text: text.trim(),
        parentCommentId: commentId
      }),
      globalPlaceId: replyGlobalPlaceId
    };

    console.log('💾 Saving reply to placeComments collection');
    const replyRef = await db.collection('placeComments').add(replyData);

    // Keep the venue's comment counter current (counts include replies)
    if (replyGlobalPlaceId) {
      await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(replyGlobalPlaceId).update({
        commentsCount: admin.firestore.FieldValue.increment(1)
      }).catch(err => console.error('⚠️ Failed to bump commentsCount:', err.message));
    }
    const replyDoc = await replyRef.get();
    const reply = serializeDoc(replyDoc);
    console.log('✅ Reply saved successfully with ID:', reply.id);
    
    // Get user details for the reply
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      reply.user = projectPublicUser(serializeDoc(userDoc));
    }
    
    // Update parent comment reply count
    const currentReplyCount = parentComment.replyCount || 0;
    await parentCommentRef.update({
      replyCount: currentReplyCount + 1
    });
    
    console.log('✅ Parent comment reply count updated');
    
    res.status(201).json({
      success: true,
      data: reply
    });
    
  } catch (error) {
    console.error('Error adding place comment reply:', error);
    next(error);
  }
};

// @desc    Get replies for a place comment
// @route   GET /api/places/:id/comments/:commentId/replies
// @access  Private
exports.getPlaceCommentReplies = async (req, res, next) => {
  try {
    const { id: placeId, commentId } = req.params;
    const userId = req.user.uid;
    
    console.log('🔍 getPlaceCommentReplies called:', {
      placeId,
      commentId,
      userId,
      timestamp: new Date().toISOString()
    });
    
    // Verify parent comment exists and belongs to the place
    const parentCommentRef = db.collection('placeComments').doc(commentId);
    const parentCommentDoc = await parentCommentRef.get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = serializeDoc(parentCommentDoc);

    // Get the place to check permissions
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();

    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Comments are global per venue: the parent belongs here if it was made
    // on this copy OR on any copy of the same venue
    const repliesSameVenue = parentComment.globalPlaceId && place.globalPlaceId &&
      parentComment.globalPlaceId === place.globalPlaceId;
    if (parentComment.placeId !== placeId && !repliesSameVenue) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this place'
      });
    }

    // Check if user can view replies (same permissions as viewing comments)
    // Get the circle to check permissions
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Check permissions
    const isOwner = circle.owner === userId;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
    const isPublic = circle.privacy === 'public';
    
    // Check if users are connected for myNetwork privacy
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view replies on this place'
      });
    }
    
    // Get replies for this comment
    const repliesSnapshot = await db.collection('placeComments')
      .where('parentCommentId', '==', commentId)
      .orderBy('createdAt', 'asc') // Replies should be chronological
      .get();
    
    const replies = [];
    for (const replyDoc of repliesSnapshot.docs) {
      const reply = serializeDoc(replyDoc);
      
      // Get user details for each reply
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(reply.userId).get();
      if (userDoc.exists) {
        reply.user = serializeDoc(userDoc);
      }
      
      replies.push(reply);
    }
    
    console.log(`✅ Found ${replies.length} replies for comment ${commentId}`);

    // Log details of replies for debugging
    replies.forEach((reply, index) => {
      console.log(`  Reply ${index + 1}: id=${reply.id}, userId=${reply.userId}, text="${reply.text?.substring(0, 50)}..."`);
    });

    // Owner badge, mirroring getPlaceComments — replies inherit the parent's
    // globalPlaceId, so resolve the venue from the first reply
    try {
      if (replies.length > 0) {
        const venue = await rewardService.findVenueByPlace(
          replies[0].globalPlaceId || req.params.id, null);
        if (venue && (venue.ownerUserId || (venue.managerUserIds || []).length)) {
          const team = [venue.ownerUserId, ...(venue.managerUserIds || [])].filter(Boolean);
          replies.forEach((r) => {
            if (team.some((id) => isSameUser(r.userId, id))) r.isVenueOwner = true;
          });
        }
      }
    } catch (badgeError) {
      console.error('⚠️ Owner-badge decoration failed (non-fatal):', badgeError.message);
    }

    res.status(200).json({
      success: true,
      comments: replies
    });
    
  } catch (error) {
    console.error('Error getting place comment replies:', error);
    next(error);
  }
};

// @desc    Track when a user views a place
// @route   POST /api/places/:id/track-view
// @access  Private
exports.trackPlaceView = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const viewerUserId = req.user.firebaseDocId || req.user.uid;
    const { connectionUserId } = req.body;
    
    if (!connectionUserId) {
      return res.status(400).json({
        success: false,
        message: 'Connection user ID is required'
      });
    }
    
    // Track the view in activity service
    await trackPlaceView(viewerUserId, placeId, connectionUserId);
    
    res.status(200).json({
      success: true,
      message: 'Place view tracked'
    });
  } catch (error) {
    console.error('Error tracking place view:', error);
    next(error);
  }
};
