// backend/controllers/activityInteractionController.js
const { getFirestore, FieldValue } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createActivityReaction,
  createActivityComment,
  validateActivityReaction,
  validateActivityComment,
  createNotification,
  validateNotification,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const notificationService = require('../services/notificationService');
const sseService = require('../services/sseService');

const db = getFirestore();

// Add or update a reaction to an activity
exports.addReaction = async (req, res) => {
  try {
    const userId = req.user.uid;
    const activityId = req.params.activityId;
    const { emoji } = req.body;
    
    // Get user data
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    const userData = userDoc.data();
    
    // Create reaction data
    const reactionData = {
      activityId,
      userId,  // Add the userId here
      emoji,
      userName: userData.displayName || userData.firstName || 'User',
      userPhoto: userData.profilePicture || null
    };
    
    // Validate reaction
    const errors = validateActivityReaction(reactionData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        errors
      });
    }
    
    // Check if activity exists
    const activityDoc = await db.collection(COLLECTIONS.ACTIVITIES).doc(activityId).get();
    if (!activityDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Activity not found'
      });
    }
    const activity = activityDoc.data();
    
    // Check if user already reacted - use composite key for unique reaction
    const reactionId = `${activityId}_${userId}`;
    const existingReactionRef = db.collection(COLLECTIONS.ACTIVITY_REACTIONS).doc(reactionId);
    const existingReaction = await existingReactionRef.get();
    
    const reaction = createActivityReaction(reactionData);
    
    if (existingReaction.exists) {
      // Update existing reaction
      await existingReactionRef.update({
        emoji: emoji,
        updatedAt: new Date().toISOString()
      });
    } else {
      // Create new reaction
      await existingReactionRef.set(reaction);
      
      // Update activity reaction count
      await db.collection(COLLECTIONS.ACTIVITIES).doc(activityId).update({
        reactionCount: FieldValue.increment(1),
        updatedAt: new Date().toISOString()
      });
      
      // Send notification to activity owner if different from reactor
      if (activity.actorId !== userId) {
        // Save notification to Firestore
        const notificationData = createNotification({
          userId: activity.actorId,
          type: 'activity_reaction',
          title: 'New Reaction',
          body: `${userData.displayName} reacted ${emoji} to your activity`,
          data: {
            activityId: activityId,
            fromUserId: userId,
            fromUserName: userData.displayName,
            fromUserPhoto: userData.profilePicture || null,
            emoji: emoji
          }
        });

        const validationErrors = validateNotification(notificationData);
        if (validationErrors.length === 0) {
          const notificationRef = await db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
          
          // Send SSE event for real-time notification count update
          sseService.notifyUser(activity.actorId, 'new_notification', {
            notificationId: notificationRef.id,
            type: 'activity_reaction',
            title: notificationData.title,
            body: notificationData.body,
            data: notificationData.data
          });
        } else {
          console.error('❌ Validation errors for activity reaction notification:', validationErrors);
        }

        // Also send push notification
        await notificationService.sendToUser(activity.actorId, {
          type: 'activity_reaction',
          title: 'New Reaction',
          body: `${userData.displayName} reacted ${emoji} to your activity`,
          data: {
            activityId: activityId,
            userId: userId,
            emoji: emoji
          }
        });
      }
    }
    
    // Send real-time update
    sseService.notifyUser(activity.actorId, 'activity_reaction', {
      activityId,
      userId,
      emoji,
      userName: userData.displayName
    });
    
    res.json({
      success: true,
      data: { reactionId, emoji }
    });
  } catch (error) {
    console.error('Error adding reaction:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to add reaction',
      error: error.message
    });
  }
};

// Remove a reaction from an activity
exports.removeReaction = async (req, res) => {
  try {
    const userId = req.user.uid;
    const activityId = req.params.activityId;
    
    // Use composite key for reaction
    const reactionId = `${activityId}_${userId}`;
    const reactionRef = db.collection(COLLECTIONS.ACTIVITY_REACTIONS).doc(reactionId);
    const reactionDoc = await reactionRef.get();
    
    if (!reactionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Reaction not found'
      });
    }
    
    // Delete reaction
    await reactionRef.delete();
    
    // Update activity reaction count
    await db.collection(COLLECTIONS.ACTIVITIES).doc(activityId).update({
      reactionCount: FieldValue.increment(-1),
      updatedAt: new Date().toISOString()
    });
    
    res.json({
      success: true,
      message: 'Reaction removed'
    });
  } catch (error) {
    console.error('Error removing reaction:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to remove reaction',
      error: error.message
    });
  }
};

