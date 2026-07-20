// backend/controllers/linkedinAuthController.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, createUser, serializeDoc } = require('../models/FirestoreModels');
const jwt = require('jsonwebtoken');

const db = getFirestore();

// LinkedIn OAuth configuration
const LINKEDIN_CLIENT_ID = process.env.LINKEDIN_CLIENT_ID || '86rx0d8w7xn8rq';
const LINKEDIN_CLIENT_SECRET = process.env.LINKEDIN_CLIENT_SECRET || 'WPL_AP1.9JAPH7a6vSn5gBbR.XDRNag==';
const LINKEDIN_REDIRECT_URI = 'com.favcircles.circles://linkedin-callback';

// Helper function to exchange LinkedIn authorization code for access token
async function exchangeLinkedInCode(code) {
  const params = new URLSearchParams({
    grant_type: 'authorization_code',
    code: code,
    redirect_uri: LINKEDIN_REDIRECT_URI,
    client_id: LINKEDIN_CLIENT_ID,
    client_secret: LINKEDIN_CLIENT_SECRET
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
    console.error('LinkedIn token exchange error:', data);
    throw new Error(data.error_description || 'Failed to exchange LinkedIn authorization code');
  }
  
  return data.access_token;
}

// Helper function to fetch LinkedIn user profile
async function fetchLinkedInProfile(accessToken) {
  const headers = {
    'Authorization': `Bearer ${accessToken}`
  };
  
  // Get basic profile information
  const profileResponse = await fetch('https://api.linkedin.com/v2/me', { headers });
  
  if (!profileResponse.ok) {
    const error = await profileResponse.text();
    console.error('LinkedIn profile fetch error:', error);
    throw new Error('Failed to fetch LinkedIn profile');
  }
  
  const profileData = await profileResponse.json();
  
  // Get email address
  const emailResponse = await fetch('https://api.linkedin.com/v2/emailAddress?q=members&projection=(elements*(handle~))', { headers });
  
  let email = null;
  if (emailResponse.ok) {
    const emailData = await emailResponse.json();
    if (emailData.elements && emailData.elements[0]) {
      email = emailData.elements[0]['handle~'].emailAddress;
    }
  }
  
  // Get profile picture
  const pictureResponse = await fetch('https://api.linkedin.com/v2/me?projection=(profilePicture(displayImage~:playableStreams))', { headers });
  
  let profilePicture = null;
  if (pictureResponse.ok) {
    const pictureData = await pictureResponse.json();
    if (pictureData.profilePicture && pictureData.profilePicture['displayImage~'] && 
        pictureData.profilePicture['displayImage~'].elements && 
        pictureData.profilePicture['displayImage~'].elements.length > 0) {
      // Get the largest available image
      const images = pictureData.profilePicture['displayImage~'].elements;
      const largestImage = images[images.length - 1];
      if (largestImage.identifiers && largestImage.identifiers[0]) {
        profilePicture = largestImage.identifiers[0].identifier;
      }
    }
  }
  
  return {
    id: profileData.id,
    firstName: profileData.localizedFirstName || '',
    lastName: profileData.localizedLastName || '',
    email: email,
    profilePicture: profilePicture
  };
}

// @desc    LinkedIn OAuth authentication
// @route   POST /api/auth/linkedin
// @access  Public
exports.linkedinAuth = async (req, res, next) => {
  try {
    const { code, email: providedEmail, name: providedName } = req.body;

    if (!code) {
      return res.status(400).json({
        success: false,
        message: 'Authorization code is required'
      });
    }

    console.log('🔄 LinkedIn authentication started');
    
    // Exchange authorization code for access token
    let accessToken;
    try {
      accessToken = await exchangeLinkedInCode(code);
      console.log('✅ LinkedIn access token obtained');
    } catch (error) {
      console.error('❌ LinkedIn token exchange failed:', error.message);
      return res.status(401).json({
        success: false,
        message: 'Failed to authenticate with LinkedIn'
      });
    }

    // Fetch user profile from LinkedIn
    let linkedInProfile;
    try {
      linkedInProfile = await fetchLinkedInProfile(accessToken);
      console.log('✅ LinkedIn profile fetched:', {
        id: linkedInProfile.id,
        email: linkedInProfile.email,
        name: `${linkedInProfile.firstName} ${linkedInProfile.lastName}`
      });
    } catch (error) {
      console.error('❌ LinkedIn profile fetch failed:', error.message);
      return res.status(401).json({
        success: false,
        message: 'Failed to fetch LinkedIn profile'
      });
    }

    // Prepare user data
    const uid = `linkedin_${linkedInProfile.id}`;
    const email = providedEmail || linkedInProfile.email;
    const displayName = providedName || 
                       `${linkedInProfile.firstName} ${linkedInProfile.lastName}`.trim() || 
                       'LinkedIn User';
    const profilePicture = linkedInProfile.profilePicture;

    if (!email) {
      return res.status(400).json({
        success: false,
        message: 'Email address is required. LinkedIn did not provide an email address.'
      });
    }

    // Check if user exists by email first (for account merging)
    let user;
    let userRef;
    let existingUserId = null;
    
    // Query for existing user by email
    const usersWithEmail = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', email)
      .limit(1)
      .get();
    
    if (!usersWithEmail.empty) {
      // User with this email exists - merge accounts
      const existingUserDoc = usersWithEmail.docs[0];
      existingUserId = existingUserDoc.id;
      userRef = existingUserDoc.ref;
      
      console.log(`Found existing user with email ${email}, merging accounts. Existing ID: ${existingUserId}, LinkedIn ID: ${uid}`);
      
      // Update user with LinkedIn provider info
      const updateData = {
        updatedAt: new Date().toISOString()
      };
      
      // Track linked providers
      const existingUser = serializeDoc(existingUserDoc);
      const linkedProviders = existingUser.linkedProviders || {};
      linkedProviders.linkedin = uid;
      updateData.linkedProviders = linkedProviders;
      
      // Update name if provided and better than current
      if (displayName && displayName !== 'LinkedIn User' && 
          (!existingUser.displayName || existingUser.displayName === 'Apple User')) {
        updateData.displayName = displayName;
      }
      
      // Update profile picture if provided and not already set
      if (profilePicture && !existingUser.profilePicture) {
        updateData.profilePicture = profilePicture;
      }
      
      await userRef.update(updateData);
      user = serializeDoc(await userRef.get());
    } else {
      // No email match — look the account up by linked provider identity
      // (keeps merged accounts reachable from LinkedIn sign-in even when the
      // doc id belongs to another provider)
      const providerQuery = await db.collection(COLLECTIONS.USERS)
        .where('linkedProviders.linkedin', '==', uid)
        .limit(1)
        .get();

      if (!providerQuery.empty) {
        const existingUserDoc = providerQuery.docs[0];
        existingUserId = existingUserDoc.id;
        userRef = existingUserDoc.ref;
        console.log(`Found existing user by linkedProviders.linkedin: ${existingUserId}`);

        const existingUser = serializeDoc(existingUserDoc);
        const updateData = {
          updatedAt: new Date().toISOString()
        };
        if (email && existingUser.email !== email) {
          const alternateEmails = existingUser.alternateEmails || [];
          if (!alternateEmails.includes(email)) {
            updateData.alternateEmails = [...alternateEmails, email];
          }
        }
        if (displayName && displayName !== 'LinkedIn User' && !existingUser.displayName) {
          updateData.displayName = displayName;
        }

        await userRef.update(updateData);
        user = serializeDoc(await userRef.get());
      }

      // No provider match either, check by LinkedIn ID as doc id
      if (!user) {
        userRef = db.collection(COLLECTIONS.USERS).doc(uid);
        const userDoc = await userRef.get();

        if (userDoc.exists) {
          // Existing user by LinkedIn ID
          const updateData = {
            updatedAt: new Date().toISOString()
          };

          const existingUser = serializeDoc(userDoc);

          // Update email if not set
          if (!existingUser.email && email) {
            updateData.email = email;
          }

          // Update display name if better
          if (displayName && displayName !== 'LinkedIn User' &&
              (!existingUser.displayName || existingUser.displayName === 'LinkedIn User')) {
            updateData.displayName = displayName;
          }

          // Update profile picture if not set
          if (profilePicture && !existingUser.profilePicture) {
            updateData.profilePicture = profilePicture;
          }

          await userRef.update(updateData);
          user = serializeDoc(await userRef.get());
        } else {
          // Completely new user
          const userData = createUser({
            uid,
            email,
            displayName,
            profilePicture,
            linkedProviders: { linkedin: uid }
          });

          await userRef.set(userData);
          user = { id: uid, ...userData };
          console.log('✅ New LinkedIn user created:', uid);
        }
      }
    }

    // Create JWT token for API access
    const token = jwt.sign(
      { 
        uid: user.id || user.uid,
        email: user.email 
      },
      process.env.JWT_SECRET || 'your-secret-key',
      { expiresIn: process.env.JWT_EXPIRE || '7d' }
    );

    const response = {
      success: true,
      token,
      refreshToken: token, // For now, use same token as refresh token
      user: {
        _id: user.id || user.uid, // iOS expects _id, not id
        email: user.email || '',
        displayName: user.displayName || displayName || 'LinkedIn User',
        profilePicture: user.profilePicture || profilePicture || null,
        bio: user.bio || null,
        location: user.location || null,
        friends: user.friends || [],
        friendRequests: user.friendRequests || [],
        createdAt: user.createdAt || new Date().toISOString()
      }
    };

    console.log('📤 Sending LinkedIn auth response for user:', response.user._id);

    res.status(200).json(response);
  } catch (error) {
    console.error('LinkedIn auth error:', error);
    next(error);
  }
};

// @desc    Get LinkedIn authorization URL
// @route   GET /api/auth/linkedin/url
// @access  Public
exports.getLinkedInAuthUrl = (req, res) => {
  const state = req.query.state || '';
  
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: LINKEDIN_CLIENT_ID,
    redirect_uri: LINKEDIN_REDIRECT_URI,
    state: state,
    scope: 'r_liteprofile r_emailaddress'
  });
  
  const authUrl = `https://www.linkedin.com/oauth/v2/authorization?${params.toString()}`;
  
  res.status(200).json({
    success: true,
    authUrl
  });
};