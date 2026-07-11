// backend/controllers/firebaseCircleController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createCircle, 
  validateCircle,
  createCircleComment,
  validateCircleComment,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { trackCircleCreated, trackCircleView, trackCircleLiked, trackCircleCommented } = require('../services/activityService');
const { normalizeUserId } = require('../services/idService');
const subscriptionLimitService = require('../services/subscriptionLimitService');

const db = getFirestore();

// @desc    Get all circles for current user
// @route   GET /api/circles
// @access  Private
exports.getMyCircles = async (req, res, next) => {
  try {
    console.log('🔍 DEBUG getMyCircles called for user:', {
      userUid: req.user.uid,
      email: req.user.email,
      displayName: req.user.displayName || 'No display name',
      originalUid: req.user.originalUid
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

    let circles = serializeQuerySnapshot(snapshot);
    
    // For the current user's own circles, check if any connections have added new places
    // This helps the user see if their connections have contributed new places to shared circles
    const connectionsSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('status', '==', 'accepted')
      .where('userId', '==', req.user.uid)
      .get();
    
    const connections = serializeQuerySnapshot(connectionsSnapshot);
    
    // Collect all recent activities from connections
    const allActivities = [];
    connections.forEach(conn => {
      const activities = conn.recentActivity || [];
      activities.forEach(activity => {
        // Only include activities where the current user hasn't viewed them
        const viewedBy = activity.viewedBy || [];
        if (!viewedBy.includes(req.user.uid)) {
          allActivities.push(activity);
        }
      });
    });
    
    // Create a map of circleId -> unviewed place count
    const unviewedPlacesByCircle = new Map();
    allActivities
      .filter(a => a.type === 'place' && a.circleId)
      .forEach(activity => {
        const count = unviewedPlacesByCircle.get(activity.circleId) || 0;
        unviewedPlacesByCircle.set(activity.circleId, count + 1);
      });
    
    // Mark circles that have new places
    circles = circles.map(circle => ({
      ...circle,
      hasNewPlaces: unviewedPlacesByCircle.has(circle.id),
      newPlacesCount: unviewedPlacesByCircle.get(circle.id) || 0
    }));
    
    console.log(`🔍 DEBUG - Found ${circles.length} circles for user ${req.user.uid}`);
    if (circles.length > 0) {
      console.log('🔍 DEBUG - Circle names:', circles.map(c => c.name));
      console.log('🔍 DEBUG - Circles with new places:', circles.filter(c => c.hasNewPlaces).map(c => c.name));
      console.log('🔍 DEBUG - First circle data:', {
        name: circles[0].name,
        id: circles[0].id,
        owner: circles[0].owner,
        placesCount: circles[0].placesCount,
        placesArrayLength: circles[0].places?.length,
        hasNewPlaces: circles[0].hasNewPlaces,
        newPlacesCount: circles[0].newPlacesCount
      });
    } else {
      console.log('🔍 DEBUG - No circles found, this might be the issue!');
    }
    
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
    const currentUserId = req.user.uid;
    
    // Get public circles and circles shared with me
    const publicCirclesPromise = circlesRef
      .where('privacy', '==', 'public')
      .where('owner', '!=', currentUserId)
      .orderBy('owner') // Required for != queries
      .orderBy('updatedAt', 'desc')
      .get();
      
    const sharedCirclesPromise = circlesRef
      .where('sharedWith', 'array-contains', currentUserId)
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
    let uniqueCircles = allCircles.filter((circle, index, self) => 
      index === self.findIndex(c => c.id === circle.id)
    );
    
    // Get connections to check for new activities
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', currentUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', currentUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    // Collect all recent activities from connections
    const allActivities = [];
    [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs].forEach(doc => {
      const connectionData = doc.data();
      const activities = connectionData.recentActivity || [];
      activities.forEach(activity => {
        // Only include activities where the current user hasn't viewed them
        const viewedBy = activity.viewedBy || [];
        if (!viewedBy.includes(currentUserId)) {
          allActivities.push(activity);
        }
      });
    });
    
    // Create maps for unviewed circles and places
    const unviewedCircleIds = new Set(
      allActivities
        .filter(a => a.type === 'circle')
        .map(a => a.entityId)
    );
    
    const unviewedPlacesByCircle = new Map();
    allActivities
      .filter(a => a.type === 'place' && a.circleId)
      .forEach(activity => {
        const count = unviewedPlacesByCircle.get(activity.circleId) || 0;
        unviewedPlacesByCircle.set(activity.circleId, count + 1);
      });
    
    // Mark circles with new status
    uniqueCircles = uniqueCircles.map(circle => ({
      ...circle,
      isNew: unviewedCircleIds.has(circle.id),
      hasNewPlaces: unviewedPlacesByCircle.has(circle.id),
      newPlacesCount: unviewedPlacesByCircle.get(circle.id) || 0
    }));

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
    
    // Normalize IDs for consistent comparison
    const normalizedCircleOwner = normalizeUserId(circle.owner);
    const normalizedUserId = normalizeUserId(req.user.uid);
    
    // Check permissions
    const isOwner = normalizedCircleOwner === normalizedUserId;
    const isSharedWith = (circle.sharedWith || []).some(userId => normalizeUserId(userId) === normalizedUserId);
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
    
    // For public circles, also check if user is following the circle owner
    let isFollowing = false;
    if (isPublic && !isOwner && !isSharedWith) {
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
      if (currentUserDoc.exists) {
        const userData = currentUserDoc.data();
        const following = userData.following || [];
        isFollowing = following.includes(circle.owner);
        console.log(`👀 User ${req.user.uid} is ${isFollowing ? '' : 'NOT '}following circle owner ${circle.owner}`);
      }
    }
    
    // Allow access if user is owner, shared with, public (including followers), or connected (for myNetwork)
    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to access this circle'
      });
    }
    
    // Note: Public circles are accessible to anyone, including followers
    // The isFollowing check above is just for logging/analytics purposes
    
    // Check for new places in this circle
    if (!isOwner && circle.privacy !== 'private') {
      // Get connection between current user and circle owner
      const [connectionSnapshot1, connectionSnapshot2] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', req.user.uid)
          .where('connectedUserId', '==', circle.owner)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', circle.owner)
          .where('connectedUserId', '==', req.user.uid)
          .where('status', '==', 'accepted')
          .get()
      ]);
      
      const connectionDoc = !connectionSnapshot1.empty ? connectionSnapshot1.docs[0] : 
                           (!connectionSnapshot2.empty ? connectionSnapshot2.docs[0] : null);
      
      if (connectionDoc) {
        const connectionData = connectionDoc.data();
        const activities = connectionData.recentActivity || [];
        
        // Count unviewed places in this circle
        const unviewedPlaces = activities.filter(activity => {
          const viewedBy = activity.viewedBy || [];
          return activity.type === 'place' && 
                 activity.circleId === req.params.id && 
                 !viewedBy.includes(req.user.uid);
        });
        
        circle.hasNewPlaces = unviewedPlaces.length > 0;
        circle.newPlacesCount = unviewedPlaces.length;
      }
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

