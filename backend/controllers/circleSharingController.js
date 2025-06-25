// backend/controllers/circleSharingController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createCircleShare, 
  validateCircleShare, 
  serializeDoc, 
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const crypto = require('crypto');

const db = getFirestore();

// @desc    Share a circle
// @route   POST /api/circles/:id/share
// @access  Private
const shareCircle = async (req, res) => {
  try {
    const userId = req.user.uid;
    const circleId = req.params.id;
    const { userId: targetUserId, email, shareType, accessLevel, expiresIn } = req.body;

    // Verify circle exists and user owns it
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();
    
    if (circle.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to share this circle'
      });
    }

    // Prepare share data based on share type
    let shareData = {
      circleId,
      sharedBy: userId,
      shareType,
      accessLevel: accessLevel || 'view_only'
    };

    // Set expiration if provided
    if (expiresIn && typeof expiresIn === 'number') {
      const expirationDate = new Date();
      expirationDate.setDate(expirationDate.getDate() + expiresIn);
      shareData.expiresAt = expirationDate.toISOString();
    }

    // Handle different share types
    switch (shareType) {
      case 'registered_user':
        if (!targetUserId) {
          return res.status(400).json({
            success: false,
            message: 'User ID is required for registered user shares'
          });
        }

        // Verify target user exists
        const targetUserDoc = await db.collection(COLLECTIONS.USERS).doc(targetUserId).get();
        if (!targetUserDoc.exists) {
          return res.status(404).json({
            success: false,
            message: 'Target user not found'
          });
        }

        // Check if already shared with this user
        const existingShare = await db.collection(COLLECTIONS.CIRCLE_SHARES)
          .where('circleId', '==', circleId)
          .where('sharedWith', '==', targetUserId)
          .where('shareType', '==', 'registered_user')
          .get();

        if (!existingShare.empty) {
          return res.status(409).json({
            success: false,
            message: 'Circle already shared with this user'
          });
        }

        shareData.sharedWith = targetUserId;
        break;

      case 'email':
        if (!email || !email.includes('@')) {
          return res.status(400).json({
            success: false,
            message: 'Valid email is required for email shares'
          });
        }

        shareData.sharedWith = email;
        break;

      case 'link':
        // Generate a secure share link
        const shareToken = crypto.randomBytes(32).toString('hex');
        shareData.shareLink = `https://circles-app.com/shared/${circleId}/${shareToken}`;
        break;

      default:
        return res.status(400).json({
          success: false,
          message: 'Invalid share type'
        });
    }

    // Validate share data
    const errors = validateCircleShare(shareData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors
      });
    }

    // Create the share
    const circleShareData = createCircleShare(shareData);
    const docRef = await db.collection(COLLECTIONS.CIRCLE_SHARES).add(circleShareData);
    const newDoc = await docRef.get();
    const share = serializeDoc(newDoc);

    // Update circle's activeShares array
    const currentShares = circle.activeShares || [];
    await circleDoc.ref.update({
      activeShares: [...currentShares, docRef.id],
      updatedAt: new Date().toISOString()
    });

    // Populate related data
    if (shareType === 'registered_user' && targetUserId) {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(targetUserId).get();
      if (userDoc.exists) {
        share.sharedWithUser = serializeDoc(userDoc);
      }
    }

    // Populate circle data
    share.circle = serializeDoc(circleDoc);

    res.status(201).json({
      success: true,
      data: share
    });

  } catch (error) {
    console.error('Error sharing circle:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Revoke circle share
// @route   DELETE /api/circles/:id/share/:shareId
// @access  Private
const revokeShare = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { id: circleId, shareId } = req.params;

    // Verify circle exists and user owns it
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();
    
    if (circle.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to revoke shares for this circle'
      });
    }

    // Get and verify share exists
    const shareDoc = await db.collection(COLLECTIONS.CIRCLE_SHARES).doc(shareId).get();
    
    if (!shareDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Share not found'
      });
    }

    const share = shareDoc.data();
    
    if (share.circleId !== circleId) {
      return res.status(400).json({
        success: false,
        message: 'Share does not belong to this circle'
      });
    }

    // Delete the share
    await shareDoc.ref.delete();

    // Update circle's activeShares array
    const currentShares = circle.activeShares || [];
    const updatedShares = currentShares.filter(id => id !== shareId);
    await circleDoc.ref.update({
      activeShares: updatedShares,
      updatedAt: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: 'Share revoked successfully'
    });

  } catch (error) {
    console.error('Error revoking share:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get all shares for a circle
// @route   GET /api/circles/:id/shares
// @access  Private
const getCircleShares = async (req, res) => {
  try {
    const userId = req.user.uid;
    const circleId = req.params.id;

    // Verify circle exists and user owns it
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = circleDoc.data();
    
    if (circle.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view shares for this circle'
      });
    }

    // Get all shares for this circle
    const sharesQuery = await db.collection(COLLECTIONS.CIRCLE_SHARES)
      .where('circleId', '==', circleId)
      .orderBy('createdAt', 'desc')
      .get();

    // Serialize and populate user data
    const shares = await Promise.all(
      sharesQuery.docs.map(async (doc) => {
        const share = serializeDoc(doc);
        
        // Populate shared with user data if it's a registered user
        if (share.shareType === 'registered_user' && share.sharedWith) {
          try {
            const userDoc = await db.collection(COLLECTIONS.USERS).doc(share.sharedWith).get();
            if (userDoc.exists) {
              share.sharedWithUser = serializeDoc(userDoc);
            }
          } catch (error) {
            console.error(`Error fetching user ${share.sharedWith}:`, error);
          }
        }

        return share;
      })
    );

    res.status(200).json({
      success: true,
      data: shares
    });

  } catch (error) {
    console.error('Error fetching circle shares:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get all shared circles for user
// @route   GET /api/network/shared-circles
// @access  Private
const getSharedCircles = async (req, res) => {
  try {
    const userId = req.user.uid;

    // Get all shares created by this user
    const sharesQuery = await db.collection(COLLECTIONS.CIRCLE_SHARES)
      .where('sharedBy', '==', userId)
      .orderBy('createdAt', 'desc')
      .get();

    // Group shares by circle
    const sharesByCircle = {};
    const circleIds = new Set();

    sharesQuery.docs.forEach(doc => {
      const share = serializeDoc(doc);
      const circleId = share.circleId;
      
      if (!sharesByCircle[circleId]) {
        sharesByCircle[circleId] = [];
      }
      sharesByCircle[circleId].push(share);
      circleIds.add(circleId);
    });

    // Fetch circle details
    const circlePromises = Array.from(circleIds).map(id => 
      db.collection(COLLECTIONS.CIRCLES).doc(id).get()
    );
    
    const circleDocs = await Promise.all(circlePromises);
    
    // Build response with share data
    const result = circleDocs
      .filter(doc => doc.exists)
      .map(doc => {
        const circle = serializeDoc(doc);
        circle.activeShares = sharesByCircle[circle._id] || [];
        return circle;
      });

    res.status(200).json({
      success: true,
      data: result
    });

  } catch (error) {
    console.error('Error fetching shared circles:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Update share access time (for analytics)
// @route   POST /api/circles/share/:shareId/access
// @access  Public (for shared links)
const updateShareAccess = async (req, res) => {
  try {
    const { shareId } = req.params;

    const shareDoc = await db.collection(COLLECTIONS.CIRCLE_SHARES).doc(shareId).get();
    
    if (!shareDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Share not found'
      });
    }

    const share = shareDoc.data();
    
    // Check if share is expired
    if (share.expiresAt && new Date(share.expiresAt) < new Date()) {
      return res.status(410).json({
        success: false,
        message: 'Share has expired'
      });
    }

    // Update last accessed time
    await shareDoc.ref.update({
      lastAccessedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });

    res.status(200).json({
      success: true,
      message: 'Access recorded'
    });

  } catch (error) {
    console.error('Error updating share access:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

module.exports = {
  shareCircle,
  revokeShare,
  getCircleShares,
  getSharedCircles,
  updateShareAccess
};