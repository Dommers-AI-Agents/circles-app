// backend/middleware/firebaseAuth.js
const jwt = require('jsonwebtoken');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { normalizeUserId, logNormalization } = require('../services/idService');

const db = getFirestore();

// Protect routes - require valid JWT token
exports.protect = async (req, res, next) => {
  console.log('🔐 AUTH MIDDLEWARE: protect function called');
  console.log('🔐 AUTH MIDDLEWARE: Request path:', req.path);
  console.log('🔐 AUTH MIDDLEWARE: Request method:', req.method);
  // Auth middleware processing
  
  try {
    let token;

    // Get token from header
    if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
      token = req.headers.authorization.split(' ')[1];
      console.log('🔐 AUTH MIDDLEWARE: Token found in Authorization header');
      console.log('🔐 AUTH MIDDLEWARE: Token length:', token.length);
    }

    // Make sure token exists
    if (!token) {
      console.log('❌ AUTH MIDDLEWARE: No token found in request');
      return res.status(401).json({
        success: false,
        message: 'Not authorized to access this route'
      });
    }

    try {
      console.log('🔐 AUTH MIDDLEWARE: Verifying JWT token...');
      // Verify token
      const decoded = jwt.verify(token, process.env.JWT_SECRET);
      console.log('✅ AUTH MIDDLEWARE: Token verified successfully');
      // Token decoded successfully

      // Normalize the user ID using our centralized service
      const normalizedUid = normalizeUserId(decoded.uid);
      logNormalization('Auth Middleware', decoded.uid, normalizedUid);

      console.log('🔐 AUTH MIDDLEWARE: Looking up user in database...');
      // Get user from Firestore - try normalized ID first
      let userDoc = null;
      let actualUserId = null;
      
      // Try with normalized ID
      console.log('🔐 AUTH MIDDLEWARE: Trying normalized ID:', normalizedUid);
      userDoc = await db.collection(COLLECTIONS.USERS).doc(normalizedUid).get();
      
      if (userDoc.exists) {
        actualUserId = normalizedUid;
        console.log('✅ AUTH MIDDLEWARE: User found with normalized ID');
      } else if (normalizedUid !== decoded.uid) {
        console.log('⚠️ AUTH MIDDLEWARE: User not found with normalized ID, trying original:', decoded.uid);
        // If not found with normalized ID and original was different, try original
        const originalDoc = await db.collection(COLLECTIONS.USERS).doc(decoded.uid).get();
        
        if (originalDoc.exists) {
          userDoc = originalDoc;
          actualUserId = decoded.uid;
          console.log(`⚠️ AUTH MIDDLEWARE: User found with complex ID ${decoded.uid}, migration needed`);
        }
      }
      
      // If still not found, try to find by email if available
      if (!userDoc || !userDoc.exists) {
        console.log('⚠️ AUTH MIDDLEWARE: User not found by ID, trying email lookup');
        if (decoded.email) {
          const normalizedEmail = decoded.email.toLowerCase().trim();
          console.log('🔐 AUTH MIDDLEWARE: Looking for user with email:', normalizedEmail);
          const usersWithEmail = await db.collection(COLLECTIONS.USERS)
            .where('email', '==', normalizedEmail)
            .limit(1)
            .get();
          
          if (!usersWithEmail.empty) {
            userDoc = usersWithEmail.docs[0];
            actualUserId = userDoc.id;
            console.log(`✅ AUTH MIDDLEWARE: Found user by email ${normalizedEmail}, ID: ${actualUserId}`);
          } else {
            console.log('❌ AUTH MIDDLEWARE: No user found with email:', normalizedEmail);
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

      console.log('✅ AUTH MIDDLEWARE: User authenticated successfully, proceeding to next middleware');
      next();
    } catch (error) {
      console.error('❌ AUTH MIDDLEWARE: Token verification failed:', error);
      console.error('❌ AUTH MIDDLEWARE: Error type:', error.name);
      console.error('❌ AUTH MIDDLEWARE: Error message:', error.message);
      return res.status(401).json({
        success: false,
        message: 'Not authorized to access this route'
      });
    }
  } catch (error) {
    console.error('❌ AUTH MIDDLEWARE: General auth middleware error:', error);
    console.error('❌ AUTH MIDDLEWARE: Error stack:', error.stack);
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