// Get reactions for an activity
exports.getReactions = async (req, res) => {
  try {
    const activityId = req.params.activityId;
    
    const reactionsQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', '==', activityId)
      .orderBy('createdAt', 'desc')
      .get();
    
    const reactions = serializeQuerySnapshot(reactionsQuery);
    
    // Group reactions by emoji
    const reactionGroups = {};
    reactions.forEach(reaction => {
      if (!reactionGroups[reaction.emoji]) {
        reactionGroups[reaction.emoji] = {
          emoji: reaction.emoji,
          count: 0,
          users: []
        };
      }
      reactionGroups[reaction.emoji].count++;
      reactionGroups[reaction.emoji].users.push({
        userId: reaction.userId,
        userName: reaction.userName,
        userPhoto: reaction.userPhoto
      });
    });
    
    res.json({
      success: true,
      data: {
        reactions: reactions,
        groups: Object.values(reactionGroups),
        totalCount: reactions.length
      }
    });
  } catch (error) {
    console.error('Error getting reactions:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get reactions',
      error: error.message
    });
  }
};

// Get detailed reactions for an activity (for engagement view)
exports.getReactionDetails = async (req, res) => {
  try {
    const activityId = req.params.activityId;
    
    const reactionsQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', '==', activityId)
      .orderBy('createdAt', 'desc')
      .get();
    
    const reactions = serializeQuerySnapshot(reactionsQuery);
    
    // Transform reactions to include full user details
    const detailedReactions = reactions.map(reaction => ({
      userId: reaction.userId,
      displayName: reaction.userName,
      profilePicture: reaction.userPhoto,
      emoji: reaction.emoji,
      timestamp: reaction.createdAt
    }));
    
    res.json({
      success: true,
      data: detailedReactions
    });
  } catch (error) {
    console.error('Error getting reaction details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get reaction details',
      error: error.message
    });
  }
};

// Add a comment to an activity
exports.addComment = async (req, res) => {
  try {
    const userId = req.user.uid;
    const activityId = req.params.activityId;
    const { text, parentCommentId } = req.body;
    
    // Get user data
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    const userData = userDoc.data();
    
    // Create comment data
    const commentData = {
      activityId,
      userId,  // Add the userId here
      text,
      parentCommentId,
      userName: userData.displayName || userData.firstName || 'User',
      userPhoto: userData.profilePicture || null
    };
    
    // Validate comment
    const errors = validateActivityComment(commentData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        errors
      });
    }
    
    // Check if activity exists
    const activityDoc = await db.collection(COLLECTIONS.ACTIVITIES).doc(activityId).get();
    if (!activityDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Activity not found'
      });
    }
    const activity = activityDoc.data();
    
    // Create comment
    const comment = createActivityComment(commentData);
    const commentRef = await db.collection(COLLECTIONS.ACTIVITY_COMMENTS).add(comment);
    const commentDoc = await commentRef.get();
    
    // Update activity comment count
    await db.collection(COLLECTIONS.ACTIVITIES).doc(activityId).update({
      commentCount: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });
    
    // If this is a reply, update parent comment's reply count
    if (parentCommentId) {
      await db.collection(COLLECTIONS.ACTIVITY_COMMENTS).doc(parentCommentId).update({
        replyCount: FieldValue.increment(1)
      });
    }
    
    // Send notification to activity owner if different from commenter
    if (activity.actorId !== userId) {
      // Save notification to Firestore
      const notificationData = createNotification({
        userId: activity.actorId,
        type: 'activity_comment',
        title: 'New Comment',
        body: `${userData.displayName} commented on your activity`,
        data: {
          activityId: activityId,
          commentId: commentRef.id,
          fromUserId: userId,
          fromUserName: userData.displayName,
          fromUserPhoto: userData.profilePicture || null,
          commentText: text
        }
      });

      const validationErrors = validateNotification(notificationData);
      if (validationErrors.length === 0) {
        const notificationRef = await db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
        
        // Send SSE event for real-time notification count update
        sseService.notifyUser(activity.actorId, 'new_notification', {
          notificationId: notificationRef.id,
          type: 'activity_comment',
          title: notificationData.title,
          body: notificationData.body,
          data: notificationData.data
        });
      } else {
        console.error('❌ Validation errors for activity comment notification:', validationErrors);
      }

      // Also send push notification
      await notificationService.sendToUser(activity.actorId, {
        type: 'activity_comment',
        title: 'New Comment',
        body: `${userData.displayName} commented on your activity`,
        data: {
          activityId: activityId,
          commentId: commentRef.id,
          userId: userId
        }
      });
    }
    
    // Send real-time update
    sseService.notifyUser(activity.actorId, 'activity_comment', {
      activityId,
      commentId: commentRef.id,
      userId,
      userName: userData.displayName,
      text
    });
    
    res.status(201).json({
      success: true,
      data: serializeDoc(commentDoc)
    });
  } catch (error) {
    console.error('Error adding comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to add comment',
      error: error.message
    });
  }
};

