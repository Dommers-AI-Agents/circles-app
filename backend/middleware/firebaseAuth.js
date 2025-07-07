// backend/middleware/firebaseAuth.js
const jwt = require('jsonwebtoken');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { normalizeUserId, logNormalization } = require('../services/idService');

const db = getFirestore();

// Protect routes - require valid JWT token
exports.protect = async (req, res, next) => {
  try {
    let token;

    // Get token from header
    if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
      token = req.headers.authorization.split(' ')[1];
    }

    // Make sure token exists
    if (!token) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to access this route'
      });
    }

    try {
      // Verify token
      const decoded = jwt.verify(token, process.env.JWT_SECRET);

      // Normalize the user ID using our centralized service
      const normalizedUid = normalizeUserId(decoded.uid);
      logNormalization('Auth Middleware', decoded.uid, normalizedUid);

      // Get user from Firestore - try normalized ID first
      let userDoc = null;
      let actualUserId = null;
      
      // Try with normalized ID
      userDoc = await db.collection(COLLECTIONS.USERS).doc(normalizedUid).get();
      
      if (userDoc.exists) {
        actualUserId = normalizedUid;
      } else if (normalizedUid !== decoded.uid) {
        // If not found with normalized ID and original was different, try original
        const originalDoc = await db.collection(COLLECTIONS.USERS).doc(decoded.uid).get();
        
        if (originalDoc.exists) {
          userDoc = originalDoc;
          actualUserId = decoded.uid;
          console.log(`⚠️ User found with complex ID ${decoded.uid}, migration needed`);
        }
      }
      
      // If still not found, try to find by email if available
      if (!userDoc || !userDoc.exists) {
        if (decoded.email) {
          const normalizedEmail = decoded.email.toLowerCase().trim();
          const usersWithEmail = await db.collection(COLLECTIONS.USERS)
            .where('email', '==', normalizedEmail)
            .limit(1)
            .get();
          
          if (!usersWithEmail.empty) {
            userDoc = usersWithEmail.docs[0];
            actualUserId = userDoc.id;
            console.log(`Found user by email ${normalizedEmail}, ID: ${actualUserId}`);
          }
        }
      }

      if (!userDoc || !userDoc.exists) {
        console.error(`❌ User not found in auth middleware. Tried normalized UID: ${normalizedUid}, original: ${decoded.uid}, email: ${decoded.email}`);
        return res.status(401).json({
          success: false,
          message: 'User no longer exists'
        });
      }

      // Add user to request object with normalized ID
      const userData = serializeDoc(userDoc);
      const finalUserId = normalizeUserId(actualUserId); // Ensure we always use normalized ID
      
      req.user = {
        uid: finalUserId, // Always use normalized ID
        firebaseDocId: finalUserId, // Keep for backwards compatibility
        originalUid: decoded.uid, // Keep the original ID from token
        email: decoded.email || userData.email,
        ...userData
      };
      
      console.log('🔍 Auth middleware - User authenticated:', {
        uid: req.user.uid,
        originalUid: req.user.originalUid,
        email: req.user.email,
        normalized: finalUserId !== decoded.uid
      });

      next();
    } catch (error) {
      console.error('Token verification failed:', error);
      return res.status(401).json({
        success: false,
        message: 'Not authorized to access this route'
      });
    }
  } catch (error) {
    console.error('Auth middleware error:', error);
    return res.status(500).json({
      success: false,
      message: 'Server error in authentication'
    });
  }
};

// Grant access to specific roles (if needed in the future)
exports.authorize = (...roles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to access this route'
      });
    }

    if (!roles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: `User role ${req.user.role} is not authorized to access this route`
      });
    }

    next();
  };
};