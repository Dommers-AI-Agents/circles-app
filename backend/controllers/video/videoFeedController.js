// controllers/video/videoFeedController.js
// Moment reads: place/user/network feeds, reels, detail and public detail
// Split out of videoController.js (handlers unchanged).
// backend/controllers/videoController.js
const { getFirestore, FieldValue } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../../models/FirestoreModels');
const { queryInChunks } = require('../../utils/firestoreChunks');
const db = getFirestore();

// Get videos for a place
exports.getPlaceVideos = async (req, res) => {
  try {
    const { placeId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    const videosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('placeId', '==', placeId)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    const videos = serializeQuerySnapshot(videosQuery);
    
    res.json({
      success: true,
      data: videos,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting place videos:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get place videos',
      error: error.message
    });
  }
};

// Get user's videos
exports.getUserVideos = async (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    const videosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('userId', '==', userId)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    const videos = serializeQuerySnapshot(videosQuery);
    
    // Populate user details
    const userIds = [...new Set(videos.map(v => v.userId))];
    const userDocs = await Promise.all(
      userIds.map(id => db.collection(COLLECTIONS.USERS).doc(id).get())
    );
    
    const usersMap = {};
    userDocs.forEach(doc => {
      if (doc.exists) {
        const userData = doc.data();
        usersMap[doc.id] = {
          id: doc.id,
          displayName: userData.displayName,
          username: userData.username,
          profilePicture: userData.profilePicture,
          bio: userData.bio
        };
      }
    });
    
    // Add user details to videos
    const videosWithUsers = videos.map(video => ({
      ...video,
      user: usersMap[video.userId] || null
    }));
    
    res.json({
      success: true,
      data: videosWithUsers,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting user videos:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get user videos',
      error: error.message
    });
  }
};

// Get video feed
exports.getVideoFeed = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { limit = 20, offset = 0 } = req.query;
    
    // Get user's connections
    const [connections1, connections2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const connectionIds = new Set([userId]); // Include self
    connections1.docs.forEach(doc => connectionIds.add(doc.data().connectedUserId));
    connections2.docs.forEach(doc => connectionIds.add(doc.data().userId));
    
    // Get videos from connections. Chunked over the connection set — 'in'
    // caps at 30 values and broke past 30 connections. Each chunk is fetched
    // sorted; merge, re-sort, and window to keep limit/offset semantics.
    const pageLimit = parseInt(limit);
    const pageOffset = parseInt(offset);
    const videoDocs = await queryInChunks(connectionIds, chunk =>
      db.collection(COLLECTIONS.PLACE_VIDEOS)
        .where('userId', 'in', chunk)
        .where('uploadStatus', '==', 'ready')
        .where('deletedAt', '==', null)
        .where('visibility', 'in', ['public', 'network'])
        .orderBy('createdAt', 'desc')
        .limit(pageLimit + pageOffset)
        .get()
    );
    videoDocs.sort((a, b) => String(b.data().createdAt).localeCompare(String(a.data().createdAt)));

    const videos = videoDocs.slice(pageOffset, pageOffset + pageLimit)
      .map(doc => serializeDoc(doc))
      .filter(doc => doc !== null);
    
    // Populate user details
    const userIds = [...new Set(videos.map(v => v.userId))];
    const userDocs = await Promise.all(
      userIds.map(id => db.collection(COLLECTIONS.USERS).doc(id).get())
    );
    
    const usersMap = {};
    userDocs.forEach(doc => {
      if (doc.exists) {
        usersMap[doc.id] = doc.data();
      }
    });
    
    // Add user details to videos
    const videosWithUsers = videos.map(video => ({
      ...video,
      user: usersMap[video.userId] || null
    }));
    
    res.json({
      success: true,
      data: videosWithUsers,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting video feed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video feed',
      error: error.message
    });
  }
};

