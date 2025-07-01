// backend/controllers/firebaseCircleController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createCircle, 
  validateCircle,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { trackCircleCreated } = require('../services/activityService');

const db = getFirestore();

// @desc    Get all circles for current user
// @route   GET /api/circles
// @access  Private
exports.getMyCircles = async (req, res, next) => {
  try {
    console.log('🔍 DEBUG getMyCircles:', {
      userUid: req.user.uid,
      userObject: req.user
    });
    
    if (!req.user.uid) {
      return res.status(400).json({
        success: false,
        message: 'User ID is missing'
      });
    }
    
    const circlesRef = db.collection(COLLECTIONS.CIRCLES);
    // Simplified query - just filter by owner, no ordering for now
    const snapshot = await circlesRef
      .where('owner', '==', req.user.uid)
      .get();

    const circles = serializeQuerySnapshot(snapshot);
    
    // Get user's circle order preference
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
    const userData = userDoc.exists ? serializeDoc(userDoc) : null;
    const circleOrder = userData?.circleOrder || [];
    
    // Sort circles based on user's preferred order
    let sortedCircles;
    if (circleOrder.length > 0) {
      // Create a map for quick lookup
      const circlesMap = new Map();
      circles.forEach(circle => {
        circlesMap.set(circle.id, circle);
      });
      
      // Sort based on the order array
      sortedCircles = [];
      circleOrder.forEach(circleId => {
        const circle = circlesMap.get(circleId);
        if (circle) {
          sortedCircles.push(circle);
          circlesMap.delete(circleId);
        }
      });
      
      // Add any remaining circles not in the order array (newly created circles)
      circlesMap.forEach(circle => {
        sortedCircles.push(circle);
      });
    } else {
      // Fallback to date-based sorting
      sortedCircles = circles.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    }

    res.status(200).json({
      success: true,
      count: sortedCircles.length,
      circles: sortedCircles
    });
  } catch (error) {
    console.error('Error fetching user circles:', error);
    next(error);
  }
};

// @desc    Get circles shared with me
// @route   GET /api/circles/shared  
// @access  Private
exports.getSharedCircles = async (req, res, next) => {
  try {
    const circlesRef = db.collection(COLLECTIONS.CIRCLES);
    
    // Get public circles and circles shared with me
    const publicCirclesPromise = circlesRef
      .where('privacy', '==', 'public')
      .where('owner', '!=', req.user.uid)
      .orderBy('owner') // Required for != queries
      .orderBy('updatedAt', 'desc')
      .get();
      
    const sharedCirclesPromise = circlesRef
      .where('sharedWith', 'array-contains', req.user.uid)
      .orderBy('updatedAt', 'desc')
      .get();

    const [publicSnapshot, sharedSnapshot] = await Promise.all([
      publicCirclesPromise,
      sharedCirclesPromise
    ]);

    const publicCircles = serializeQuerySnapshot(publicSnapshot);
    const sharedCircles = serializeQuerySnapshot(sharedSnapshot);
    
    // Combine and deduplicate
    const allCircles = [...publicCircles, ...sharedCircles];
    const uniqueCircles = allCircles.filter((circle, index, self) => 
      index === self.findIndex(c => c.id === circle.id)
    );

    res.status(200).json({
      success: true,
      count: uniqueCircles.length,
      circles: uniqueCircles
    });
  } catch (error) {
    console.error('Error fetching shared circles:', error);
    next(error);
  }
};

// @desc    Get single circle
// @route   GET /api/circles/:id
// @access  Private
exports.getCircle = async (req, res, next) => {
  try {
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(req.params.id).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    // Check permissions
    const isOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith.includes(req.user.uid);
    const isPublic = circle.privacy === 'public';
    
    // For myNetwork privacy, check if users are connected
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      // Check if the current user is connected to the circle owner
      const connectionQuery1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', req.user.uid)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connectionQuery2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', req.user.uid)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connectionQuery1.empty || !connectionQuery2.empty;
    }
    
    // Allow access if user is owner, shared with, public, or connected (for myNetwork)
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to access this circle'
      });
    }

    res.status(200).json({
      success: true,
      circle: circle
    });
  } catch (error) {
    console.error('Error fetching circle:', error);
    next(error);
  }
};

