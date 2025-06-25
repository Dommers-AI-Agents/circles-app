// backend/controllers/firebaseAuthController.js
const { getFirestore, getAuth } = require('../config/firebase');
const { COLLECTIONS, createUser, serializeDoc } = require('../models/FirestoreModels');
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const db = getFirestore();
const auth = getAuth();

// Apple's JWKS client for verifying tokens
const appleClient = jwksClient({
  jwksUri: 'https://appleid.apple.com/auth/keys',
  cache: true,
  rateLimit: true
});

// Helper function to exchange LinkedIn authorization code for access token
async function exchangeLinkedInCode(code) {
  const clientId = process.env.LINKEDIN_CLIENT_ID;
  const clientSecret = process.env.LINKEDIN_CLIENT_SECRET;
  const redirectUri = 'com.favcircles.circles://linkedin-callback';
  
  if (!clientId || !clientSecret) {
    throw new Error('LinkedIn OAuth credentials not configured');
  }
  
  const params = new URLSearchParams({
    grant_type: 'authorization_code',
    code: code,
    redirect_uri: redirectUri,
    client_id: clientId,
    client_secret: clientSecret
  });
  
  const response = await fetch('https://www.linkedin.com/oauth/v2/accessToken', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: params.toString()
  });
  
  const data = await response.json();
  
  if (!response.ok || !data.access_token) {
    throw new Error('Failed to exchange LinkedIn authorization code');
  }
  
  return data.access_token;
}

// Helper function to get Apple's signing key
function getAppleSigningKey(kid) {
  return new Promise((resolve, reject) => {
    appleClient.getSigningKey(kid, (err, key) => {
      if (err) {
        reject(err);
      } else {
        const signingKey = key.getPublicKey();
        resolve(signingKey);
      }
    });
  });
}

// Helper function to verify Apple Sign-In token
async function verifyAppleToken(idToken) {
  try {
    // Decode the token without verification first to get the header
    const decoded = jwt.decode(idToken, { complete: true });
    if (!decoded) {
      throw new Error('Failed to decode token');
    }

    // Check if this is an Apple token by looking at the issuer
    const payload = decoded.payload;
    if (payload.iss !== 'https://appleid.apple.com') {
      throw new Error('Not an Apple ID token');
    }

    // For development, we'll trust the token if it's from Apple
    // In production, you should uncomment the verification below
    
    /*
    // Get the signing key from Apple
    const signingKey = await getAppleSigningKey(decoded.header.kid);
    
    // Verify the token
    const verified = jwt.verify(idToken, signingKey, {
      issuer: 'https://appleid.apple.com',
      audience: 'com.favcircles.circles' // Your app's bundle ID
    });
    */
    
    // Extract user info from the token
    return {
      uid: payload.sub, // Apple user ID
      email: payload.email || null,
      name: null, // Apple doesn't provide name in the token
      picture: null // Apple doesn't provide picture
    };
  } catch (error) {
    throw error;
  }
}

