// backend/controllers/userController.js
const User = require('../models/User');
const Circle = require('../models/Circle');
const { storage } = require('../config/firebase');

// @desc    Get all users
// @route   GET /api/users
// @access  Private
exports.getUsers = async (req, res, next) => {
  try {
    const users = await User.find();

    res.status(200).json({
      success: true,
      count: users.length,
      data: users
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Get single user
// @route   GET /api/users/:id
// @access  Private
exports.getUser = async (req, res, next) => {
  try {
    console.log('🔍 getUser called with ID:', req.params.id);
    const user = await User.findById(req.params.id);

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    res.status(200).json({
      success: true,
      user: user
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Update user
// @route   PUT /api/users/:id
// @access  Private
exports.updateUser = async (req, res, next) => {
  try {
    // Make sure user is updating their own profile
    if (req.params.id !== req.user.id.toString()) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to update this user'
      });
    }

    // Don't allow email updates here
    const { email, password, ...updateData } = req.body;

    const user = await User.findByIdAndUpdate(req.params.id, updateData, {
      new: true,
      runValidators: true
    });

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    res.status(200).json({
      success: true,
      user: user
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Upload profile picture
// @route   POST /api/users/:id/upload-profile-picture
// @access  Private
exports.uploadProfilePicture = async (req, res, next) => {
  try {
    // Make sure user is updating their own profile
    if (req.params.id !== req.user.id.toString()) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to update this user'
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
    const fileName = `profile-pictures/${req.user.id}-${Date.now()}-${req.file.originalname}`;
    
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
      
      // Update user profile
      const user = await User.findByIdAndUpdate(
        req.params.id,
        { profilePicture: publicUrl },
        { new: true }
      );

      res.status(200).json({
        success: true,
        data: user
      });
    });

    blobStream.end(req.file.buffer);
  } catch (error) {
    next(error);
  }
};

// @desc    Get user's friends
// @route   GET /api/users/:id/friends
// @access  Private
exports.getUserFriends = async (req, res, next) => {
  try {
    const user = await User.findById(req.params.id).populate('friends', 'displayName email profilePicture');

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    res.status(200).json({
      success: true,
      count: user.friends.length,
      data: user.friends
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Send friend request
// @route   POST /api/users/:id/friend-request
// @access  Private
exports.sendFriendRequest = async (req, res, next) => {
  try {
    // Cannot send request to yourself
    if (req.params.id === req.user.id.toString()) {
      return res.status(400).json({
        success: false,
        message: 'Cannot send friend request to yourself'
      });
    }

    const targetUser = await User.findById(req.params.id);

    if (!targetUser) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Check if already friends
    if (targetUser.friends.includes(req.user.id)) {
      return res.status(400).json({
        success: false,
        message: 'Already friends with this user'
      });
    }

    // Check if friend request already sent
    if (targetUser.friendRequests.includes(req.user.id)) {
      return res.status(400).json({
        success: false,
        message: 'Friend request already sent'
      });
    }

    // Add to friend requests
    targetUser.friendRequests.push(req.user.id);
    await targetUser.save();

    res.status(200).json({
      success: true,
      message: 'Friend request sent'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Accept friend request
// @route   POST /api/users/:id/accept-friend
// @access  Private
exports.acceptFriendRequest = async (req, res, next) => {
  try {
    const senderId = req.params.id;
    
    // Check if request exists
    if (!req.user.friendRequests.includes(senderId)) {
      return res.status(400).json({
        success: false,
        message: 'No friend request from this user'
      });
    }

    const sender = await User.findById(senderId);

    if (!sender) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Add each other as friends
    req.user.friends.push(senderId);
    sender.friends.push(req.user.id);

    // Remove from friend requests
    req.user.friendRequests = req.user.friendRequests.filter(
      id => id.toString() !== senderId
    );

    await req.user.save();
    await sender.save();

    res.status(200).json({
      success: true,
      message: 'Friend request accepted'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Reject friend request
// @route   POST /api/users/:id/reject-friend
// @access  Private
exports.rejectFriendRequest = async (req, res, next) => {
  try {
    const senderId = req.params.id;
    
    // Check if request exists
    if (!req.user.friendRequests.includes(senderId)) {
      return res.status(400).json({
        success: false,
        message: 'No friend request from this user'
      });
    }

    // Remove from friend requests
    req.user.friendRequests = req.user.friendRequests.filter(
      id => id.toString() !== senderId
    );

    await req.user.save();

    res.status(200).json({
      success: true,
      message: 'Friend request rejected'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Remove friend
// @route   DELETE /api/users/:id/remove-friend
// @access  Private
exports.removeFriend = async (req, res, next) => {
  try {
    const friendId = req.params.id;
    
    // Check if actually friends
    if (!req.user.friends.includes(friendId)) {
      return res.status(400).json({
        success: false,
        message: 'Not friends with this user'
      });
    }

    const friend = await User.findById(friendId);

    if (!friend) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Remove each other from friends list
    req.user.friends = req.user.friends.filter(
      id => id.toString() !== friendId
    );
    
    friend.friends = friend.friends.filter(
      id => id.toString() !== req.user.id.toString()
    );

    await req.user.save();
    await friend.save();

    res.status(200).json({
      success: true,
      message: 'Friend removed'
    });
  } catch (error) {
    next(error);
  }
};