// @desc    Get single circle (public access)
// @route   GET /api/circles/:id/public
// @access  Public
exports.getCirclePublic = async (req, res, next) => {
  try {
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(req.params.id).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    // Only allow access to public circles
    if (circle.privacy !== 'public') {
      return res.status(403).json({
        success: false,
        message: 'This circle is not public'
      });
    }

    // For public circles, anyone can view them
    res.status(200).json({
      success: true,
      circle: circle
    });
  } catch (error) {
    console.error('Error fetching public circle:', error);
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
    
    // Check subscription limits BEFORE validation and other checks
    const limitCheck = await subscriptionLimitService.canCreateCircle(req.user.uid);
    if (!limitCheck.canCreate) {
      return res.status(403).json({
        success: false,
        message: limitCheck.error,
        upgradeRequired: true,
        currentCount: limitCheck.currentCount,
        maxAllowed: limitCheck.maxAllowed
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

    // Check for duplicate circle name for this user
    const existingCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', req.user.uid)
      .where('name', '==', req.body.name)
      .get();
    
    if (!existingCirclesSnapshot.empty) {
      return res.status(400).json({
        success: false,
        message: 'You already have a circle with this name. Please choose a different name.'
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
    const userId = req.user.uid;  // Use uid consistently with circle creation
    
    // Normalize IDs for comparison to handle both complex and simple ID formats
    const normalizedCircleOwner = normalizeUserId(circle.owner);
    const normalizedUserId = normalizeUserId(userId);
    
    // Debug logging to help diagnose authorization issues
    console.log('🔍 Circle update authorization check:', {
      circleId: req.params.id,
      circleName: circle.name,
      circleOwner: circle.owner,
      normalizedCircleOwner: normalizedCircleOwner,
      requestingUserId: userId,
      normalizedUserId: normalizedUserId,
      requestingUserEmail: req.user.email,
      isOwnerMatch: normalizedCircleOwner === normalizedUserId
    });

    // Check if user is owner or editor (using normalized IDs)
    const isOwner = normalizedCircleOwner === normalizedUserId;
    const isEditor = (circle.editors || []).some(editorId => normalizeUserId(editorId) === normalizedUserId);
    
    if (!isOwner && !isEditor) {
      console.log('❌ Circle update authorization failed:', {
        circleId: req.params.id,
        circleOwner: circle.owner,
        normalizedCircleOwner: normalizedCircleOwner,
        requestingUserId: userId,
        normalizedUserId: normalizedUserId,
        isOwner: isOwner,
        isEditor: isEditor,
        editors: circle.editors || []
      });
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
      
      // Check for duplicate name if name is being changed
      if (req.body.name !== circle.name) {
        const existingCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
          .where('owner', '==', circle.owner)
          .where('name', '==', req.body.name)
          .get();
        
        if (!existingCirclesSnapshot.empty) {
          return res.status(400).json({
            success: false,
            message: 'You already have a circle with this name. Please choose a different name.'
          });
        }
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
    
    console.log('✅ Circle updated successfully:', {
      circleId: req.params.id,
      circleName: updatedCircle.name,
      updatedFields: Object.keys(updateData)
    });

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

    // Make sure user is circle owner (using normalized IDs)
    const normalizedCircleOwner = normalizeUserId(circle.owner);
    const normalizedUserId = normalizeUserId(req.user.uid);
    
    if (normalizedCircleOwner !== normalizedUserId) {
      console.log('❌ Circle delete authorization failed:', {
        circleId: req.params.id,
        circleOwner: circle.owner,
        normalizedCircleOwner: normalizedCircleOwner,
        requestingUserId: req.user.uid,
        normalizedUserId: normalizedUserId
      });
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this circle'
      });
    }

    // Soft delete: move the circle to the deletedCircles trash collection and
    // mark its live places deleted (deletedViaCircleDelete lets a restore
    // bring back exactly the places this deletion removed). Recoverable via
    // POST /api/trash/circles/:id/restore until permanently deleted.
    const now = new Date().toISOString();
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', req.params.id)
      .get();

    const livePlaceDocs = placesSnapshot.docs.filter(doc => doc.data().deletedAt == null);
    // Firestore batches cap at 500 ops — chunk the place updates.
    for (let i = 0; i < livePlaceDocs.length; i += 400) {
      const placeBatch = db.batch();
      livePlaceDocs.slice(i, i + 400).forEach(doc => {
        placeBatch.update(doc.ref, { deletedAt: now, deletedViaCircleDelete: true, updatedAt: now });
      });
      await placeBatch.commit();
    }

    const batch = db.batch();
    batch.set(db.collection('deletedCircles').doc(req.params.id), {
      ...circleDoc.data(),
      deletedAt: now
    });
    batch.delete(circleRef);
    await batch.commit();

    res.status(200).json({
      success: true,
      message: 'Circle moved to trash (restorable via /api/trash)',
      deletedPlaces: livePlaceDocs.length
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

    // Make sure user is circle owner (using normalized IDs)
    const normalizedCircleOwner = normalizeUserId(circle.owner);
    const normalizedUserId = normalizeUserId(req.user.uid);
    
    if (normalizedCircleOwner !== normalizedUserId) {
      console.log('❌ Circle share authorization failed:', {
        circleId: req.params.id,
        circleOwner: circle.owner,
        normalizedCircleOwner: normalizedCircleOwner,
        requestingUserId: req.user.uid,
        normalizedUserId: normalizedUserId
      });
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
    const requesterId = req.user.uid; // Use uid consistently

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

    // Check if requester is the owner (using normalized IDs)
    const normalizedCircleOwner = normalizeUserId(circle.owner);
    const normalizedRequesterId = normalizeUserId(requesterId);
    
    if (normalizedCircleOwner !== normalizedRequesterId) {
      console.log('❌ Add editor authorization failed:', {
        circleId: circleId,
        circleOwner: circle.owner,
        normalizedCircleOwner: normalizedCircleOwner,
        requesterId: requesterId,
        normalizedRequesterId: normalizedRequesterId
      });
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
    const requesterId = req.user.uid; // Use uid consistently

    // Get circle
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();

    // Check if requester is the owner (using normalized IDs)
    const normalizedCircleOwner = normalizeUserId(circle.owner);
    const normalizedRequesterId = normalizeUserId(requesterId);
    
    if (normalizedCircleOwner !== normalizedRequesterId) {
      console.log('❌ Remove editor authorization failed:', {
        circleId: circleId,
        circleOwner: circle.owner,
        normalizedCircleOwner: normalizedCircleOwner,
        requesterId: requesterId,
        normalizedRequesterId: normalizedRequesterId
      });
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
    const requesterId = req.user.uid; // Use uid consistently

    // Get circle
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();

    // Check if user has access to view editors (owner or editor) using normalized IDs
    const normalizedCircleOwner = normalizeUserId(circle.owner);
    const normalizedRequesterId = normalizeUserId(requesterId);
    const editors = circle.editors || [];
    const isOwner = normalizedCircleOwner === normalizedRequesterId;
    const isEditor = editors.some(editorId => normalizeUserId(editorId) === normalizedRequesterId);
    
    if (!isOwner && !isEditor) {
      console.log('❌ Get editors authorization failed:', {
        circleId: circleId,
        circleOwner: circle.owner,
        normalizedCircleOwner: normalizedCircleOwner,
        requesterId: requesterId,
        normalizedRequesterId: normalizedRequesterId,
        isOwner: isOwner,
        isEditor: isEditor
      });
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

// @desc    Track when a user views a circle
// @route   POST /api/circles/:id/track-view
// @access  Private
exports.trackCircleView = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const viewerUserId = req.user.firebaseDocId || req.user.uid;
    const { connectionUserId } = req.body;
    
    if (!connectionUserId) {
      return res.status(400).json({
        success: false,
        message: 'Connection user ID is required'
      });
    }
    
    // Track the view in activity service
    await trackCircleView(viewerUserId, circleId, connectionUserId);
    
    res.status(200).json({
      success: true,
      message: 'Circle view tracked'
    });
  } catch (error) {
    console.error('Error tracking circle view:', error);
    next(error);
  }
};

// @desc    Like/unlike a circle
// @route   POST /api/circles/:id/like
// @access  Private
exports.likeCircle = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const userId = req.user.uid;
    
    console.log('❤️ likeCircle called:', {
      circleId,
      userId,
      timestamp: new Date().toISOString()
    });
    
    // Get the circle
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    const currentLikes = circle.likes || [];
    const isLiked = currentLikes.includes(userId);
    
    let newLikes;
    let action;
    
    if (isLiked) {
      // Unlike - remove user from likes array
      newLikes = currentLikes.filter(id => id !== userId);
      action = 'unliked';
      console.log('👎 User unliked circle');
    } else {
      // Like - add user to likes array
      newLikes = [...currentLikes, userId];
      action = 'liked';
      console.log('👍 User liked circle');
    }
    
    // Update the circle with new likes
    await circleRef.update({
      likes: newLikes,
      likesCount: newLikes.length,
      updatedAt: new Date().toISOString()
    });
    
    console.log('✅ Circle like status updated successfully');
    
    // Track activity if circle was liked (not unliked)
    if (!isLiked) {
      await trackCircleLiked(circleId, userId, circle.owner);
    }
    
    res.status(200).json({
      success: true,
      message: `Circle ${action} successfully`,
      data: {
        circleId,
        isLiked: !isLiked,
        likesCount: newLikes.length
      }
    });
    
  } catch (error) {
    console.error('Error liking circle:', error);
    next(error);
  }
};

// @desc    Get users who liked a circle
// @route   GET /api/circles/:id/likes
// @access  Private
exports.getCircleLikes = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const userId = req.user.uid;
    
    console.log('👥 getCircleLikes called:', {
      circleId,
      userId,
      timestamp: new Date().toISOString()
    });
    
    // Get the circle
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    const likeUserIds = circle.likes || [];
    
    // Get user details for all likes
    const users = [];
    for (const likeUserId of likeUserIds) {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(likeUserId).get();
      if (userDoc.exists) {
        users.push(serializeDoc(userDoc));
      }
    }
    
    console.log(`✅ Found ${users.length} users who liked circle`);
    
    res.status(200).json({
      success: true,
      data: users
    });
    
  } catch (error) {
    console.error('Error getting circle likes:', error);
    next(error);
  }
};

// @desc    Get comments for a circle
// @route   GET /api/circles/:id/comments
// @access  Private
exports.getCircleComments = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const userId = req.user.uid;
    
    console.log('🔍 getCircleComments called:', {
      circleId,
      userId,
      timestamp: new Date().toISOString()
    });
    
    // Get the circle to check permissions
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    // Get comments for this circle (only top-level comments, not replies)
    const commentsSnapshot = await db.collection(COLLECTIONS.CIRCLE_COMMENTS)
      .where('circleId', '==', circleId)
      .where('parentCommentId', '==', null)
      .orderBy('createdAt', 'desc')
      .get();
    
    const comments = [];
    for (const commentDoc of commentsSnapshot.docs) {
      const comment = serializeDoc(commentDoc);
      
      // Get user details for each comment
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(comment.userId).get();
      if (userDoc.exists) {
        comment.user = serializeDoc(userDoc);
      }
      
      comments.push(comment);
    }
    
    console.log(`✅ Found ${comments.length} comments for circle`);
    
    res.status(200).json({
      success: true,
      data: comments
    });
    
  } catch (error) {
    console.error('Error getting circle comments:', error);
    next(error);
  }
};

// @desc    Add comment to a circle
// @route   POST /api/circles/:id/comments
// @access  Private
exports.addCircleComment = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const userId = req.user.uid;
    const { text } = req.body;
    
    console.log('💬 addCircleComment called:', {
      circleId,
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
    
    // Get the circle to check permissions and update comment count
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Create comment data
    const commentData = createCircleComment({
      circleId: circleId,
      userId: userId,
      text: text.trim()
    });
    
    console.log('💾 Saving comment to circleComments collection');
    const commentRef = await db.collection(COLLECTIONS.CIRCLE_COMMENTS).add(commentData);
    const commentDoc = await commentRef.get();
    const comment = serializeDoc(commentDoc);
    console.log('✅ Comment saved successfully with ID:', comment.id);
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      comment.user = serializeDoc(userDoc);
    }
    
    // Update circle comment count
    const currentCommentsCount = circle.commentsCount || 0;
    await circleRef.update({
      commentsCount: currentCommentsCount + 1,
      updatedAt: new Date().toISOString()
    });
    
    console.log('✅ Circle comment count updated');
    
    // Track activity for circle comment
    await trackCircleCommented(circleId, userId, circle.owner, text.trim());
    
    res.status(201).json({
      success: true,
      data: comment
    });
    
  } catch (error) {
    console.error('Error adding circle comment:', error);
    next(error);
  }
};

// @desc    Delete a comment from a circle
// @route   DELETE /api/circles/:circleId/comments/:commentId
// @access  Private (comment owner or circle owner)
exports.deleteCircleComment = async (req, res, next) => {
  try {
    const { circleId, commentId } = req.params;
    const userId = req.user.uid;
    
    // Get the comment
    const commentRef = db.collection(COLLECTIONS.CIRCLE_COMMENTS).doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = serializeDoc(commentDoc);
    
    // Get the circle
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Check permission - only comment owner or circle owner can delete (using normalized IDs)
    const normalizedCommentUserId = normalizeUserId(comment.userId);
    const normalizedCircleOwner = normalizeUserId(circle.owner);
    const normalizedUserId = normalizeUserId(userId);
    
    if (normalizedCommentUserId !== normalizedUserId && normalizedCircleOwner !== normalizedUserId) {
      console.log('❌ Delete comment authorization failed:', {
        commentId: commentId,
        commentUserId: comment.userId,
        normalizedCommentUserId: normalizedCommentUserId,
        circleOwner: circle.owner,
        normalizedCircleOwner: normalizedCircleOwner,
        requestingUserId: userId,
        normalizedUserId: normalizedUserId
      });
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this comment'
      });
    }
    
    // Delete the comment
    await commentRef.delete();
    
    // Update circle comment count
    const currentCommentsCount = circle.commentsCount || 0;
    await circleRef.update({
      commentsCount: Math.max(0, currentCommentsCount - 1),
      updatedAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: 'Comment deleted successfully'
    });
    
  } catch (error) {
    console.error('Error deleting circle comment:', error);
    next(error);
  }
};

// @desc    Add reply to a comment
// @route   POST /api/circles/:id/comments/:commentId/replies
// @access  Private
exports.addCommentReply = async (req, res, next) => {
  try {
    const { id: circleId, commentId } = req.params;
    const userId = req.user.uid;
    const { text } = req.body;
    
    console.log('💬 addCommentReply called:', {
      circleId,
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
    const parentCommentRef = db.collection(COLLECTIONS.CIRCLE_COMMENTS).doc(commentId);
    const parentCommentDoc = await parentCommentRef.get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = serializeDoc(parentCommentDoc);
    
    // Ensure the parent comment belongs to the specified circle
    if (parentComment.circleId !== circleId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this circle'
      });
    }
    
    // Create reply data
    const replyData = createCircleComment({
      circleId: circleId,
      userId: userId,
      text: text.trim(),
      parentCommentId: commentId
    });
    
    console.log('💾 Saving reply to circleComments collection');
    const replyRef = await db.collection(COLLECTIONS.CIRCLE_COMMENTS).add(replyData);
    const replyDoc = await replyRef.get();
    const reply = serializeDoc(replyDoc);
    console.log('✅ Reply saved successfully with ID:', reply.id);
    
    // Get user details for the reply
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      reply.user = serializeDoc(userDoc);
    }
    
    // Update parent comment reply count
    const currentReplyCount = parentComment.replyCount || 0;
    await parentCommentRef.update({
      replyCount: currentReplyCount + 1
    });
    
    // Update circle comment count (replies count towards total comments)
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    if (circleDoc.exists) {
      const circle = serializeDoc(circleDoc);
      const currentCommentsCount = circle.commentsCount || 0;
      await circleRef.update({
        commentsCount: currentCommentsCount + 1,
        updatedAt: new Date().toISOString()
      });
    }
    
    console.log('✅ Parent comment reply count and circle comment count updated');
    
    res.status(201).json({
      success: true,
      data: reply
    });
    
  } catch (error) {
    console.error('Error adding comment reply:', error);
    next(error);
  }
};

// @desc    Get replies for a comment
// @route   GET /api/circles/:id/comments/:commentId/replies
// @access  Private
exports.getCommentReplies = async (req, res, next) => {
  try {
    const { id: circleId, commentId } = req.params;
    const userId = req.user.uid;
    
    console.log('🔍 getCommentReplies called:', {
      circleId,
      commentId,
      userId,
      timestamp: new Date().toISOString()
    });
    
    // Verify parent comment exists and belongs to the circle
    const parentCommentRef = db.collection(COLLECTIONS.CIRCLE_COMMENTS).doc(commentId);
    const parentCommentDoc = await parentCommentRef.get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = serializeDoc(parentCommentDoc);
    
    if (parentComment.circleId !== circleId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this circle'
      });
    }
    
    // Get replies for this comment
    const repliesSnapshot = await db.collection(COLLECTIONS.CIRCLE_COMMENTS)
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
    
    res.status(200).json({
      success: true,
      data: replies
    });
    
  } catch (error) {
    console.error('Error getting comment replies:', error);
    next(error);
  }
};