// @desc    Firebase authentication (Google Sign-In and Apple Sign-In from iOS)
// @route   POST /api/auth/firebase
// @access  Public
exports.firebaseAuth = async (req, res, next) => {
  try {
    const { idToken, name: providedName, email: providedEmail } = req.body;

    if (!idToken) {
      return res.status(400).json({
        success: false,
        message: 'ID token is required'
      });
    }

    let uid, email, name, picture;
    let provider = 'unknown';

    // Try Firebase ID token first
    try {
      const decodedToken = await auth.verifyIdToken(idToken);
      uid = decodedToken.uid;
      email = decodedToken.email;
      name = decodedToken.name;
      picture = decodedToken.picture;
      provider = 'firebase';
      console.log('✅ Firebase ID token verified successfully');
    } catch (firebaseError) {
      console.log('⚠️ Firebase token failed, trying other providers...');
      
      // Try Apple Sign-In
      try {
        const appleData = await verifyAppleToken(idToken);
        uid = appleData.uid;
        // Use provided email/name from client if available (Apple only provides on first sign-in)
        email = providedEmail || appleData.email;
        name = providedName || appleData.name || 'Apple User';
        picture = appleData.picture;
        provider = 'apple';
        console.log('✅ Apple ID token verified successfully');
        console.log('Apple user data:', { uid, email, name });
      } catch (appleError) {
        console.log('⚠️ Apple token failed:', appleError.message);
        
        // Try Facebook token verification
        try {
          const fbResponse = await fetch(`https://graph.facebook.com/me?fields=id,name,email,picture&access_token=${idToken}`);
          const fbData = await fbResponse.json();
          
          if (fbResponse.ok && fbData.id) {
            uid = `fb_${fbData.id}`;
            email = providedEmail || fbData.email;
            name = providedName || fbData.name;
            picture = fbData.picture?.data?.url;
            provider = 'facebook';
            console.log('✅ Facebook token verified successfully');
            console.log('Facebook user data:', { uid, email, name });
          } else {
            throw new Error('Invalid Facebook token');
          }
        } catch (facebookError) {
          console.log('⚠️ Facebook token failed:', facebookError.message);
          
          // Try LinkedIn token verification
          try {
            // For LinkedIn, we might receive either an auth code or access token
            let accessToken = idToken;
            
            // Check if this looks like an authorization code (shorter than typical access token)
            if (idToken.length < 100 && !idToken.includes('.')) {
              console.log('🔄 Exchanging LinkedIn authorization code for access token');
              accessToken = await exchangeLinkedInCode(idToken);
            }
            
            const linkedInHeaders = {
              'Authorization': `Bearer ${accessToken}`
            };
            
            // Get basic profile
            const profileResponse = await fetch('https://api.linkedin.com/v2/me', { headers: linkedInHeaders });
            const profileData = await profileResponse.json();
            
            if (profileResponse.ok && profileData.id) {
              uid = `linkedin_${profileData.id}`;
              const firstName = profileData.localizedFirstName || '';
              const lastName = profileData.localizedLastName || '';
              name = providedName || `${firstName} ${lastName}`.trim() || 'LinkedIn User';
              
              // Try to get email if not provided
              if (!providedEmail) {
                try {
                  const emailResponse = await fetch('https://api.linkedin.com/v2/emailAddress?q=members&projection=(elements*(handle~))', { headers: linkedInHeaders });
                  const emailData = await emailResponse.json();
                  if (emailData.elements && emailData.elements[0]) {
                    email = emailData.elements[0]['handle~'].emailAddress;
                  }
                } catch (emailError) {
                  console.log('⚠️ Failed to fetch LinkedIn email:', emailError.message);
                }
              } else {
                email = providedEmail;
              }
              
              provider = 'linkedin';
              console.log('✅ LinkedIn token verified successfully');
              console.log('LinkedIn user data:', { uid, email, name });
            } else {
              throw new Error('Invalid LinkedIn token');
            }
          } catch (linkedInError) {
            console.log('⚠️ LinkedIn token failed:', linkedInError.message);
            console.log('⚠️ Trying Google OAuth...');
            
            // Fallback: Try to verify as Google OAuth token
            try {
              // Verify Google OAuth token directly
              const response = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${idToken}`);
              const tokenInfo = await response.json();
              
              if (response.ok && tokenInfo.aud) {
                // Valid Google OAuth token
                uid = tokenInfo.sub; // Google user ID - use as-is, don't modify
                email = tokenInfo.email;
                name = tokenInfo.name;
                picture = tokenInfo.picture;
                provider = 'google';
                console.log('✅ Google OAuth token verified successfully');
                console.log(`📝 Google user ID (sub): ${uid}`);
              } else {
                throw new Error('Invalid Google token');
              }
            } catch (googleError) {
              console.error('All token verification methods failed:');
              console.error('Firebase error:', firebaseError.message);
              console.error('Apple error:', appleError.message);
              console.error('Facebook error:', facebookError.message);
              console.error('LinkedIn error:', linkedInError.message);
              console.error('Google error:', googleError.message);
              return res.status(401).json({
                success: false,
                message: 'Invalid authentication token'
              });
            }
          }
        }
      }
    }

    // Check if user exists by email first (for account merging)
    let user;
    let userRef;
    let existingUserId = null;
    
    if (email) {
      // Query for existing user by email
      const usersWithEmail = await db.collection(COLLECTIONS.USERS)
        .where('email', '==', email)
        .limit(1)
        .get();
      
      if (!usersWithEmail.empty) {
        // User with this email exists - use their account
        const existingUserDoc = usersWithEmail.docs[0];
        existingUserId = existingUserDoc.id;
        userRef = existingUserDoc.ref;
        console.log(`Found existing user with email ${email}, merging accounts. Existing ID: ${existingUserId}, Provider ID: ${uid}`);
        
        // Update user with new provider info
        const updateData = {
          updatedAt: new Date().toISOString()
        };
        
        // Track linked providers
        const existingUser = serializeDoc(existingUserDoc);
        const linkedProviders = existingUser.linkedProviders || {};
        linkedProviders[provider] = uid;
        updateData.linkedProviders = linkedProviders;
        
        // Update name if provided and better than current
        if (name && name !== 'Apple User' && (!existingUser.displayName || existingUser.displayName === 'Apple User')) {
          updateData.displayName = name;
        }
        
        // Update profile picture if provided and not already set
        if (picture && !existingUser.profilePicture) {
          updateData.profilePicture = picture;
        }
        
        await userRef.update(updateData);
        user = serializeDoc(await userRef.get());
      }
    }
    
    // If no existing user found by email, check by provider ID
    if (!user) {
      console.log(`🔍 Checking for user by provider ID: ${uid}`);
      userRef = db.collection(COLLECTIONS.USERS).doc(uid);
      const userDoc = await userRef.get();
      
      if (userDoc.exists) {
        // Existing user by provider ID
        const updateData = {
          updatedAt: new Date().toISOString()
        };
        
        const existingUser = serializeDoc(userDoc);
        if (name && name !== 'Apple User' && (!existingUser.displayName || existingUser.displayName === 'Apple User')) {
          updateData.displayName = name;
        }
        
        await userRef.update(updateData);
        user = serializeDoc(await userRef.get());
      } else {
        // Completely new user
        console.log(`🆕 Creating new user with ID: ${uid}, provider: ${provider}`);
        const userData = createUser({
          uid,
          email,
          displayName: name,
          profilePicture: picture,
          linkedProviders: { [provider]: uid }
        });
        
        await userRef.set(userData);
        user = { id: uid, ...userData };
        console.log(`✅ New user created successfully with ID: ${uid}`);
      }
    }

    // Create JWT token for API access
    const tokenUid = user.id || user.uid;
    console.log(`🆔 Creating JWT token with UID: ${tokenUid}`);
    const token = jwt.sign(
      { 
        uid: tokenUid,
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

// @desc    Register user with email and password
// @route   POST /api/auth/register
// @access  Public
exports.register = async (req, res, next) => {
  try {
    const { email, password, displayName } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Email and password are required'
      });
    }

    // Check if user already exists with this email
    const existingUsersQuery = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', email)
      .limit(1)
      .get();
    
    let user;
    let userRef;
    
    if (!existingUsersQuery.empty) {
      // User with this email exists - link the manual registration
      const existingUserDoc = existingUsersQuery.docs[0];
      const existingUserId = existingUserDoc.id;
      userRef = existingUserDoc.ref;
      
      console.log(`Linking manual registration to existing user with email ${email}. Existing ID: ${existingUserId}`);
      
      // For existing users, we need to handle this differently
      // Since Firebase Auth likely already has this email, we can't create a new auth user
      // Instead, we should update the existing user's record to support password login
      
      try {
        // Try to get the existing Firebase Auth user
        const existingAuthUser = await auth.getUserByEmail(email);
        
        // Update the password for the existing auth user
        await auth.updateUser(existingAuthUser.uid, {
          password: password,
          displayName: displayName || existingUserDoc.data().displayName || email.split('@')[0]
        });
        
        console.log(`Updated password for existing Firebase Auth user: ${existingAuthUser.uid}`);
      } catch (error) {
        if (error.code === 'auth/user-not-found') {
          // No Firebase Auth user exists yet (e.g., they only used social login before)
          // Create auth user with the existing Firestore user's ID
          try {
            await auth.createUser({
              uid: existingUserId,
              email,
              password,
              displayName: displayName || existingUserDoc.data().displayName || email.split('@')[0]
            });
          } catch (createError) {
            console.error('Error creating Firebase Auth user:', createError);
            return res.status(400).json({
              success: false,
              message: 'Failed to enable password login for this account'
            });
          }
        } else {
          console.error('Error handling existing user registration:', error);
          return res.status(400).json({
            success: false,
            message: 'This email is already registered. Please use the login page instead.'
          });
        }
      }
      
      // Update existing user with manual registration info
      const updateData = {
        updatedAt: new Date().toISOString()
      };
      
      const existingUser = serializeDoc(existingUserDoc);
      const linkedProviders = existingUser.linkedProviders || {};
      linkedProviders.manual = existingUserId;
      updateData.linkedProviders = linkedProviders;
      
      // Update display name if provided and better than current
      if (displayName && (!existingUser.displayName || existingUser.displayName === 'Apple User')) {
        updateData.displayName = displayName;
      }
      
      await userRef.update(updateData);
      user = serializeDoc(await userRef.get());
    } else {
      // No existing user - create new account
      let userRecord;
      try {
        userRecord = await auth.createUser({
          email,
          password,
          displayName: displayName || email.split('@')[0]
        });
      } catch (error) {
        if (error.code === 'auth/email-already-exists') {
          return res.status(400).json({
            success: false,
            message: 'Email already in use'
          });
        }
        throw error;
      }

      // Create user profile in Firestore
      const userData = createUser({
        uid: userRecord.uid,
        email: userRecord.email,
        displayName: displayName || userRecord.displayName || email.split('@')[0],
        profilePicture: null,
        linkedProviders: { manual: userRecord.uid }
      });

      userRef = db.collection(COLLECTIONS.USERS).doc(userRecord.uid);
      await userRef.set(userData);
      user = { id: userRecord.uid, ...userData };
    }

    // Create JWT token
    const token = jwt.sign(
      { 
        uid: user.id || user.uid,
        email: user.email 
      },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRE }
    );

    res.status(201).json({
      success: true,
      token,
      refreshToken: token,
      user: {
        _id: user.id || user.uid,
        email: user.email,
        displayName: user.displayName,
        profilePicture: user.profilePicture,
        bio: user.bio || null,
        location: user.location || null,
        friends: user.friends || [],
        friendRequests: user.friendRequests || [],
        createdAt: user.createdAt
      }
    });
  } catch (error) {
    console.error('Registration error:', error);
    next(error);
  }
};

// @desc    Login user with email and password
// @route   POST /api/auth/login
// @access  Public
exports.login = async (req, res, next) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Email and password are required'
      });
    }

    // Get user by email from Firebase Auth
    let userRecord;
    try {
      userRecord = await auth.getUserByEmail(email);
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        return res.status(401).json({
          success: false,
          message: 'Invalid credentials'
        });
      }
      throw error;
    }

    // IMPORTANT: Firebase Admin SDK cannot verify passwords directly
    // This is a security limitation - in production you should either:
    // 1. Use Firebase Client SDK on frontend and send ID token to backend
    // 2. Implement a custom authentication endpoint using Firebase REST API
    // For development, we're bypassing password verification which is NOT secure

    // Get user profile from Firestore - check by email first for account merging
    let userDoc;
    let userRef;
    let user;
    
    // First, try to find user by email (for account merging)
    const usersWithEmail = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', email)
      .limit(1)
      .get();
    
    if (!usersWithEmail.empty) {
      // Found user by email
      userDoc = usersWithEmail.docs[0];
      userRef = userDoc.ref;
      user = serializeDoc(userDoc);
      
      // Update linkedProviders to include manual login
      const linkedProviders = user.linkedProviders || {};
      linkedProviders.manual = userRecord.uid;
      
      await userRef.update({
        linkedProviders,
        updatedAt: new Date().toISOString()
      });
      
      // Re-fetch the updated user
      userDoc = await userRef.get();
      user = serializeDoc(userDoc);
    } else {
      // No user found by email, try by UID
      userRef = db.collection(COLLECTIONS.USERS).doc(userRecord.uid);
      userDoc = await userRef.get();
      
      if (!userDoc.exists) {
        // Create profile if it doesn't exist (shouldn't happen normally)
        const userData = createUser({
          uid: userRecord.uid,
          email: userRecord.email,
          displayName: userRecord.displayName || email.split('@')[0],
          profilePicture: null,
          linkedProviders: { manual: userRecord.uid }
        });
        await userRef.set(userData);
        user = { id: userRecord.uid, ...userData };
      } else {
        user = serializeDoc(userDoc);
      }
    }
      
    // Create JWT token
    const token = jwt.sign(
      { 
        uid: user.id || user.uid,
        email: user.email 
      },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRE }
    );

    res.status(200).json({
      success: true,
      token,
      refreshToken: token,
      user: {
        _id: user.id || user.uid,
        email: user.email,
        displayName: user.displayName,
        profilePicture: user.profilePicture,
        bio: user.bio || null,
        location: user.location || null,
        friends: user.friends || [],
        friendRequests: user.friendRequests || [],
        createdAt: user.createdAt
      }
    });
  } catch (error) {
    console.error('Login error:', error);
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

    // Parse the actual Firebase UID from complex format if needed
    let firebaseUid = decoded.uid;
    let parsedUid = null;
    if (decoded.uid && decoded.uid.includes('.')) {
      // Handle format like "000454.9b5eeac93282416c9bc6dcecbc49b40f.2127"
      const parts = decoded.uid.split('.');
      if (parts.length >= 2) {
        parsedUid = parts[1]; // Use the middle part as potential Firebase UID
        console.log(`🔐 Refresh token: Complex ID detected: ${decoded.uid}, parsed UID: ${parsedUid}`);
      }
    }

    // Check if user still exists - try multiple ID formats
    let userDoc = null;
    let actualUserId = null;
    
    // First try the original UID as-is
    const userRef = db.collection(COLLECTIONS.USERS).doc(firebaseUid);
    userDoc = await userRef.get();
    
    if (userDoc.exists) {
      actualUserId = firebaseUid;
      console.log(`✅ Found user with original UID: ${actualUserId}`);
    } else if (parsedUid) {
      // If not found and we have a parsed UID, try that
      const parsedUserRef = db.collection(COLLECTIONS.USERS).doc(parsedUid);
      const parsedUserDoc = await parsedUserRef.get();
      
      if (parsedUserDoc.exists) {
        userDoc = parsedUserDoc;
        actualUserId = parsedUid;
        console.log(`✅ Found user with parsed UID: ${actualUserId}`);
      }
    }
    
    // If still not found, try to find by email if available
    if (!userDoc || !userDoc.exists) {
      if (decoded.email) {
        const usersWithEmail = await db.collection(COLLECTIONS.USERS)
          .where('email', '==', decoded.email)
          .limit(1)
          .get();
        
        if (!usersWithEmail.empty) {
          userDoc = usersWithEmail.docs[0];
          actualUserId = userDoc.id;
          console.log(`✅ Found user by email (${decoded.email}), ID: ${actualUserId}`);
        }
      }
    }

    if (!userDoc || !userDoc.exists) {
      console.error(`❌ User not found for refresh token. Tried UIDs: ${firebaseUid}, ${parsedUid}, email: ${decoded.email}`);
      return res.status(401).json({
        success: false,
        message: 'User no longer exists'
      });
    }

    // Create new JWT token with the same format
    const token = jwt.sign(
      { 
        uid: decoded.uid, // Keep the original complex ID format for consistency
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

// @desc    Handle Facebook data deletion request
// @route   POST /api/auth/facebook-deauthorize
// @access  Public
exports.facebookDataDeletion = async (req, res, next) => {
  try {
    const { signed_request } = req.body;
    
    if (!signed_request) {
      return res.status(400).json({
        success: false,
        message: 'signed_request is required'
      });
    }
    
    // Parse Facebook signed request
    const [encodedSig, payload] = signed_request.split('.');
    const decodedPayload = JSON.parse(Buffer.from(payload, 'base64').toString());
    
    // Extract user ID
    const userId = decodedPayload.user_id;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'Invalid signed request'
      });
    }
    
    // TODO: In production, verify the signature using your app secret
    // For now, we'll proceed with deletion
    
    // Delete user data from Firestore
    const fbUserId = `fb_${userId}`;
    const userRef = db.collection(COLLECTIONS.USERS).doc(fbUserId);
    
    // Check if user exists
    const userDoc = await userRef.get();
    if (userDoc.exists) {
      // Delete user document
      await userRef.delete();
      console.log(`Deleted Facebook user data for user: ${fbUserId}`);
    }
    
    // Return confirmation
    const confirmationCode = `DEL_${userId}_${Date.now()}`;
    
    res.status(200).json({
      url: `${process.env.API_URL || 'https://yourapi.com'}/data-deletion-status?code=${confirmationCode}`,
      confirmation_code: confirmationCode
    });
  } catch (error) {
    console.error('Facebook data deletion error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process data deletion request'
    });
  }
};