// Get video details (and track view)
// Build a human, actionable access-denied payload for a gated moment. The
// message tells the viewer exactly what to do; the structured fields let the
// client offer a "Send request"/"Follow" affordance.
function momentAccessDenied(visibility, ownerName, ownerId) {
  const name = ownerName || 'this person';
  if (visibility === 'network') {
    return {
      reason: 'not_connected',
      action: 'connect',
      ownerId,
      ownerName: ownerName || null,
      message: `You're not connected to ${name}. Send them a connection request to view this moment.`
    };
  }
  if (visibility === 'followers') {
    return {
      reason: 'not_following',
      action: 'follow',
      ownerId,
      ownerName: ownerName || null,
      message: `This moment is for ${name}'s followers. Follow ${name} to view it.`
    };
  }
  return {
    reason: 'private',
    action: null,
    ownerId,
    ownerName: ownerName || null,
    message: 'This moment is private.'
  };
}

exports.getVideoDetails = async (req, res) => {
  try {
    const { videoId } = req.params;
    const { quality = 'preview' } = req.query; // preview or full
    const userId = req.user?.uid;

    // Guard against an empty/whitespace id reaching Firestore's .doc(), which
    // throws a raw "documentPath must be a non-empty string" 500. Treat a
    // missing id as a not-found request instead.
    if (!videoId || typeof videoId !== 'string' || videoId.trim() === '') {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }

    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const videoData = videoDoc.data();

    // Visibility check based on the viewer's relationship to the owner.
    // (Previously only 'private' was blocked, so network/followers moments were
    // viewable by anyone holding the id.)
    // Moderation-hidden content: gone for everyone but the owner
    if ((videoData.moderationStatus === 'under_review' || videoData.moderationStatus === 'removed')
        && videoData.userId !== userId) {
      return res.status(404).json({ success: false, message: 'Video not found' });
    }

    if (videoData.userId !== userId) {
      const owner = videoData.userId;

      // A block in either direction makes the content unavailable
      if (userId) {
        const viewerDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
        const { isBlockedEitherWay } = require('../../services/moderationService');
        if (viewerDoc.exists && isBlockedEitherWay(viewerDoc.data(), owner)) {
          return res.status(404).json({ success: false, message: 'Video not found' });
        }
      }

      const visibility = videoData.visibility || 'private';
      let allowed = visibility === 'public';
      // A relationship-gated moment needs a known viewer. Without one (no auth)
      // only public moments are visible — the checks below simply don't run.
      if (!allowed && userId) {
        if (visibility === 'network') {
          const [c1, c2] = await Promise.all([
            db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', userId).where('connectedUserId', '==', owner).where('status', '==', 'accepted').get(),
            db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', owner).where('connectedUserId', '==', userId).where('status', '==', 'accepted').get()
          ]);
          allowed = !c1.empty || !c2.empty;
        } else if (visibility === 'followers') {
          const meDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
          allowed = (meDoc.exists ? (meDoc.data().following || []) : []).includes(owner);
        }
      }
      // Not allowed → return a friendly, actionable message naming the owner.
      if (!allowed) {
        let ownerName = null;
        try {
          const ownerDoc = await db.collection(COLLECTIONS.USERS).doc(owner).get();
          if (ownerDoc.exists) ownerName = ownerDoc.data().displayName || null;
        } catch (_) { /* name is best-effort */ }
        return res.status(403).json({
          success: false,
          ...momentAccessDenied(visibility, ownerName, owner)
        });
      }
    }
    
    // Update view count and last viewed
    if (userId && userId !== videoData.userId) {
      await videoRef.update({
        viewCount: FieldValue.increment(1),
        lastViewedAt: new Date().toISOString()
      });
    }
    
    // Return all URLs correctly without overwriting
    // The iOS app expects both videoUrl and previewUrl to be present
    const response = {
      ...serializeDoc(videoDoc)
      // Don't override videoUrl - keep both URLs intact
    };
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(videoData.userId).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      // Add _id field for iOS compatibility
      response.user = {
        _id: userDoc.id,
        ...userData
      };
    }
    
    // Check if current user has liked this video
    if (userId) {
      const likeDoc = await db.collection(COLLECTIONS.VIDEO_LIKES)
        .doc(`${userId}_${videoId}`)
        .get();
      response.likedByCurrentUser = likeDoc.exists;
    }
    
    res.json({
      success: true,
      data: response
    });
  } catch (error) {
    console.error('Error getting video details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video details',
      error: error.message
    });
  }
};