// Get comments for an activity
exports.getComments = async (req, res) => {
  try {
    const activityId = req.params.activityId;
    const { parentCommentId } = req.query;
    
    let query = db.collection(COLLECTIONS.ACTIVITY_COMMENTS)
      .where('activityId', '==', activityId);
    
    // If parentCommentId is provided, get replies
    // If null/undefined, get top-level comments
    if (parentCommentId) {
      query = query.where('parentCommentId', '==', parentCommentId);
    } else {
      query = query.where('parentCommentId', '==', null);
    }
    
    const commentsQuery = await query
      .orderBy('createdAt', 'desc')
      .get();
    
    const comments = serializeQuerySnapshot(commentsQuery);
    
    res.json({
      success: true,
      data: comments
    });
  } catch (error) {
    console.error('Error getting comments:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get comments',
      error: error.message
    });
  }
};

// Delete a comment
exports.deleteComment = async (req, res) => {
  try {
    const userId = req.user.uid;
    const activityId = req.params.activityId;
    const commentId = req.params.commentId;
    
    // Get comment
    const commentRef = db.collection(COLLECTIONS.ACTIVITY_COMMENTS).doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = commentDoc.data();
    
    // Verify ownership
    if (comment.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized to delete this comment'
      });
    }
    
    // Delete comment
    await commentRef.delete();
    
    // Update activity comment count
    await db.collection(COLLECTIONS.ACTIVITIES).doc(activityId).update({
      commentCount: FieldValue.increment(-1),
      updatedAt: new Date().toISOString()
    });
    
    // If this was a reply, update parent comment's reply count
    if (comment.parentCommentId) {
      await db.collection(COLLECTIONS.ACTIVITY_COMMENTS).doc(comment.parentCommentId).update({
        replyCount: FieldValue.increment(-1)
      });
    }
    
    res.json({
      success: true,
      message: 'Comment deleted'
    });
  } catch (error) {
    console.error('Error deleting comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete comment',
      error: error.message
    });
  }
};

// Like/unlike a comment
exports.toggleCommentLike = async (req, res) => {
  try {
    const userId = req.user.uid;
    const commentId = req.params.commentId;
    
    const commentRef = db.collection(COLLECTIONS.ACTIVITY_COMMENTS).doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = commentDoc.data();
    const likes = comment.likes || [];
    const isLiked = likes.includes(userId);
    
    if (isLiked) {
      // Unlike
      await commentRef.update({
        likes: FieldValue.arrayRemove(userId),
        likesCount: FieldValue.increment(-1)
      });
    } else {
      // Like
      await commentRef.update({
        likes: FieldValue.arrayUnion(userId),
        likesCount: FieldValue.increment(1)
      });
    }
    
    res.json({
      success: true,
      data: { isLiked: !isLiked }
    });
  } catch (error) {
    console.error('Error toggling comment like:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to toggle comment like',
      error: error.message
    });
  }
};