// @desc    Copy a circle with all its places
// @route   POST /api/circles/:id/copy
// @access  Private
exports.copyCircle = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const sourceCircleId = req.params.id;
    
    console.log('📋 copyCircle called:', {
      userId,
      sourceCircleId,
      timestamp: new Date().toISOString()
    });
    
    // Get the source circle
    const sourceCircleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(sourceCircleId).get();
    
    if (!sourceCircleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Source circle not found'
      });
    }
    
    const sourceCircle = serializeDoc(sourceCircleDoc);
    
    // Check if user has access to the source circle
    const isOwner = sourceCircle.owner === userId;
    const isPublic = sourceCircle.privacy === 'public';
    const isSharedWith = sourceCircle.sharedWith && sourceCircle.sharedWith.includes(userId);
    
    // For myNetwork privacy, check if users are connected
    let isConnected = false;
    if (sourceCircle.privacy === 'myNetwork' && !isOwner) {
      const connection1 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', sourceCircle.owner)
        .where('status', '==', 'accepted')
        .get();
        
      const connection2 = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', sourceCircle.owner)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get();
        
      isConnected = !connection1.empty || !connection2.empty;
    }
    
    // Check if user has access to view the circle
    if (!isOwner && !isPublic && !isSharedWith && !(sourceCircle.privacy === 'myNetwork' && isConnected)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to copy this circle'
      });
    }
    
    // Create a new circle name (append "Copy" if not provided)
    const newCircleName = req.body.name || `${sourceCircle.name} (Copy)`;
    
    // Check if user already has a circle with this name
    const existingCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .where('name', '==', newCircleName)
      .get();
    
    if (!existingCirclesSnapshot.empty) {
      return res.status(400).json({
        success: false,
        message: 'You already have a circle with this name. Please choose a different name.'
      });
    }
    
    // Create new circle data
    const newCircleData = {
      name: newCircleName,
      description: sourceCircle.description || '',
      privacy: 'private', // Always start copied circles as private
      category: sourceCircle.category,
      customCategoryId: sourceCircle.customCategoryId,
      location: sourceCircle.location,
      tags: sourceCircle.tags || [],
      coverImage: sourceCircle.coverImage || null,
      allowNetworkEdit: false,
      owner: userId,
      sharedWith: [],
      followers: [],
      activeShares: [],
      places: [], // Will be populated with copied places
      placesCount: 0,
      likes: [],
      likesCount: 0,
      commentsCount: 0,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    
    // Create the new circle
    const newCircleRef = await db.collection(COLLECTIONS.CIRCLES).add(newCircleData);
    const newCircleId = newCircleRef.id;
    
    console.log('✅ Created new circle:', newCircleId);
    
    // Get all places from the source circle
    let copiedPlaceIds = [];
    if (sourceCircle.places && sourceCircle.places.length > 0) {
      // Batch get the places
      const placePromises = sourceCircle.places.map(placeId => 
        db.collection(COLLECTIONS.PLACES).doc(placeId).get()
      );
      const placeDocs = await Promise.all(placePromises);
      
      // Copy each place
      for (const placeDoc of placeDocs) {
        if (placeDoc.exists && !placeDoc.data().deletedAt) {
          const sourcePlace = serializeDoc(placeDoc);
          
          // Create new place data
          const newPlaceData = {
            name: sourcePlace.name,
            address: sourcePlace.address,
            googlePlaceId: sourcePlace.googlePlaceId,
            appleMapItemId: sourcePlace.appleMapItemId,
            category: sourcePlace.category,
            phone: sourcePlace.phone || null,
            website: sourcePlace.website || null,
            priceLevel: sourcePlace.priceLevel || null,
            rating: sourcePlace.rating || null,
            userRatingsTotal: sourcePlace.userRatingsTotal || null,
            location: sourcePlace.location,
            photos: sourcePlace.photos || [],
            userNotes: '', // Clear user notes for copied places
            circleId: newCircleId,
            userId: userId,
            addedBy: userId,
            likes: [],
            likesCount: 0,
            commentsCount: 0,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
          };
          
          // Add the new place
          const newPlaceRef = await db.collection(COLLECTIONS.PLACES).add(newPlaceData);
          copiedPlaceIds.push(newPlaceRef.id);
          
          console.log(`📍 Copied place: ${sourcePlace.name}`);
        }
      }
    }
    
    // Update the new circle with the copied place IDs
    await newCircleRef.update({
      places: copiedPlaceIds,
      placesCount: copiedPlaceIds.length,
      updatedAt: new Date().toISOString()
    });
    
    // Get the created circle with all data
    const createdCircleDoc = await newCircleRef.get();
    const createdCircle = serializeDoc(createdCircleDoc);
    
    console.log(`✅ Successfully copied circle with ${copiedPlaceIds.length} places`);
    
    res.status(201).json({
      success: true,
      message: `Successfully copied circle with ${copiedPlaceIds.length} places`,
      circle: createdCircle
    });
    
  } catch (error) {
    console.error('Error copying circle:', error);
    next(error);
  }
};