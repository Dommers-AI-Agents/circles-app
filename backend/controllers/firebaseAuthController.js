// backend/controllers/firebaseAuthController.js
const { getFirestore, getAuth } = require('../config/firebase');
const { COLLECTIONS, createUser, serializeDoc } = require('../models/FirestoreModels');
const jwt = require('jsonwebtoken');

const db = getFirestore();
const auth = getAuth();

// @desc    Firebase authentication (Google Sign-In from iOS)
// @route   POST /api/auth/firebase
// @access  Public
exports.firebaseAuth = async (req, res, next) => {
  try {
    const { idToken } = req.body;

    if (!idToken) {
      return res.status(400).json({
        success: false,
        message: 'ID token is required'
      });
    }

    let decodedToken;
    let uid, email, name, picture;

    // Try Firebase ID token first
    try {
      decodedToken = await auth.verifyIdToken(idToken);
      uid = decodedToken.uid;
      email = decodedToken.email;
      name = decodedToken.name;
      picture = decodedToken.picture;
      console.log('✅ Firebase ID token verified successfully');
    } catch (firebaseError) {
      console.log('⚠️ Firebase token failed, trying Google OAuth token...');
      
      // Fallback: Try to verify as Google OAuth token
      try {
        // Verify Google OAuth token directly
        const response = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${idToken}`);
        const tokenInfo = await response.json();
        
        if (response.ok && tokenInfo.aud) {
          // Valid Google OAuth token
          uid = tokenInfo.sub; // Google user ID
          email = tokenInfo.email;
          name = tokenInfo.name;
          picture = tokenInfo.picture;
          console.log('✅ Google OAuth token verified successfully');
        } else {
          throw new Error('Invalid Google token');
        }
      } catch (googleError) {
        console.error('Both Firebase and Google token verification failed:');
        console.error('Firebase error:', firebaseError.message);
        console.error('Google error:', googleError.message);
        return res.status(401).json({
          success: false,
          message: 'Invalid authentication token'
        });
      }
    }

    // Check if user exists in Firestore
    const userRef = db.collection(COLLECTIONS.USERS).doc(uid);
    const userDoc = await userRef.get();

    let user;
    if (userDoc.exists) {
      // Existing user - update last login
      await userRef.update({
        updatedAt: new Date().toISOString()
      });
      user = serializeDoc(userDoc);
    } else {
      // New user - create profile
      const userData = createUser({
        uid,
        email,
        displayName: name,
        profilePicture: picture
      });
      
      await userRef.set(userData);
      user = { id: uid, ...userData };
    }

    // Create JWT token for API access
    const token = jwt.sign(
      { 
        uid: user.id || user.uid,
        email: user.email 
      },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRE }
    );

    const response = {
      success: true,
      token,
      refreshToken: token, // For now, use same token as refresh token
      user: {
        _id: user.id || user.uid, // iOS expects _id, not id
        email: user.email || '',
        displayName: user.displayName || name || 'Unknown User',
        profilePicture: user.profilePicture || picture || null,
        bio: user.bio || null,
        location: user.location || null,
        friends: user.friends || [],
        friendRequests: user.friendRequests || [],
        createdAt: user.createdAt || new Date().toISOString()
      }
    };

    console.log('📤 Sending auth response:', JSON.stringify(response, null, 2));

    res.status(200).json(response);
  } catch (error) {
    console.error('Firebase auth error:', error);
    next(error);
  }
};

// @desc    Get current user profile
// @route   GET /api/auth/me
// @access  Private
exports.getMe = async (req, res, next) => {
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

    res.status(200).json({
      success: true,
      user: {
        _id: user.id,
        email: user.email,
        displayName: user.displayName,
        profilePicture: user.profilePicture,
        bio: user.bio,
        location: user.location,
        friends: user.friends,
        createdAt: user.createdAt
      }
    });
  } catch (error) {
    console.error('Get user profile error:', error);
    next(error);
  }
};

// @desc    Update user profile
// @route   PUT /api/auth/me
// @access  Private
exports.updateProfile = async (req, res, next) => {
  try {
    const { displayName, bio, location, profilePicture } = req.body;
    
    const updateData = {
      updatedAt: new Date().toISOString()
    };

    if (displayName !== undefined) updateData.displayName = displayName;
    if (bio !== undefined) updateData.bio = bio;
    if (location !== undefined) updateData.location = location;
    if (profilePicture !== undefined) updateData.profilePicture = profilePicture;

    const userRef = db.collection(COLLECTIONS.USERS).doc(req.user.uid);
    await userRef.update(updateData);

    // Get updated user
    const updatedUserDoc = await userRef.get();
    const user = serializeDoc(updatedUserDoc);

    res.status(200).json({
      success: true,
      user: {
        _id: user.id,
        email: user.email,
        displayName: user.displayName,
        profilePicture: user.profilePicture,
        bio: user.bio,
        location: user.location,
        createdAt: user.createdAt
      }
    });
  } catch (error) {
    console.error('Update profile error:', error);
    next(error);
  }
};

// @desc    Refresh JWT token
// @route   POST /api/auth/refresh-token
// @access  Public
exports.refreshToken = async (req, res, next) => {
  try {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      return res.status(400).json({
        success: false,
        message: 'Refresh token is required'
      });
    }

    // Verify the refresh token
    let decoded;
    try {
      decoded = jwt.verify(refreshToken, process.env.JWT_SECRET);
    } catch (error) {
      return res.status(401).json({
        success: false,
        message: 'Invalid refresh token'
      });
    }

    // Check if user still exists
    const userRef = db.collection(COLLECTIONS.USERS).doc(decoded.uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      return res.status(401).json({
        success: false,
        message: 'User no longer exists'
      });
    }

    // Create new JWT token
    const token = jwt.sign(
      { 
        uid: decoded.uid,
        email: decoded.email 
      },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRE }
    );

    res.status(200).json({
      success: true,
      token
    });
  } catch (error) {
    console.error('Refresh token error:', error);
    next(error);
  }
};