// MARK: - Reels Specific Endpoints

// Helper function to fetch activity data for videos
const fetchActivityDataForVideos = async (videos, userId) => {
  const videoIds = videos.map(v => v.id);
  if (videoIds.length === 0) return {};
  
  // Fetch activities for these videos
  const activitiesQuery = await db.collection(COLLECTIONS.ACTIVITIES)
    .where('targetType', '==', 'place_video')
    .where('targetId', 'in', videoIds.slice(0, 10)) // Firestore 'in' limit
    .get();
  
  const activitiesMap = {};
  activitiesQuery.docs.forEach(doc => {
    const activity = serializeDoc(doc);
    activitiesMap[activity.targetId] = activity;
  });
  
  // Fetch remaining activities if more than 10 videos
  if (videoIds.length > 10) {
    const remainingActivitiesQuery = await db.collection(COLLECTIONS.ACTIVITIES)
      .where('targetType', '==', 'place_video')
      .where('targetId', 'in', videoIds.slice(10))
      .get();
    
    remainingActivitiesQuery.docs.forEach(doc => {
      const activity = serializeDoc(doc);
      activitiesMap[activity.targetId] = activity;
    });
  }
  
  // Check user reactions
  const activityIds = Object.values(activitiesMap).map(a => a.id);
  if (activityIds.length > 0) {
    const reactionsQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', 'in', activityIds.slice(0, 10))
      .where('userId', '==', userId)
      .get();
    
    const userReactions = {};
    reactionsQuery.docs.forEach(doc => {
      const reaction = doc.data();
      userReactions[reaction.activityId] = reaction.emoji;
    });
    
    // Add user reaction to activities
    Object.values(activitiesMap).forEach(activity => {
      activity.userReaction = userReactions[activity.id] || null;
    });
  }
  
  return activitiesMap;
};

