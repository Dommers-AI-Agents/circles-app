// backend/controllers/users/pinnedPlacesController.js
// pinned (quick-access) places
// Split out of firebaseUserController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');

const db = getFirestore();

// @desc    Add place to pinned places
// @route   POST /api/users/me/pinned-places
// @access  Private
exports.addPinnedPlace = async (req, res, next) => {
  try {
    const { placeId } = req.body;
    
    if (!placeId) {
      return res.status(400).json({
        success: false,
        message: 'Place ID is required'
      });
    }

    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = serializeDoc(userDoc);
    const pinnedPlaces = user.pinnedPlaces || [];
    
    // Check if place is already pinned
    if (pinnedPlaces.includes(placeId)) {
      return res.status(400).json({
        success: false,
        message: 'Place is already pinned'
      });
    }
    
    // Check max limit (6 pinned places)
    if (pinnedPlaces.length >= 6) {
      return res.status(400).json({
        success: false,
        message: 'Maximum 6 places can be pinned'
      });
    }
    
    // Verify place exists and user has access to it
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check if user has access to this place (owns it or it's in their network)
    if (place.addedBy !== req.user.uid) {
      // Could add additional access checks here for network visibility
      // For now, only allow pinning own places
      return res.status(403).json({
        success: false,
        message: 'You can only pin places you have added'
      });
    }
    
    // Add to pinned places
    pinnedPlaces.push(placeId);
    
    await userRef.update({
      pinnedPlaces: pinnedPlaces,
      updatedAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: 'Place pinned successfully',
      pinnedPlaces: pinnedPlaces
    });
    
  } catch (error) {
    console.error('Error adding pinned place:', error);
    next(error);
  }
};

// @desc    Remove place from pinned places
// @route   DELETE /api/users/me/pinned-places/:placeId
// @access  Private
exports.removePinnedPlace = async (req, res, next) => {
  try {
    const { placeId } = req.params;
    
    if (!placeId) {
      return res.status(400).json({
        success: false,
        message: 'Place ID is required'
      });
    }

    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = serializeDoc(userDoc);
    const pinnedPlaces = user.pinnedPlaces || [];
    
    // Check if place is pinned
    if (!pinnedPlaces.includes(placeId)) {
      return res.status(400).json({
        success: false,
        message: 'Place is not pinned'
      });
    }
    
    // Remove from pinned places
    const updatedPinnedPlaces = pinnedPlaces.filter(id => id !== placeId);
    
    await userRef.update({
      pinnedPlaces: updatedPinnedPlaces,
      updatedAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: 'Place unpinned successfully',
      pinnedPlaces: updatedPinnedPlaces
    });
    
  } catch (error) {
    console.error('Error removing pinned place:', error);
    next(error);
  }
};

// @desc    Get user's pinned places with details
// @route   GET /api/users/me/pinned-places
// @access  Private
exports.getPinnedPlaces = async (req, res, next) => {
  try {
    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = serializeDoc(userDoc);
    const pinnedPlaceIds = user.pinnedPlaces || [];
    
    if (pinnedPlaceIds.length === 0) {
      return res.status(200).json({
        success: true,
        pinnedPlaces: []
      });
    }
    
    // Fetch place details
    const pinnedPlaces = [];
    for (const placeId of pinnedPlaceIds) {
      const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      if (placeDoc.exists) {
        const place = serializeDoc(placeDoc);
        pinnedPlaces.push(place);
      }
    }
    
    res.status(200).json({
      success: true,
      count: pinnedPlaces.length,
      pinnedPlaces: pinnedPlaces
    });
    
  } catch (error) {
    console.error('Error fetching pinned places:', error);
    next(error);
  }
};

// @desc    Reorder pinned places
// @route   PUT /api/users/me/pinned-places/reorder
// @access  Private
exports.reorderPinnedPlaces = async (req, res, next) => {
  try {
    const { pinnedPlaces } = req.body;
    
    if (!Array.isArray(pinnedPlaces)) {
      return res.status(400).json({
        success: false,
        message: 'pinnedPlaces must be an array'
      });
    }
    
    if (pinnedPlaces.length > 6) {
      return res.status(400).json({
        success: false,
        message: 'Maximum 6 places can be pinned'
      });
    }

    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = serializeDoc(userDoc);
    const currentPinnedPlaces = user.pinnedPlaces || [];
    
    // Validate that all provided place IDs are currently pinned
    for (const placeId of pinnedPlaces) {
      if (!currentPinnedPlaces.includes(placeId)) {
        return res.status(400).json({
          success: false,
          message: `Place ${placeId} is not currently pinned`
        });
      }
    }
    
    // Update the order
    await userRef.update({
      pinnedPlaces: pinnedPlaces,
      updatedAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: 'Pinned places reordered successfully',
      pinnedPlaces: pinnedPlaces
    });
    
  } catch (error) {
    console.error('Error reordering pinned places:', error);
    next(error);
  }
};
