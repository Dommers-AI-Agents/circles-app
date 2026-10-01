// backend/controllers/users/accountAdminController.js
// duplicate-account detection and account merge (admin)
// Split out of firebaseUserController.js (handlers unchanged).
const { getFirestore, admin } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');
const { mergeAccounts } = require('../../services/accountMergeService');
const { mintSessionToken, getTokenExpiresInSeconds } = require('../../services/sessionToken');
const { sendServiceError } = require('../../utils/serviceError');
const { invalidateUserCache } = require('../../middleware/firebaseAuth');

const db = getFirestore();

// @desc    Find and merge duplicate user accounts
// @route   POST /api/users/find-duplicates
// @access  Private (Admin only)
exports.findDuplicateAccounts = async (req, res, next) => {
  try {
    const isSuperUser = req.user.isSuperUser === true;
    // Only your OWN address unless you're a super-user: this used to look up
    // any email and return those people's full records (security audit
    // 2026-10-01). Displayname is a hint, not an identity.
    const email = isSuperUser ? req.body.email : req.user.email;
    const displayName = req.body.displayName;
    const currentUserId = req.user.uid;
    
    if (!email) {
      return res.status(400).json({
        success: false,
        message: 'Email is required'
      });
    }
    
    console.log(`🔍 Finding duplicates for user: ${email} (${displayName})`);
    
    const duplicateAccounts = [];
    const currentUserEmail = email.toLowerCase();
    
    // Find accounts with same email (exact match)
    const emailQuery = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', email)
      .get();
    
    emailQuery.docs.forEach(doc => {
      const user = serializeDoc(doc);
      if (user.id !== currentUserId) {
        duplicateAccounts.push({
          ...user,
          matchType: 'email',
          reason: 'Same email address'
        });
      }
    });
    
    // Find accounts in alternateEmails array
    const alternateEmailQuery = await db.collection(COLLECTIONS.USERS)
      .where('alternateEmails', 'array-contains', email)
      .get();
    
    alternateEmailQuery.docs.forEach(doc => {
      const user = serializeDoc(doc);
      if (user.id !== currentUserId && !duplicateAccounts.find(acc => acc.id === user.id)) {
        duplicateAccounts.push({
          ...user,
          matchType: 'alternateEmail',
          reason: 'Email found in alternate emails'
        });
      }
    });
    
    // Find potential Apple Sign In duplicates by displayName (if current email is private relay)
    if (email.includes('@privaterelay.appleid.com') && displayName) {
      const nameQuery = await db.collection(COLLECTIONS.USERS)
        .where('displayName', '==', displayName)
        .get();
      
      nameQuery.docs.forEach(doc => {
        const user = serializeDoc(doc);
        if (user.id !== currentUserId && 
            !user.email.includes('@privaterelay.appleid.com') && 
            !duplicateAccounts.find(acc => acc.id === user.id)) {
          duplicateAccounts.push({
            ...user,
            matchType: 'displayName',
            reason: 'Same display name (potential Apple Sign In duplicate)'
          });
        }
      });
    }
    
    // Find accounts where current email is in their alternateEmails
    if (isSuperUser && !email.includes('@privaterelay.appleid.com')) {
      const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
      
      usersSnapshot.docs.forEach(doc => {
        const user = serializeDoc(doc);
        if (user.id !== currentUserId && 
            user.email && 
            user.email.includes('@privaterelay.appleid.com') &&
            user.displayName === displayName &&
            !duplicateAccounts.find(acc => acc.id === user.id)) {
          duplicateAccounts.push({
            ...user,
            matchType: 'privateRelay',
            reason: 'Private relay account with same display name'
          });
        }
      });
    }
    
    console.log(`Found ${duplicateAccounts.length} potential duplicate accounts for ${currentUserId}`);

    // Public fields only. An email is shown back only where it IS the
    // caller's (matched on their own address); name-only matches are
    // other people as far as we know.
    const publicView = (u) => ({
      id: u.id, _id: u.id, displayName: u.displayName || 'User', profilePicture: u.profilePicture || null,
      createdAt: u.createdAt || null, matchType: u.matchType, reason: u.reason,
      ...((isSuperUser || u.matchType === 'email' || u.matchType === 'alternateEmail') ? { email: u.email || null } : {})
    });
    res.status(200).json({
      success: true,
      duplicateAccounts: duplicateAccounts.map(publicView)
    });
    
  } catch (error) {
    console.error('Error finding duplicate accounts:', error);
    next(error);
  }
};

