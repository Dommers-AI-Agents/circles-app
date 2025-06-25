// backend/middleware/firebaseAuth.js
const jwt = require('jsonwebtoken');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');

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

      // Parse the actual Firebase UID from complex format if needed
      let firebaseUid = decoded.uid;
      let parsedUid = null;
      if (decoded.uid && decoded.uid.includes('.')) {
        // Handle format like "000454.9b5eeac93282416c9bc6dcecbc49b40f.2127"
        const parts = decoded.uid.split('.');
        if (parts.length >= 2) {
          parsedUid = parts[1]; // Use the middle part as potential Firebase UID
          console.log(`🔐 Auth middleware: Complex ID detected: ${decoded.uid}, parsed UID: ${parsedUid}`);
        }
      }

      // Get user from Firestore - try multiple ID formats
      let userDoc = null;
      let actualUserId = null;
      
      // First try the original UID as-is
      userDoc = await db.collection(COLLECTIONS.USERS).doc(firebaseUid).get();
      
      if (userDoc.exists) {
        actualUserId = firebaseUid;
      } else if (parsedUid) {
        // If not found and we have a parsed UID, try that
        const parsedUserDoc = await db.collection(COLLECTIONS.USERS).doc(parsedUid).get();
        
        if (parsedUserDoc.exists) {
          userDoc = parsedUserDoc;
          actualUserId = parsedUid;
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
          }
        }
      }

      if (!userDoc || !userDoc.exists) {
        console.error(`❌ User not found in auth middleware. Tried UIDs: ${firebaseUid}, ${parsedUid}, email: ${decoded.email}`);
        return res.status(401).json({
          success: false,
          message: 'User no longer exists'
        });
      }

      // Add user to request object
      const userData = serializeDoc(userDoc);
      req.user = {
        uid: decoded.uid, // Always use the original complex ID from the token
        firebaseDocId: actualUserId, // Keep the actual Firestore document ID
        email: decoded.email,
        ...userData
      };
      
      console.log('🔍 DEBUG auth middleware user:', req.user);

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