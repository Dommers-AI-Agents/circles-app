// backend/middleware/firebaseAuth.js
const jwt = require('jsonwebtoken');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { normalizeUserId, logNormalization } = require('../services/idService');

const db = getFirestore();

// Passive activity tracking: stamp users.lastActive on authenticated traffic,
// at most once per throttle window per instance. Fire-and-forget — must never
// add latency or fail a request. (Firebase Auth's lastSignInTime is useless
// here because the app mints its own long-lived JWTs.)
const LAST_ACTIVE_THROTTLE_MS = 15 * 60 * 1000;
const lastActiveStamps = new Map(); // uid -> ms of last stamp (per instance)

const stampLastActive = (userId) => {
  const now = Date.now();
  const last = lastActiveStamps.get(userId) || 0;
  if (now - last < LAST_ACTIVE_THROTTLE_MS) return;
  lastActiveStamps.set(userId, now);
  db.collection(COLLECTIONS.USERS).doc(userId)
    .update({ lastActive: new Date().toISOString() })
    .catch((error) => console.error('⚠️ lastActive stamp failed:', error.message));
};

// Short-TTL per-instance cache of resolved user identity, so read traffic
// doesn't pay a Firestore read to rehydrate req.user on every request. Only
// served for GET: any mutating request reads fresh (and refreshes the cache),
// so a write never acts on — or returns — stale user state.
const USER_CACHE_TTL_MS = 20 * 1000;
const userCache = new Map(); // decoded.uid -> { userData, finalUserId, expires }

const buildReqUser = (decoded, userData, finalUserId) => ({
  uid: finalUserId,
  firebaseDocId: finalUserId,
  originalUid: decoded.uid,
  email: decoded.email || userData.email,
  ...userData
});

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

      // Fast path: serve cached identity for read-only requests
      if (req.method === 'GET') {
        const cached = userCache.get(decoded.uid);
        if (cached && cached.expires > Date.now()) {
          if (cached.userData.banned === true) {
            return res.status(403).json({
              success: false, code: 'account_banned',
              message: 'This account has been suspended for violating our community guidelines. Contact support@favcircles.com to appeal.'
            });
          }
          req.user = buildReqUser(decoded, cached.userData, cached.finalUserId);
          stampLastActive(cached.finalUserId);
          return next();
        }
      }

      // Get user from Firestore - try normalized ID first
      let userDoc = null;
      let actualUserId = null;

      userDoc = await db.collection(COLLECTIONS.USERS).doc(normalizedUid).get();

      if (userDoc.exists) {
        actualUserId = normalizedUid;
      } else if (normalizedUid !== decoded.uid) {
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
        if (decoded.email) {
          const normalizedEmail = decoded.email.toLowerCase().trim();
          const usersWithEmail = await db.collection(COLLECTIONS.USERS)
            .where('email', '==', normalizedEmail)
            .limit(1)
            .get();
          if (!usersWithEmail.empty) {
            userDoc = usersWithEmail.docs[0];
            actualUserId = userDoc.id;
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

      // Banned accounts are locked out everywhere, with an appeal path
      if (userData.banned === true) {
        return res.status(403).json({
          success: false, code: 'account_banned',
          message: 'This account has been suspended for violating our community guidelines. Contact support@favcircles.com to appeal.'
        });
      }

      userCache.set(decoded.uid, { userData, finalUserId, expires: Date.now() + USER_CACHE_TTL_MS });
      req.user = buildReqUser(decoded, userData, finalUserId);
      stampLastActive(finalUserId);
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