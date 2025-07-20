// backend/controllers/suggestionController.js
const { getFirestore } = require('../config/firebase');
const { FieldValue, FieldPath } = require('firebase-admin/firestore');
const { 
  COLLECTIONS, 
  createSuggestion, 
  validateSuggestion, 
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const notificationService = require('../services/notificationService');

const db = getFirestore();

// @desc    Create a new suggestion
// @route   POST /api/suggestions
// @access  Private
const createNewSuggestion = async (req, res) => {
  try {
    const userId = req.user.uid;
    const suggestionData = req.body;

    // Validate suggestion data
    const errors = validateSuggestion(suggestionData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors
      });
    }

    // If a placeId is provided, fetch place details
    let placeDetails = null;
    if (suggestionData.placeId) {
      const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(suggestionData.placeId).get();
      if (placeDoc.exists) {
        placeDetails = serializeDoc(placeDoc);
      }
    }

    // Detect place mentions in the message
    const mentionedPlaces = await detectPlaceMentions(suggestionData.message, userId);
    
    // Create suggestion object
    const newSuggestion = createSuggestion({
      ...suggestionData,
      placeDetails,
      mentionedPlaces: mentionedPlaces.map(p => ({
        placeId: p.id,
        name: p.name,
        startIndex: p.startIndex,
        endIndex: p.endIndex
      }))
    }, userId);

    // Save to Firestore
    const suggestionRef = await db.collection(COLLECTIONS.SUGGESTIONS).add(newSuggestion);
    
    // Get user details for response
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userDetails = userDoc.exists ? serializeDoc(userDoc) : null;

    const suggestion = {
      _id: suggestionRef.id,
      id: suggestionRef.id,
      ...newSuggestion,
      userDetails
    };

    res.status(201).json({
      success: true,
      data: suggestion,
      message: 'Suggestion created successfully'
    });

    // Send notifications to network users
    try {
      // Get user's connections
      const connectionsQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      const connectionsQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
      
      const notifyUserIds = new Set();
      
      // Add connections from both queries
      connectionsQuery1.forEach(doc => {
        const conn = doc.data();
        notifyUserIds.add(conn.connectedUserId);
      });
      
      connectionsQuery2.forEach(doc => {
        const conn = doc.data();
        notifyUserIds.add(conn.userId);
      });
      
      // Also notify users who own places mentioned in the suggestion
      if (mentionedPlaces && mentionedPlaces.length > 0) {
        for (const place of mentionedPlaces) {
          if (place.addedBy && place.addedBy !== userId) {
            notifyUserIds.add(place.addedBy);
          }
        }
      }
      
      if (notifyUserIds.size > 0) {
        await notificationService.notifyNewSuggestion(
          suggestion,
          Array.from(notifyUserIds)
        );
      }
    } catch (notifError) {
      console.error('Error sending suggestion notifications:', notifError);
      // Don't fail the request if notifications fail
    }

  } catch (error) {
    console.error('Error creating suggestion:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get suggestions from user's network
// @route   GET /api/suggestions/network
// @access  Private
const getNetworkSuggestions = async (req, res) => {
  try {
    const userId = req.user.uid;
    const now = new Date();

    // Get all connections for the current user
    const connectionsQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted')
      .get();
      
    const connectionsQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted')
      .get();

    // Get connected user IDs
    const connectedUserIds = new Set();
    
    connectionsQuery1.docs.forEach(doc => {
      const connection = doc.data();
      connectedUserIds.add(connection.connectedUserId);
    });
    
    connectionsQuery2.docs.forEach(doc => {
      const connection = doc.data();
      connectedUserIds.add(connection.userId);
    });

    // Include user's own suggestions
    connectedUserIds.add(userId);

    if (connectedUserIds.size === 0) {
      return res.status(200).json({
        success: true,
        data: []
      });
    }

    // Get suggestions from connected users, sorted by most recent first
    const suggestionsQuery = await db.collection(COLLECTIONS.SUGGESTIONS)
      .where('userId', 'in', Array.from(connectedUserIds))
      .orderBy('createdAt', 'desc')
      .limit(100)  // Increased limit since suggestions don't expire
      .get();

    // Build response with user and place details
    const suggestions = [];
    for (const doc of suggestionsQuery.docs) {
      const suggestion = serializeDoc(doc);
      
      // Get user details
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(suggestion.userId).get();
      if (userDoc.exists) {
        suggestion.userDetails = serializeDoc(userDoc);
      }
      
      suggestions.push(suggestion);
    }

    res.status(200).json({
      success: true,
      data: suggestions
    });

  } catch (error) {
    console.error('Error fetching network suggestions:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Delete a suggestion
// @route   DELETE /api/suggestions/:id
// @access  Private (owner only)
const deleteSuggestion = async (req, res) => {
  try {
    const userId = req.user.uid;
    const suggestionId = req.params.id;

    // Get the suggestion
    const suggestionDoc = await db.collection(COLLECTIONS.SUGGESTIONS).doc(suggestionId).get();
    
    if (!suggestionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Suggestion not found'
      });
    }

    const suggestion = suggestionDoc.data();

    // Check if user owns the suggestion
    if (suggestion.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this suggestion'
      });
    }

    // Delete the suggestion
    await suggestionDoc.ref.delete();

    res.status(200).json({
      success: true,
      message: 'Suggestion deleted successfully'
    });

  } catch (error) {
    console.error('Error deleting suggestion:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Clean up expired suggestions (to be called by a cron job or cloud function)
// @route   POST /api/suggestions/cleanup
// @access  Private (admin or system only)
const cleanupExpiredSuggestions = async (req, res) => {
  try {
    const now = new Date();

    // Get expired suggestions
    const expiredQuery = await db.collection(COLLECTIONS.SUGGESTIONS)
      .where('expiresAt', '<=', now.toISOString())
      .get();

    // Delete expired suggestions in batches
    const batch = db.batch();
    let deleteCount = 0;
    
    expiredQuery.docs.forEach(doc => {
      batch.delete(doc.ref);
      deleteCount++;
    });

    if (deleteCount > 0) {
      await batch.commit();
    }

    res.status(200).json({
      success: true,
      message: `Cleaned up ${deleteCount} expired suggestions`
    });

  } catch (error) {
    console.error('Error cleaning up suggestions:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Add comment to suggestion
// @route   POST /api/suggestions/:id/comments
// @access  Private
const addComment = async (req, res) => {
  const { createComment, validateComment, COLLECTIONS } = require('../models/FirestoreModels');
  
  try {
    const userId = req.user.uid;
    const suggestionId = req.params.id;
    const { message } = req.body;

    // Validate comment
    const errors = validateComment({ message, suggestionId });
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors
      });
    }

    // Check if suggestion exists
    const suggestionDoc = await db.collection(COLLECTIONS.SUGGESTIONS).doc(suggestionId).get();
    if (!suggestionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Suggestion not found'
      });
    }

    // Create comment
    const commentData = createComment({
      suggestionId,
      userId,
      message
    });

    const commentRef = await db.collection(COLLECTIONS.COMMENTS).add(commentData);
    
    // Update suggestion comments count
    await suggestionDoc.ref.update({
      commentsCount: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });

    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userDetails = userDoc.exists ? serializeDoc(userDoc) : null;

    res.status(201).json({
      success: true,
      data: {
        _id: commentRef.id,
        ...commentData,
        userDetails
      }
    });

  } catch (error) {
    console.error('Error adding comment:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get comments for a suggestion
// @route   GET /api/suggestions/:id/comments
// @access  Private
const getComments = async (req, res) => {
  const { COLLECTIONS } = require('../models/FirestoreModels');
  
  try {
    const suggestionId = req.params.id;

    // Get comments
    const commentsSnapshot = await db.collection(COLLECTIONS.COMMENTS)
      .where('suggestionId', '==', suggestionId)
      .orderBy('createdAt', 'desc')
      .get();

    // Get user details for each comment
    const comments = await Promise.all(
      commentsSnapshot.docs.map(async (doc) => {
        const comment = doc.data();
        const userDoc = await db.collection(COLLECTIONS.USERS).doc(comment.userId).get();
        const userDetails = userDoc.exists ? serializeDoc(userDoc) : null;

        return {
          _id: doc.id,
          ...comment,
          userDetails
        };
      })
    );

    res.status(200).json({
      success: true,
      data: comments
    });

  } catch (error) {
    console.error('Error getting comments:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// Helper function to detect place mentions in text
const detectPlaceMentions = async (text, userId) => {
  const { COLLECTIONS } = require('../models/FirestoreModels');
  
  try {
    // Get all places from user's circles
    const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .get();
    
    const placeIds = new Set();
    circlesSnapshot.docs.forEach(doc => {
      const circle = doc.data();
      if (circle.places) {
        circle.places.forEach(placeId => placeIds.add(placeId));
      }
    });
    
    if (placeIds.size === 0) return [];
    
    // Get place details
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where(FieldPath.documentId(), 'in', Array.from(placeIds))
      .get();
    
    const mentionedPlaces = [];
    const lowerText = text.toLowerCase();
    
    placesSnapshot.docs.forEach(doc => {
      const place = doc.data();
      const placeName = place.name.toLowerCase();
      
      // Find all occurrences of the place name in the text
      let startIndex = 0;
      while ((startIndex = lowerText.indexOf(placeName, startIndex)) !== -1) {
        mentionedPlaces.push({
          id: doc.id,
          name: place.name,
          startIndex: startIndex,
          endIndex: startIndex + place.name.length
        });
        startIndex += place.name.length;
      }
    });
    
    // Sort by start index
    mentionedPlaces.sort((a, b) => a.startIndex - b.startIndex);
    
    return mentionedPlaces;
  } catch (error) {
    console.error('Error detecting place mentions:', error);
    return [];
  }
};

// @desc    Like a suggestion
// @route   POST /api/suggestions/:id/like
// @access  Private
const likeSuggestion = async (req, res) => {
  try {
    const userId = req.user.uid;
    const suggestionId = req.params.id;

    // Get suggestion
    const suggestionRef = db.collection(COLLECTIONS.SUGGESTIONS).doc(suggestionId);
    const suggestionDoc = await suggestionRef.get();

    if (!suggestionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Suggestion not found'
      });
    }

    const suggestion = suggestionDoc.data();
    const likes = suggestion.likes || [];

    // Check if user already liked
    if (likes.includes(userId)) {
      return res.status(400).json({
        success: false,
        message: 'You have already liked this suggestion'
      });
    }

    // Add user to likes array
    await suggestionRef.update({
      likes: FieldValue.arrayUnion(userId),
      likesCount: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: 'Suggestion liked successfully'
    });

  } catch (error) {
    console.error('Error liking suggestion:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Unlike a suggestion
// @route   DELETE /api/suggestions/:id/like
// @access  Private
const unlikeSuggestion = async (req, res) => {
  try {
    const userId = req.user.uid;
    const suggestionId = req.params.id;

    // Get suggestion
    const suggestionRef = db.collection(COLLECTIONS.SUGGESTIONS).doc(suggestionId);
    const suggestionDoc = await suggestionRef.get();

    if (!suggestionDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Suggestion not found'
      });
    }

    const suggestion = suggestionDoc.data();
    const likes = suggestion.likes || [];

    // Check if user has liked
    if (!likes.includes(userId)) {
      return res.status(400).json({
        success: false,
        message: 'You have not liked this suggestion'
      });
    }

    // Remove user from likes array
    await suggestionRef.update({
      likes: FieldValue.arrayRemove(userId),
      likesCount: FieldValue.increment(-1),
      updatedAt: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: 'Suggestion unliked successfully'
    });

  } catch (error) {
    console.error('Error unliking suggestion:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get suggestions by specific user
// @route   GET /api/suggestions/user/:userId
// @access  Private
const getSuggestionsByUser = async (req, res) => {
  try {
    const requestingUserId = req.user.uid;
    const targetUserId = req.params.userId;
    
    // Verify that the requesting user is connected to the target user
    const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', requestingUserId)
      .where('connectedUserId', '==', targetUserId)
      .where('status', '==', 'accepted')
      .get();
      
    const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', targetUserId)
      .where('connectedUserId', '==', requestingUserId)
      .where('status', '==', 'accepted')
      .get();
    
    const isConnected = !connection1.empty || !connection2.empty;
    const isSelf = requestingUserId === targetUserId;
    
    if (!isConnected && !isSelf) {
      return res.status(403).json({
        success: false,
        message: 'You must be connected to view this user\'s suggestions'
      });
    }
    
    // Get suggestions from the specific user, sorted by most recent first
    const suggestionsQuery = await db.collection(COLLECTIONS.SUGGESTIONS)
      .where('userId', '==', targetUserId)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();
    
    // Build response with user and place details
    const suggestions = [];
    for (const doc of suggestionsQuery.docs) {
      const suggestion = serializeDoc(doc);
      
      // Get user details
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(suggestion.userId).get();
      if (userDoc.exists) {
        suggestion.userDetails = serializeDoc(userDoc);
      }
      
      suggestions.push(suggestion);
    }
    
    res.status(200).json({
      success: true,
      data: suggestions
    });
    
  } catch (error) {
    console.error('Error fetching user suggestions:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

module.exports = {
  createNewSuggestion,
  getNetworkSuggestions,
  getSuggestionsByUser,
  deleteSuggestion,
  cleanupExpiredSuggestions,
  addComment,
  getComments,
  likeSuggestion,
  unlikeSuggestion
};