// Get reels feed with algorithm
exports.getReelsFeed = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { limit = 20, offset = 0 } = req.query;
    
    // Get user's connections and following list
    const [connections1, connections2, userDoc] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.USERS).doc(userId).get()
    ]);
    
    // Separate connections from following for proper visibility filtering
    const connectionIds = new Set([userId]);
    connections1.docs.forEach(doc => connectionIds.add(doc.data().connectedUserId));
    connections2.docs.forEach(doc => connectionIds.add(doc.data().userId));
    
    const following = userDoc.data()?.following || [];
    const followingIds = new Set(following);
    
    // Combine for user content discovery
    const allUserIds = new Set([...connectionIds, ...followingIds]);
    
    // A viewer may see a moment by its visibility + their relationship to the
    // owner: public (anyone in their graph), network/"Connections" (accepted
    // connections only), followers (people who follow the owner), private (self).
    const canView = (v) => {
      if (v.userId === userId) return true;
      switch (v.visibility) {
        case 'public': return true;
        case 'network': return connectionIds.has(v.userId);
        case 'followers': return followingIds.has(v.userId);
        case 'private': return false;
        default: return v.visibility === 'public';
      }
    };

    // Fetch recent ready moments from everyone in the viewer's graph, batched for
    // Firestore's 30-value IN limit. Visibility is filtered in JS (Firestore
    // allows only one IN per query, so userId-IN can't be combined with a
    // visibility filter) — over-fetch a little to cover filtered-out items.
    const graphIds = Array.from(allUserIds);
    const idBatches = [];
    for (let i = 0; i < graphIds.length; i += 30) idBatches.push(graphIds.slice(i, i + 30));
    const need = parseInt(offset) + parseInt(limit);

    const snaps = graphIds.length > 0 ? await Promise.all(idBatches.map(batch =>
      db.collection(COLLECTIONS.PLACE_VIDEOS)
        .where('userId', 'in', batch)
        .where('uploadStatus', '==', 'ready')
        .where('deletedAt', '==', null)
        .orderBy('createdAt', 'desc')
        .limit(need + 20)
        .get()
    )) : [];

    // Blocked users vanish in both directions, and reported content that hit
    // the auto-hide threshold ('under_review'/'removed') never surfaces.
    const { excludedUserIds } = require('../../services/moderationService');
    const excluded = excludedUserIds(userDoc.data() || {});

    const seenVideoIds = new Set();
    const videos = [];
    snaps.flatMap(s => s.docs).forEach(doc => {
      if (seenVideoIds.has(doc.id)) return;
      const v = serializeDoc(doc);
      if (excluded.has(v.userId)) return;
      if (v.moderationStatus === 'under_review' || v.moderationStatus === 'removed') return;
      if (!canView(v)) return;
      seenVideoIds.add(doc.id);
      videos.push(v);
    });
    videos.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    // Apply pagination
    const paginatedVideos = videos.slice(parseInt(offset), parseInt(offset) + parseInt(limit));
    
    // Populate user details
    const userIds = [...new Set(paginatedVideos.map(v => v.userId))];
    const userDocs = await Promise.all(
      userIds.map(id => db.collection(COLLECTIONS.USERS).doc(id).get())
    );
    
    // Viewer's follow state rides along so the reel cell can render
    // Follow vs already-following without a second request
    const viewerFollowing = new Set((userDoc.data() || {}).following || []);
    const usersMap = {};
    userDocs.forEach(doc => {
      if (doc.exists) {
        const userData = doc.data();
        usersMap[doc.id] = {
          id: doc.id,
          displayName: userData.displayName,
          profilePicture: userData.profilePicture,
          isVerified: userData.isVerified || false,
          isFollowing: viewerFollowing.has(doc.id)
        };
      }
    });
    
    // Check which videos are liked by current user
    const videoIds = paginatedVideos.map(v => v.id);
    const likesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
      .where('userId', '==', userId)
      .where('videoId', 'in', videoIds.slice(0, 10)) // Firestore 'in' limit
      .get();
    
    const likedVideoIds = new Set();
    likesQuery.docs.forEach(doc => {
      const [_, videoId] = doc.id.split('_');
      likedVideoIds.add(videoId);
    });
    
    // Check remaining videos if more than 10
    if (videoIds.length > 10) {
      const remainingLikesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
        .where('userId', '==', userId)
        .where('videoId', 'in', videoIds.slice(10))
        .get();
      
      remainingLikesQuery.docs.forEach(doc => {
        const [_, videoId] = doc.id.split('_');
        likedVideoIds.add(videoId);
      });
    }
    
    // Fetch activity data for videos
    const activitiesMap = await fetchActivityDataForVideos(paginatedVideos, userId);
    
    // Add user details, like status, and activity data to videos
    const videosWithUsers = paginatedVideos.map(video => {
      const activity = activitiesMap[video.id];
      return {
        ...video,
        user: usersMap[video.userId] || null,
        likedByCurrentUser: likedVideoIds.has(video.id),
        activityId: activity?.id || null,
        activityReactionCount: activity?.reactionCount || 0,
        activityCommentCount: activity?.commentCount || 0,
        userActivityReaction: activity?.userReaction || null
      };
    });
    
    res.json({
      success: true,
      data: videosWithUsers,
      hasMore: videos.length > parseInt(offset) + parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting reels feed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get reels feed',
      error: error.message
    });
  }
};