// @desc    Create new circle
// @route   POST /api/circles
// @access  Private
exports.createCircle = async (req, res, next) => {
  try {
    console.log('🔍 DEBUG createCircle:', {
      userUid: req.user.uid,
      requestBody: req.body,
      userObject: req.user
    });
    
    if (!req.user.uid) {
      return res.status(400).json({
        success: false,
        message: 'User ID is missing'
      });
    }
    
    // Validate input
    const validationErrors = validateCircle(req.body);
    if (validationErrors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: validationErrors
      });
    }

    // Create circle data
    const circleData = createCircle(req.body, req.user.uid);
    
    // Add to Firestore
    const circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circleData);
    
    // Get the created circle with ID
    const createdCircle = await circleRef.get();
    const circle = serializeDoc(createdCircle);

    // Track activity for network connections
    await trackCircleCreated(circleRef.id, req.user.uid);

    res.status(201).json({
      success: true,
      circle: circle
    });
  } catch (error) {
    console.error('Error creating circle:', error);
    next(error);
  }
};

// @desc    Update circle
// @route   PUT /api/circles/:id
// @access  Private
exports.updateCircle = async (req, res, next) => {
  try {
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(req.params.id);
    const circleDoc = await circleRef.get();

    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    const userId = req.user.firebaseDocId || req.user.uid;

    // Check if user is owner or editor
    const isOwner = circle.owner === userId;
    const isEditor = (circle.editors || []).includes(userId);
    
    if (!isOwner && !isEditor) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to update this circle'
      });
    }

    // Validate only the fields that are being updated
    const updateData = {};
    
    // Only validate and add fields that are present in the request
    if (req.body.name !== undefined) {
      if (!req.body.name || req.body.name.trim().length === 0) {
        return res.status(400).json({
          success: false,
          message: 'Circle name cannot be empty'
        });
      }
      if (req.body.name.length > 50) {
        return res.status(400).json({
          success: false,
          message: 'Circle name must be 50 characters or less'
        });
      }
      updateData.name = req.body.name;
    }
    
    if (req.body.description !== undefined) {
      if (req.body.description && req.body.description.length > 500) {
        return res.status(400).json({
          success: false,
          message: 'Description must be 500 characters or less'
        });
      }
      updateData.description = req.body.description;
    }
    
    if (req.body.privacy !== undefined) {
      const validPrivacyLevels = ['public', 'myNetwork', 'private'];
      if (!validPrivacyLevels.includes(req.body.privacy)) {
        return res.status(400).json({
          success: false,
          message: 'Privacy must be public, myNetwork, or private'
        });
      }
      updateData.privacy = req.body.privacy;
    }
    
    if (req.body.category !== undefined) {
      const validCategories = ['travel', 'food', 'services', 'shopping', 'healthcare', 'entertainment', 'other'];
      if (!validCategories.includes(req.body.category)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid category'
        });
      }
      updateData.category = req.body.category;
    }
    
    // Add other fields without validation
    if (req.body.coverImage !== undefined) updateData.coverImage = req.body.coverImage;
    if (req.body.location !== undefined) updateData.location = req.body.location;
    if (req.body.tags !== undefined) updateData.tags = req.body.tags;

    // Add timestamp
    updateData.updatedAt = new Date().toISOString();
    
    // Make sure we have something to update
    if (Object.keys(updateData).length === 1) { // Only updatedAt
      return res.status(400).json({
        success: false,
        message: 'No fields to update'
      });
    }

    await circleRef.update(updateData);
    
    // Get updated circle
    const updatedCircleDoc = await circleRef.get();
    const updatedCircle = serializeDoc(updatedCircleDoc);

    res.status(200).json({
      success: true,
      circle: updatedCircle
    });
  } catch (error) {
    console.error('Error updating circle:', error);
    next(error);
  }
};

// @desc    Delete circle
// @route   DELETE /api/circles/:id
// @access  Private
exports.deleteCircle = async (req, res, next) => {
  try {
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(req.params.id);
    const circleDoc = await circleRef.get();

    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);

    // Make sure user is circle owner
    if (circle.owner !== req.user.uid) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this circle'
      });
    }

    // Delete all places in this circle first
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', req.params.id)
      .get();
    
    const batch = db.batch();
    placesSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    // Delete the circle
    batch.delete(circleRef);
    
    await batch.commit();

    res.status(200).json({
      success: true,
      message: 'Circle deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting circle:', error);
    next(error);
  }
};

// @desc    Share circle with users
// @route   POST /api/circles/:id/share
// @access  Private
exports.shareCircle = async (req, res, next) => {
  try {
    const { userIds } = req.body;
    
    if (!userIds || !Array.isArray(userIds)) {
      return res.status(400).json({
        success: false,
        message: 'User IDs array is required'
      });
    }

    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(req.params.id);
    const circleDoc = await circleRef.get();

    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);

    // Make sure user is circle owner
    if (circle.owner !== req.user.uid) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to share this circle'
      });
    }

    // Add users to sharedWith array (avoid duplicates)
    const currentSharedWith = circle.sharedWith || [];
    const newSharedWith = [...new Set([...currentSharedWith, ...userIds])];

    await circleRef.update({
      sharedWith: newSharedWith,
      updatedAt: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: 'Circle shared successfully'
    });
  } catch (error) {
    console.error('Error sharing circle:', error);
    next(error);
  }
};

