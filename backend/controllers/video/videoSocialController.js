// controllers/video/videoSocialController.js
// Moment likes, views, comments and replies
// Split out of videoController.js (handlers unchanged).
// backend/controllers/videoController.js
const { getFirestore, FieldValue, admin } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');
const { queryInChunks } = require('../../utils/firestoreChunks');
const db = getFirestore();
// Like a reel
const sseService = require('../../services/sseService');
const { trackVideoLiked } = require('../../services/activityService');

exports.likeReel = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    
    // Check if already liked
    const likeRef = db.collection(COLLECTIONS.VIDEO_LIKES)
      .doc(`${userId}_${videoId}`);
    
    const likeDoc = await likeRef.get();
    
    if (likeDoc.exists) {
      return res.status(400).json({
        success: false,
        message: 'Already liked this video'
      });
    }
    
    // Add like
    await likeRef.set({
      userId,
      videoId,
      timestamp: new Date().toISOString()
    });
    
    // Update video like count
    await videoRef.update({
      likeCount: FieldValue.increment(1)
    });
    
    // Get video details and track comprehensive activity
    let likePiggyBank = null;
    const videoDoc = await videoRef.get();
    if (videoDoc.exists) {
      const videoData = videoDoc.data();

      // FavCoins: the liker earns a nickel; the moment's owner earns one too
      // (received engagement). Self-likes pay NOBODY. The liker's credit is
      // awaited so the response can drive the coin-drop (credit() never
      // throws); the owner's stays fire-and-forget — they're not on this call.
      if (videoData.userId && videoData.userId !== userId) {
        const piggyBankService = require('../../services/piggyBankService');
        likePiggyBank = await piggyBankService.credit({
          userId,
          eventType: 'moment_liked',
          sourceRef: { videoId }
        });
        piggyBankService.credit({
          userId: videoData.userId,
          eventType: 'moment_like_received',
          sourceRef: { videoId, likerUserId: userId }
        }).catch(() => {});
      }

      // Get place information for activity tracking
      let placeName = 'Unknown Place';
      if (videoData.placeId) {
        try {
          const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(videoData.placeId).get();
          if (placeDoc.exists) {
            placeName = placeDoc.data().name || 'Unknown Place';
          }
        } catch (placeError) {
          console.warn('Could not fetch place name for video like tracking:', placeError);
        }
      }
      
      // Use comprehensive activity tracking (includes connection notifications)
      if (videoData.userId && videoData.userId !== userId) {
        await trackVideoLiked(
          videoId,
          videoData.placeId || null,
          placeName,
          userId,
          videoData.userId
        );
      }
      
      // Still broadcast engagement for real-time UI updates
      sseService.broadcastVideoEngagement(videoId, 'like', {
        userId,
        videoId,
        type: 'like',
        timestamp: new Date().toISOString()
      });
    }
    
    res.json({
      success: true,
      message: 'Video liked successfully',
      piggyBank: likePiggyBank
    });
  } catch (error) {
    console.error('Error liking reel:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to like video',
      error: error.message
    });
  }
};

// Unlike a reel
exports.unlikeReel = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const likeRef = db.collection(COLLECTIONS.VIDEO_LIKES)
      .doc(`${userId}_${videoId}`);
    
    const likeDoc = await likeRef.get();
    
    if (!likeDoc.exists) {
      return res.status(400).json({
        success: false,
        message: 'Video not liked'
      });
    }
    
    // Remove like
    await likeRef.delete();
    
    // Update video like count
    await videoRef.update({
      likeCount: FieldValue.increment(-1)
    });
    
    // Get video details for SSE notification
    const videoDoc = await videoRef.get();
    if (videoDoc.exists) {
      const videoData = videoDoc.data();
      
      // Broadcast to all users viewing this video
      sseService.broadcastVideoEngagement(videoId, 'unlike', {
        userId,
        videoId,
        type: 'unlike',
        timestamp: new Date().toISOString()
      });
    }
    
    res.json({
      success: true,
      message: 'Video unliked successfully'
    });
  } catch (error) {
    console.error('Error unliking reel:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to unlike video',
      error: error.message
    });
  }
};