// Get user's reels
exports.getUserReels = async (req, res) => {
  try {
    const currentUserId = req.user.uid;
    const { userId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    // Check relationship with target user
    let visibilityFilter = ['public']; // Default: only public content
    
    if (currentUserId === userId) {
      // User viewing their own content - show all
      visibilityFilter = ['public', 'followers', 'network', 'private'];
    } else {
      // Build the filter from BOTH relationships: connections can see 'network',
      // people who follow the owner can see 'followers'. They're independent
      // audiences, so a viewer may qualify for either, both, or neither.
      const [connection1, connection2, currentUserDoc] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', currentUserId)
          .where('connectedUserId', '==', userId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', userId)
          .where('connectedUserId', '==', currentUserId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.USERS).doc(currentUserId).get()
      ]);

      const isConnected = !connection1.empty || !connection2.empty;
      const isFollowing = (currentUserDoc.exists ? (currentUserDoc.data().following || []) : []).includes(userId);

      // A block in either direction empties the shelf entirely
      const { isBlockedEitherWay } = require('../../services/moderationService');
      if (currentUserDoc.exists && isBlockedEitherWay(currentUserDoc.data(), userId)) {
        return res.json({ success: true, data: [], hasMore: false });
      }

      visibilityFilter = ['public'];
      if (isConnected) visibilityFilter.push('network');
      if (isFollowing) visibilityFilter.push('followers');
    }

    const videosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('userId', '==', userId)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .where('visibility', 'in', visibilityFilter)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();

    let videos = serializeQuerySnapshot(videosQuery);
    // Reported-and-hidden moments stay visible ONLY to their owner
    if (currentUserId !== userId) {
      videos = videos.filter(v => v.moderationStatus !== 'under_review' && v.moderationStatus !== 'removed');
    }
    
    // Check which videos are liked by current user
    if (videos.length > 0) {
      const videoIds = videos.map(v => v.id);
      const likesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
        .where('userId', '==', currentUserId)
        .where('videoId', 'in', videoIds.slice(0, 10)) // Firestore 'in' limit
        .get();
      
      const likedVideoIds = new Set();
      likesQuery.docs.forEach(doc => {
        const [_, videoId] = doc.id.split('_');
        likedVideoIds.add(videoId);
      });
      
      // Check remaining videos if more than 10
      if (videoIds.length > 10) {
        const remainingLikesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
          .where('userId', '==', currentUserId)
          .where('videoId', 'in', videoIds.slice(10))
          .get();
        
        remainingLikesQuery.docs.forEach(doc => {
          const [_, videoId] = doc.id.split('_');
          likedVideoIds.add(videoId);
        });
      }
      
      // Add like status to videos
      videos.forEach(video => {
        video.likedByCurrentUser = likedVideoIds.has(video.id);
      });
    }
    
    // Fetch activity data for videos
    const activitiesMap = await fetchActivityDataForVideos(videos, currentUserId);
    
    // Add activity data to videos
    const videosWithActivity = videos.map(video => {
      const activity = activitiesMap[video.id];
      return {
        ...video,
        activityId: activity?.id || null,
        activityReactionCount: activity?.reactionCount || 0,
        activityCommentCount: activity?.commentCount || 0,
        userActivityReaction: activity?.userReaction || null
      };
    });
    
    res.json({
      success: true,
      data: videosWithActivity,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting user reels:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get user reels',
      error: error.message
    });
  }
};

