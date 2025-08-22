// backend/controllers/circleController.js
const Circle = require('../models/Circle');
const User = require('../models/User');
const Place = require('../models/Place');
const { storage } = require('../config/firebase');

// Helper function to serialize circle data for iOS
const serializeCircle = (circle) => {
  return {
    _id: circle._id.toString(),
    name: circle.name,
    description: circle.description || null,
    coverImage: circle.coverImage || null,
    owner: circle.owner.toString(),
    places: circle.places.map(place => place.toString()),
    privacy: circle.privacy,
    category: circle.category,
    location: circle.location || null,
    tags: circle.tags || [],
    sharedWith: circle.sharedWith.map(user => user.toString()),
    followers: circle.followers.map(user => user.toString()),
    createdAt: circle.createdAt.toISOString(),
    updatedAt: circle.updatedAt.toISOString()
  };
};

// @desc    Get all circles for current user
// @route   GET /api/circles
// @access  Private
exports.getMyCircles = async (req, res, next) => {
  try {
    const circles = await Circle.find({ owner: req.user.id })
      .populate('places', 'name address location photos category rating')
      .sort('-createdAt');

    res.status(200).json({
      success: true,
      count: circles.length,
      circles: circles.map(circle => serializeCircle(circle))
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Get circles shared with me
// @route   GET /api/circles/shared
// @access  Private
exports.getSharedCircles = async (req, res, next) => {
  try {
    // Find circles where I'm in the sharedWith array or the circle is public
    // Or circles from my friends that are set to 'friends' privacy
    const friendIds = req.user.friends.map(friend => friend.toString());
    
    const circles = await Circle.find({
      $or: [
        { sharedWith: req.user.id },
        { privacy: 'public' },
        { owner: { $in: friendIds }, privacy: 'friends' }
      ],
      owner: { $ne: req.user.id } // Not my own circles
    })
      .populate('owner', 'displayName profilePicture')
      .populate('places', 'name address location photos category rating')
      .sort('-updatedAt');

    res.status(200).json({
      success: true,
      count: circles.length,
      circles: circles.map(circle => serializeCircle(circle))
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Get single circle
// @route   GET /api/circles/:id
// @access  Private
exports.getCircle = async (req, res, next) => {
  try {
    const circle = await Circle.findById(req.params.id)
      .populate('owner', 'displayName profilePicture')
      .populate('places')
      .populate('followers', 'displayName profilePicture')
      .populate('sharedWith', 'displayName profilePicture');

    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    // Check permissions
    const isOwner = circle.owner._id.toString() === req.user.id;
    const isSharedWith = circle.sharedWith.some(user => user._id.toString() === req.user.id);
    const isFriend = req.user.friends.includes(circle.owner._id.toString());
    const isPublic = circle.privacy === 'public';
    const isFriendPrivacy = circle.privacy === 'friends' && isFriend;

    if (!isOwner && !isSharedWith && !isPublic && !isFriendPrivacy) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to access this circle'
      });
    }

    res.status(200).json({
      success: true,
      circle: serializeCircle(circle)
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Create new circle
// @route   POST /api/circles
// @access  Private
exports.createCircle = async (req, res, next) => {
  try {
    // Add owner to request body
    req.body.owner = req.user.id;

    const circle = await Circle.create(req.body);

    res.status(201).json({
      success: true,
      circle: serializeCircle(circle)
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Update circle
// @route   PUT /api/circles/:id
// @access  Private
exports.updateCircle = async (req, res, next) => {
  try {
    let circle = await Circle.findById(req.params.id);

    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    // Make sure user is circle owner
    if (circle.owner.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to update this circle'
      });
    }

    // Don't allow ownership transfer
    const { owner, ...updateData } = req.body;

    circle = await Circle.findByIdAndUpdate(req.params.id, updateData, {
      new: true,
      runValidators: true
    });

    res.status(200).json({
      success: true,
      circle: serializeCircle(circle)
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Upload circle cover image
// @route   POST /api/circles/:id/upload-cover
// @access  Private
exports.uploadCoverImage = async (req, res, next) => {
  try {
    const circle = await Circle.findById(req.params.id);

    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    // Make sure user is circle owner
    if (circle.owner.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to update this circle'
      });
    }

    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: 'Please upload a file'
      });
    }

    // Upload to Firebase Storage
    const bucket = storage.bucket();
    const fileName = `circle-covers/${circle._id}-${Date.now()}-${req.file.originalname}`;
    
    const fileUpload = bucket.file(fileName);
    
    const blobStream = fileUpload.createWriteStream({
      metadata: {
        contentType: req.file.mimetype
      }
    });

    blobStream.on('error', (error) => {
      next(error);
    });

    blobStream.on('finish', async () => {
      // Make the file public
      await fileUpload.makePublic();
      
      // Get the public URL
      const publicUrl = `https://storage.googleapis.com/${bucket.name}/${fileUpload.name}`;
      
      // Update circle
      circle.coverImage = publicUrl;
      await circle.save();

      res.status(200).json({
        success: true,
        circle: serializeCircle(circle)
      });
    });

    blobStream.end(req.file.buffer);
  } catch (error) {
    next(error);
  }
};

// @desc    Delete circle
// @route   DELETE /api/circles/:id
// @access  Private
exports.deleteCircle = async (req, res, next) => {
  try {
    const circle = await Circle.findById(req.params.id);

    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    // Make sure user is circle owner
    if (circle.owner.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to delete this circle'
      });
    }

    // Remove circle reference from all places
    await Place.updateMany(
      { circles: circle._id },
      { $pull: { circles: circle._id } }
    );

    await circle.deleteOne();

    res.status(200).json({
      success: true,
      data: {}
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Share circle with specific users
// @route   POST /api/circles/:id/share
// @access  Private
exports.shareCircle = async (req, res, next) => {
  try {
    const { userIds } = req.body;
    
    if (!userIds || !Array.isArray(userIds)) {
      return res.status(400).json({
        success: false,
        message: 'Please provide an array of user IDs'
      });
    }

    const circle = await Circle.findById(req.params.id);

    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    // Make sure user is circle owner
    if (circle.owner.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to share this circle'
      });
    }

    // Validate users exist
    const users = await User.find({ _id: { $in: userIds } });
    
    if (users.length !== userIds.length) {
      return res.status(404).json({
        success: false,
        message: 'One or more users not found'
      });
    }

    // Add users to sharedWith (avoid duplicates)
    const newSharedWith = [...new Set([
      ...circle.sharedWith.map(id => id.toString()),
      ...userIds
    ])];
    
    circle.sharedWith = newSharedWith;
    await circle.save();

    res.status(200).json({
      success: true,
      circle: circle
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Follow a circle
// @route   POST /api/circles/:id/follow
// @access  Private
exports.followCircle = async (req, res, next) => {
  try {
    const circle = await Circle.findById(req.params.id);

    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    // Check permission to follow
    const isOwner = circle.owner.toString() === req.user.id;
    const isSharedWith = circle.sharedWith.includes(req.user.id);
    const isFriend = req.user.friends.includes(circle.owner.toString());
    const isPublic = circle.privacy === 'public';
    const isFriendPrivacy = circle.privacy === 'friends' && isFriend;

    if (!isPublic && !isFriendPrivacy && !isSharedWith && !isOwner) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to follow this circle'
      });
    }

    // Check if already following
    if (circle.followers.includes(req.user.id)) {
      return res.status(400).json({
        success: false,
        message: 'Already following this circle'
      });
    }

    // Add to followers
    circle.followers.push(req.user.id);
    await circle.save();

    res.status(200).json({
      success: true,
      message: 'Now following circle'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Unfollow a circle
// @route   POST /api/circles/:id/unfollow
// @access  Private
exports.unfollowCircle = async (req, res, next) => {
  try {
    const circle = await Circle.findById(req.params.id);

    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    // Check if following
    if (!circle.followers.includes(req.user.id)) {
      return res.status(400).json({
        success: false,
        message: 'Not following this circle'
      });
    }

    // Remove from followers
    circle.followers = circle.followers.filter(
      id => id.toString() !== req.user.id
    );
    
    await circle.save();

    res.status(200).json({
      success: true,
      message: 'Unfollowed circle'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Mark circle as viewed by user (clears new indicators)
// @route   POST /api/circles/:id/mark-viewed
// @access  Private
exports.markCircleAsViewed = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    const userId = req.user.id;
    
    // Get the circle
    const circle = await Circle.findById(circleId);
    
    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    // Check if user has access to view this circle
    const hasAccess = 
      circle.owner.toString() === userId ||
      circle.sharedWith?.includes(userId) ||
      circle.privacy === 'public' ||
      (circle.privacy === 'myNetwork' && req.user.connections?.includes(circle.owner.toString()));
    
    if (!hasAccess) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to view this circle'
      });
    }
    
    // Update or create user's view record for this circle
    const now = new Date();
    
    // Store the last viewed timestamp in a separate collection
    // For Firestore implementation, we would use:
    const { getFirestore } = require('../config/firebase');
    const db = getFirestore();
    
    await db.collection('circle_views').doc(`${userId}_${circleId}`).set({
      userId,
      circleId,
      lastViewedAt: now.toISOString(),
      updatedAt: now.toISOString()
    }, { merge: true });
    
    // Clear hasNewPlaces flag for this circle for this user
    // This would typically be calculated when fetching circles based on lastViewedAt
    
    res.status(200).json({
      success: true,
      message: 'Circle marked as viewed',
      data: {
        circleId,
        lastViewedAt: now.toISOString()
      }
    });
  } catch (error) {
    next(error);
  }
};