// @desc    Follow/unfollow circle
// @route   POST /api/circles/:id/follow
// @route   POST /api/circles/:id/unfollow
// @access  Private
exports.followCircle = async (req, res, next) => {
  try {
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(req.params.id);
    const circleDoc = await circleRef.get();

    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    const followers = circle.followers || [];
    const isFollowing = followers.includes(req.user.uid);
    const action = req.path.endsWith('/follow') ? 'follow' : 'unfollow';

    let newFollowers;
    if (action === 'follow' && !isFollowing) {
      newFollowers = [...followers, req.user.uid];
    } else if (action === 'unfollow' && isFollowing) {
      newFollowers = followers.filter(id => id !== req.user.uid);
    } else {
      return res.status(400).json({
        success: false,
        message: `Already ${action}ing this circle`
      });
    }

    await circleRef.update({
      followers: newFollowers,
      updatedAt: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: `Successfully ${action}ed circle`
    });
  } catch (error) {
    console.error(`Error ${req.path.endsWith('/follow') ? 'following' : 'unfollowing'} circle:`, error);
    next(error);
  }
};

exports.unfollowCircle = exports.followCircle; // Same handler, different action

// @desc    Add editor to circle
// @route   POST /api/circles/:id/editors
// @access  Private (owner only)
exports.addEditor = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const { userId } = req.body;
    const requesterId = req.user.firebaseDocId || req.user.uid;

    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }

    // Get circle
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();

    // Check if requester is the owner
    if (circle.owner !== requesterId) {
      return res.status(403).json({
        success: false,
        message: 'Only the circle owner can add editors'
      });
    }

    // Check if user exists
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Check if user is already an editor
    const currentEditors = circle.editors || [];
    if (currentEditors.includes(userId)) {
      return res.status(400).json({
        success: false,
        message: 'User is already an editor'
      });
    }

    // Add user as editor
    await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update({
      editors: [...currentEditors, userId],
      updatedAt: new Date().toISOString()
    });

    // Return updated circle
    const updatedCircleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    const updatedCircle = serializeDoc(updatedCircleDoc);

    res.status(200).json({
      success: true,
      data: updatedCircle
    });
  } catch (error) {
    console.error('Error adding editor:', error);
    next(error);
  }
};

// @desc    Remove editor from circle
// @route   DELETE /api/circles/:id/editors/:userId
// @access  Private (owner only)
exports.removeEditor = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const userIdToRemove = req.params.userId;
    const requesterId = req.user.firebaseDocId || req.user.uid;

    // Get circle
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();

    // Check if requester is the owner
    if (circle.owner !== requesterId) {
      return res.status(403).json({
        success: false,
        message: 'Only the circle owner can remove editors'
      });
    }

    // Remove user from editors
    const currentEditors = circle.editors || [];
    const updatedEditors = currentEditors.filter(id => id !== userIdToRemove);

    await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update({
      editors: updatedEditors,
      updatedAt: new Date().toISOString()
    });

    // Return updated circle
    const updatedCircleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    const updatedCircle = serializeDoc(updatedCircleDoc);

    res.status(200).json({
      success: true,
      data: updatedCircle
    });
  } catch (error) {
    console.error('Error removing editor:', error);
    next(error);
  }
};

// @desc    Get circle editors
// @route   GET /api/circles/:id/editors
// @access  Private
exports.getEditors = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const requesterId = req.user.firebaseDocId || req.user.uid;

    // Get circle
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();

    // Check if user has access to view editors (owner or editor)
    const editors = circle.editors || [];
    if (circle.owner !== requesterId && !editors.includes(requesterId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view editors'
      });
    }

    // Fetch editor user details
    const editorDetails = await Promise.all(
      editors.map(async (editorId) => {
        const userDoc = await db.collection(COLLECTIONS.USERS).doc(editorId).get();
        if (userDoc.exists) {
          return serializeDoc(userDoc);
        }
        return null;
      })
    );

    res.status(200).json({
      success: true,
      data: editorDetails.filter(editor => editor !== null)
    });
  } catch (error) {
    console.error('Error getting editors:', error);
    next(error);
  }
};