// Get place's reels
exports.getPlaceReels = async (req, res) => {
  try {
    const currentUserId = req.user.uid;
    const { placeId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    // First get all videos for this place
    const allVideosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('placeId', '==', placeId)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .orderBy('createdAt', 'desc')
      .get();
    
    const allVideos = serializeQuerySnapshot(allVideosQuery);
    
    if (allVideos.length === 0) {
      return res.json({
        success: true,
        data: [],
        hasMore: false
      });
    }
    
    // Get unique user IDs from videos
    const videoUserIds = [...new Set(allVideos.map(v => v.userId))];
    
    // Check relationships with all video creators (chunked — a feed page can
    // reference more than 30 distinct creators)
    const [connection1Docs, connection2Docs, currentUserDoc] = await Promise.all([
      queryInChunks(videoUserIds, chunk =>
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', currentUserId)
          .where('connectedUserId', 'in', chunk)
          .where('status', '==', 'accepted')
          .get()
      ),
      queryInChunks(videoUserIds, chunk =>
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', 'in', chunk)
          .where('connectedUserId', '==', currentUserId)
          .where('status', '==', 'accepted')
          .get()
      ),
      db.collection(COLLECTIONS.USERS).doc(currentUserId).get()
    ]);

    // Build sets of connected and following users
    const connectedUserIds = new Set();
    connection1Docs.forEach(doc => connectedUserIds.add(doc.data().connectedUserId));
    connection2Docs.forEach(doc => connectedUserIds.add(doc.data().userId));
    
    const followingUserIds = new Set();
    if (currentUserDoc.exists) {
      const following = currentUserDoc.data().following || [];
      following.forEach(id => followingUserIds.add(id));
    }
    
    // Blocked either way, or hidden by moderation → never surfaces here
    const { excludedUserIds } = require('../../services/moderationService');
    const excludedIds = excludedUserIds(currentUserDoc.exists ? currentUserDoc.data() : {});

    // Filter videos based on visibility and relationships
    const filteredVideos = allVideos.filter(video => {
      if (excludedIds.has(video.userId)) return false;
      if (video.moderationStatus === 'under_review' || video.moderationStatus === 'removed') {
        return video.userId === currentUserId && video.moderationStatus === 'under_review';
      }
      // User's own videos - always visible
      if (video.userId === currentUserId) return true;

      // Check visibility based on relationship
      const isConnected = connectedUserIds.has(video.userId);
      const isFollowing = followingUserIds.has(video.userId);
      
      if (video.visibility === 'public') {
        return true; // Public videos visible to all
      } else if (video.visibility === 'followers') {
        return isFollowing; // Followers-only: viewer must follow the owner
      } else if (video.visibility === 'network') {
        return isConnected; // Connections-only ("network") visible to connections
      } else if (video.visibility === 'private') {
        return false; // Private videos not visible in place feeds
      }

      return false; // Default deny
    });
    
    // Apply pagination to filtered results
    const paginatedVideos = filteredVideos.slice(parseInt(offset), parseInt(offset) + parseInt(limit));
    
    res.json({
      success: true,
      data: paginatedVideos,
      hasMore: filteredVideos.length > parseInt(offset) + parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting place reels:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get place reels',
      error: error.message
    });
  }
};

// Get public video details (no auth required)
exports.getPublicVideoDetails = async (req, res) => {
  try {
    const { videoId } = req.params;
    
    // Get video document
    const videoDoc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const video = serializeDoc(videoDoc);
    
    // Only return public or non-sensitive information
    const publicVideo = {
      id: video.id,
      title: video.title,
      description: video.description,
      thumbnailUrl: video.thumbnailUrl,
      placeName: video.placeName,
      placeId: video.placeId,
      placeAddress: video.placeAddress,
      userName: video.userName || 'Circles User',
      userPhoto: video.userPhoto,
      createdAt: video.createdAt,
      likeCount: video.likeCount || 0,
      commentCount: video.commentCount || 0,
      viewCount: video.viewCount || 0,
      // Don't include the actual video URL for non-authenticated users
      hasVideo: !!video.videoUrl,
      duration: video.duration
    };
    
    res.json({
      success: true,
      data: publicVideo
    });
  } catch (error) {
    console.error('Error getting public video details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video details',
      error: error.message
    });
  }
};