// Track reel view
exports.trackReelView = async (req, res) => {
  try {
    const userId = req.user?.uid;
    const { videoId } = req.params;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    
    // Update view count and last viewed
    const updates = {
      viewCount: FieldValue.increment(1),
      lastViewedAt: new Date().toISOString()
    };
    
    await videoRef.update(updates);
    
    // Track individual view if user is logged in
    if (userId) {
      const viewRef = db.collection(COLLECTIONS.VIDEO_VIEWS)
        .doc(`${userId}_${videoId}_${Date.now()}`);
      
      await viewRef.set({
        userId,
        videoId,
        viewedAt: new Date().toISOString()
      });
    }
    
    res.json({
      success: true,
      message: 'View tracked successfully'
    });
  } catch (error) {
    console.error('Error tracking view:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to track view',
      error: error.message
    });
  }
};

// MARK: - Video Comments

// Get comments for a video
exports.getVideoComments = async (req, res) => {
  try {
    const { videoId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    // Verify video exists
    const videoDoc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    // Get top-level comments (not replies)
    const commentsQuery = await db.collection('video_comments')
      .where('videoId', '==', videoId)
      .where('parentCommentId', '==', null)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    // Comments from blocked users (either direction) and moderation-hidden
    // comments are invisible
    const viewerDocForComments = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
    const { excludedUserIds: excludedForComments } = require('../../services/moderationService');
    const commentExcluded = excludedForComments(viewerDocForComments.exists ? viewerDocForComments.data() : {});

    const comments = [];
    for (const doc of commentsQuery.docs) {
      const comment = serializeDoc(doc);
      if (commentExcluded.has(comment.userId)) continue;
      if (comment.moderationStatus === 'under_review' || comment.moderationStatus === 'removed') continue;

      // Get user details
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(comment.userId).get();
      if (userDoc.exists) {
        const user = serializeDoc(userDoc);
        // Flatten user fields for iOS compatibility
        comment.userName = user.displayName || 'Unknown User';
        comment.userPhoto = user.profilePicture || null;
      } else {
        comment.userName = 'Unknown User';
        comment.userPhoto = null;
      }
      
      // Get reply count
      const replyCountQuery = await db.collection('video_comments')
        .where('parentCommentId', '==', doc.id)
        .count()
        .get();
      
      comment.replyCount = replyCountQuery.data().count || 0;
      
      // Check if current user has liked this comment (if user is authenticated)
      comment.isLikedByUser = false;
      comment.likes = comment.likes || [];
      
      comments.push(comment);
    }
    
    res.json({
      success: true,
      data: comments,
      hasMore: comments.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting video comments:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get comments',
      error: error.message
    });
  }
};

// Create a comment on a video
exports.createVideoComment = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    const { text } = req.body;
    
    // Validate input
    if (!text || text.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Comment text is required'
      });
    }
    
    // Verify video exists
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const video = videoDoc.data();
    
    // Create comment
    const commentData = {
      videoId,
      userId,
      text: text.trim(),
      parentCommentId: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      editedAt: null,
      deletedAt: null
    };
    
    const commentRef = await db.collection('video_comments').add(commentData);
    const commentDoc = await commentRef.get();
    const comment = serializeDoc(commentDoc);
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      comment.user = serializeDoc(userDoc);
    }
    
    // Update video comment count
    await videoRef.update({
      commentCount: FieldValue.increment(1)
    });
    
    // Send SSE notification
    const userData = comment.user || {};
    
    // Notify video owner of the comment (if not self-comment)
    if (video.userId && video.userId !== userId) {
      sseService.notifyUser(video.userId, 'video_comment', {
        videoId,
        commentBy: userId,
        commentByName: userData.displayName || 'Unknown User',
        videoTitle: video.title,
        commentText: text.trim(),
        timestamp: new Date().toISOString()
      });
    }
    
    // Broadcast to all users viewing this video
    sseService.broadcastVideoEngagement(videoId, 'comment', {
      userId,
      videoId,
      type: 'comment',
      comment: comment,
      timestamp: new Date().toISOString()
    });
    
    res.json({
      success: true,
      data: comment
    });
  } catch (error) {
    console.error('Error creating video comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create comment',
      error: error.message
    });
  }
};