// @desc    Get potential duplicate connections for a user
// @route   GET /api/users/me/duplicate-connections
// @access  Private
exports.checkDuplicateConnections = async (req, res, next) => {
  try {
    const currentUserId = req.user.uid;
    const currentUserEmail = req.user.email;
    
    // Find all users with the same email
    const sameEmailUsers = [];
    const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
    
    usersSnapshot.docs.forEach(doc => {
      const user = serializeDoc(doc);
      if (user.email && user.email.toLowerCase() === currentUserEmail.toLowerCase() && user.id !== currentUserId) {
        sameEmailUsers.push({
          id: user.id,
          email: user.email,
          displayName: user.displayName
        });
      }
    });
    
    if (sameEmailUsers.length === 0) {
      return res.status(200).json({
        success: true,
        message: 'No duplicate accounts found',
        duplicates: []
      });
    }
    
    // Get connections for all accounts with this email
    const allConnections = new Map();
    
    // Get connections for current user
    const currentUserConnections = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', currentUserId).get(),
      db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', currentUserId).get()
    ]);
    
    currentUserConnections.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
        const conn = doc.data();
        const otherUserId = conn.userId === currentUserId ? conn.connectedUserId : conn.userId;
        allConnections.set(otherUserId, {
          connectionId: doc.id,
          status: conn.status,
          fromAccount: currentUserId
        });
      });
    });
    
    // Get connections for duplicate accounts
    for (const dupUser of sameEmailUsers) {
      const dupConnections = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', dupUser.id).get(),
        db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', dupUser.id).get()
      ]);
      
      dupConnections.forEach(snapshot => {
        snapshot.docs.forEach(doc => {
          const conn = doc.data();
          const otherUserId = conn.userId === dupUser.id ? conn.connectedUserId : conn.userId;
          
          // Check if this connection already exists from another account
          if (allConnections.has(otherUserId)) {
            console.log(`Duplicate connection found: ${otherUserId} connected to both ${currentUserId} and ${dupUser.id}`);
          }
        });
      });
    }
    
    res.status(200).json({
      success: true,
      currentUserId: currentUserId,
      duplicateAccounts: sameEmailUsers,
      message: `Found ${sameEmailUsers.length} other accounts with email ${currentUserEmail}`
    });
  } catch (error) {
    console.error('Error checking duplicate connections:', error);
    next(error);
  }
};

exports.mergeUserAccounts = async (req, res, next) => {
  try {
    const { primaryAccountId, secondaryAccountId, dryRun } = req.body;
    if (!primaryAccountId || !secondaryAccountId) {
      return res.status(400).json({ success: false, message: 'Both primaryAccountId and secondaryAccountId are required' });
    }

    // Super-users only. Owning ONE of the two accounts used to be enough —
    // a brand-new account could merge itself into anyone's and be handed a
    // session for the survivor (security audit 2026-10-01). A self-service
    // merge would need proof of signing in to BOTH accounts.
    const isAdmin = req.user.isSuperUser === true;
    const callerIds = [req.user.uid, req.user.originalUid].filter(Boolean);
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        code: 'merge_needs_support',
        message: 'To merge two accounts, email wesley@favcircles.com from the address on both and we will combine them for you.'
      });
    }

    const result = await mergeAccounts({
      primaryId: primaryAccountId, secondaryId: secondaryAccountId, dryRun: dryRun === true,
      mergedBy: req.user.uid, via: 'api'
    });

    // The caller may have been signed into the account that just got folded
    // (the new empty one). Hand back a session for the survivor so the app
    // continues as the person they actually are.
    const response = {
      success: true,
      message: dryRun === true ? 'Merge previewed' : 'Accounts merged successfully',
      primaryAccount: result.primaryUser,
      survivorId: result.primaryId,
      mergedAccountId: result.secondaryId,
      // The audit record's id; absent on a dry run.
      mergeId: result.mergeId || null,
      swapped: result.swapped,
      counts: result.counts,
      mergedData: {
        alternateEmailsAdded: result.mergedData.alternateEmails || [],
        providersLinked: Object.keys(result.mergedData.linkedProviders || {}),
        followersAdded: result.counts.followerRefs || 0,
        followingAdded: result.counts.followingRefs || 0
      }
    };
    if (dryRun !== true) {
      invalidateUserCache(result.primaryId);
      invalidateUserCache(result.secondaryId);
      if (callerIds.includes(result.secondaryId)) {
        response.token = mintSessionToken(result.primaryId, result.primaryUser.email);
        response.expiresIn = getTokenExpiresInSeconds();
      }
    }
    res.status(200).json(response);
  } catch (error) {
    sendServiceError(res, error, { log: 'Error merging accounts', fallbackCode: 'merge_failed', fallbackMessage: 'Could not merge accounts' });
  }
};

// @route   DELETE /api/users/me
// Deletes the caller's account and their data (services/accountDeletionService).
exports.deleteMyAccount = async (req, res) => {
  const uid = req.user.firebaseDocId || req.user.uid;
  try {
    const { deleteAccount } = require('../../services/accountDeletionService');
    const result = await deleteAccount(uid);
    invalidateUserCache(uid);
    console.log(`🗑️ Account deleted: ${uid}`, result.counts);
    res.status(200).json({ success: true, message: 'Your account and data were deleted.' });
  } catch (error) {
    invalidateUserCache(uid);
    sendServiceError(res, error, { log: 'Error deleting account', fallbackCode: 'delete_failed', fallbackMessage: 'Could not delete your account. Please try again.' });
  }
};