// Get activity for a video
exports.getVideoActivity = async (req, res) => {
  try {
    const { videoId } = req.params;
    const userId = req.user.uid;
    
    // Find activity for this video
    const activityQuery = await db.collection(COLLECTIONS.ACTIVITIES)
      .where('targetType', '==', 'place_video')
      .where('targetId', '==', videoId)
      .limit(1)
      .get();
    
    if (activityQuery.empty) {
      return res.status(404).json({
        success: false,
        message: 'Activity not found for this video'
      });
    }
    
    const activity = serializeDoc(activityQuery.docs[0]);
    
    // Check if user has reacted
    const reactionQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', '==', activity.id)
      .where('userId', '==', userId)
      .limit(1)
      .get();
    
    if (!reactionQuery.empty) {
      activity.userReaction = reactionQuery.docs[0].data().emoji;
    } else {
      activity.userReaction = null;
    }
    
    // Get reaction summary
    const reactionsQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', '==', activity.id)
      .get();
    
    const reactionCounts = {};
    reactionsQuery.docs.forEach(doc => {
      const emoji = doc.data().emoji;
      reactionCounts[emoji] = (reactionCounts[emoji] || 0) + 1;
    });
    
    activity.reactionSummary = Object.entries(reactionCounts)
      .map(([emoji, count]) => ({ emoji, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 3);
    
    res.json({
      success: true,
      data: activity
    });
  } catch (error) {
    console.error('Error getting video activity:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video activity',
      error: error.message
    });
  }
};

// Get video likes list
exports.getVideoLikes = async (req, res) => {
  try {
    const { videoId } = req.params;
    const { limit = 50, offset = 0 } = req.query;
    
    // Get likes for the video
    const likesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
      .where('videoId', '==', videoId)
      .orderBy('timestamp', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    // Get user details for each like
    const userIds = likesQuery.docs.map(doc => doc.data().userId);
    
    if (userIds.length === 0) {
      return res.json({
        success: true,
        data: []
      });
    }
    
    // Fetch user details (chunked — a popular video can pass 30 likers)
    const userDocs = await queryInChunks(userIds, chunk =>
      db.collection(COLLECTIONS.USERS)
        .where(admin.firestore.FieldPath.documentId(), 'in', chunk)
        .get()
    );

    const usersMap = {};
    userDocs.forEach(doc => {
      const user = serializeDoc(doc);
      usersMap[user.id] = user;
    });
    
    // Combine likes with user details
    const likes = likesQuery.docs.map(doc => {
      const likeData = doc.data();
      const user = usersMap[likeData.userId] || {};
      
      return {
        userId: likeData.userId,
        displayName: user.displayName || 'Unknown User',
        profilePicture: user.profilePicture || null,
        timestamp: likeData.timestamp || new Date()
      };
    });
    
    res.json({
      success: true,
      data: likes
    });
  } catch (error) {
    console.error('Error getting video likes:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video likes',
      error: error.message
    });
  }
};

// Delete a video comment
exports.deleteVideoComment = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId, commentId } = req.params;
    
    // Get the comment
    const commentRef = db.collection('video_comments').doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = commentDoc.data();
    
    // Check if comment belongs to this video
    if (comment.videoId !== videoId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this video'
      });
    }
    
    // Check if user owns the comment
    if (comment.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You can only delete your own comments'
      });
    }
    
    // Soft delete the comment
    await commentRef.update({
      deletedAt: new Date().toISOString(),
      text: '[deleted]'
    });
    
    // Update video comment count
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    await videoRef.update({
      commentCount: FieldValue.increment(-1)
    });
    
    res.json({
      success: true,
      message: 'Comment deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting video comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete comment',
      error: error.message
    });
  }
};

// Create a reply to a video comment
exports.createVideoCommentReply = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId, commentId } = req.params;
    const { text } = req.body;
    
    // Validate input
    if (!text || text.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Reply text is required'
      });
    }
    
    // Verify parent comment exists
    const parentCommentRef = db.collection('video_comments').doc(commentId);
    const parentCommentDoc = await parentCommentRef.get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = parentCommentDoc.data();
    
    // Ensure parent comment belongs to the video
    if (parentComment.videoId !== videoId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this video'
      });
    }
    
    // Create reply
    const replyData = {
      videoId,
      userId,
      text: text.trim(),
      parentCommentId: commentId,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      editedAt: null,
      deletedAt: null
    };
    
    const replyRef = await db.collection('video_comments').add(replyData);
    const replyDoc = await replyRef.get();
    const reply = serializeDoc(replyDoc);
    
    // Get user details and flatten for iOS compatibility
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      const user = serializeDoc(userDoc);
      reply.userName = user.displayName || 'Unknown User';
      reply.userPhoto = user.profilePicture || null;
    } else {
      reply.userName = 'Unknown User';
      reply.userPhoto = null;
    }
    
    // Add default fields for compatibility
    reply.likes = reply.likes || [];
    reply.isLikedByUser = false;
    reply.replyCount = 0;
    
    // TODO: Send notification to parent comment author
    
    res.json({
      success: true,
      data: reply
    });
  } catch (error) {
    console.error('Error creating video comment reply:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create reply',
      error: error.message
    });
  }
};

// Like or unlike a video comment
exports.likeVideoComment = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId, commentId } = req.params;
    
    // Get the comment
    const commentRef = db.collection('video_comments').doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = commentDoc.data();
    
    // Check if comment belongs to this video
    if (comment.videoId !== videoId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this video'
      });
    }
    
    // Get current likes array or initialize
    let likes = comment.likes || [];
    let liked = false;
    
    // Toggle like status
    if (likes.includes(userId)) {
      // Unlike - remove user from likes array
      likes = likes.filter(id => id !== userId);
      liked = false;
    } else {
      // Like - add user to likes array
      likes.push(userId);
      liked = true;
    }
    
    // Update comment with new likes array and count
    await commentRef.update({
      likes: likes,
      likesCount: likes.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    // Log activity if liking (not unliking)
    if (liked && comment.userId !== userId) {
      try {
        await logActivity({
          type: 'comment_liked',
          actorId: userId,
          targetType: 'comment',
          targetId: commentId,
          targetName: comment.text.substring(0, 50) + (comment.text.length > 50 ? '...' : ''),
          metadata: {
            videoId: videoId,
            commentId: commentId,
            commentAuthorId: comment.userId
          }
        });
      } catch (activityError) {
        console.error('Failed to log like activity:', activityError);
        // Don't fail the request if activity logging fails
      }
    }
    
    res.json({
      success: true,
      liked: liked,
      likesCount: likes.length
    });
    
  } catch (error) {
    console.error('Error liking video comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update comment like',
      error: error.message
    });
  }
};

// Get replies for a video comment
exports.getVideoCommentReplies = async (req, res) => {
  try {
    const { videoId, commentId } = req.params;
    
    // Verify parent comment exists
    const parentCommentDoc = await db.collection('video_comments').doc(commentId).get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = parentCommentDoc.data();
    
    if (parentComment.videoId !== videoId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this video'
      });
    }
    
    // Get replies
    const repliesQuery = await db.collection('video_comments')
      .where('parentCommentId', '==', commentId)
      .orderBy('createdAt', 'asc')
      .get();
    
    const replies = [];
    for (const replyDoc of repliesQuery.docs) {
      const reply = serializeDoc(replyDoc);
      
      // Get user details and flatten for iOS compatibility
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(reply.userId).get();
      if (userDoc.exists) {
        const user = serializeDoc(userDoc);
        reply.userName = user.displayName || 'Unknown User';
        reply.userPhoto = user.profilePicture || null;
      } else {
        reply.userName = 'Unknown User';
        reply.userPhoto = null;
      }
      
      // Add default fields for compatibility
      reply.likes = reply.likes || [];
      reply.isLikedByUser = false;
      reply.replyCount = 0;
      
      replies.push(reply);
    }
    
    res.json({
      success: true,
      data: replies
    });
  } catch (error) {
    console.error('Error getting video comment replies:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get replies',
      error: error.message
    });
  }
};
