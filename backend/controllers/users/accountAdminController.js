// backend/controllers/users/accountAdminController.js
// duplicate-account detection and account merge (admin)
// Split out of firebaseUserController.js (handlers unchanged).
const { getFirestore, admin } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');

const db = getFirestore();

// @desc    Find and merge duplicate user accounts
// @route   POST /api/users/find-duplicates
// @access  Private (Admin only)
exports.findDuplicateAccounts = async (req, res, next) => {
  try {
    const { email, displayName } = req.body;
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
    if (!email.includes('@privaterelay.appleid.com')) {
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
    
    console.log(`Found ${duplicateAccounts.length} potential duplicate accounts for ${email}`);
    
    res.status(200).json({
      success: true,
      duplicateAccounts: duplicateAccounts
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
    const { primaryAccountId, secondaryAccountId } = req.body;
    
    if (!primaryAccountId || !secondaryAccountId) {
      return res.status(400).json({
        success: false,
        message: 'Both primaryAccountId and secondaryAccountId are required'
      });
    }
    
    if (primaryAccountId === secondaryAccountId) {
      return res.status(400).json({
        success: false,
        message: 'Cannot merge account with itself'
      });
    }
    
    // Get both user documents
    const primaryRef = db.collection(COLLECTIONS.USERS).doc(primaryAccountId);
    const secondaryRef = db.collection(COLLECTIONS.USERS).doc(secondaryAccountId);
    
    const [primaryDoc, secondaryDoc] = await Promise.all([
      primaryRef.get(),
      secondaryRef.get()
    ]);
    
    if (!primaryDoc.exists || !secondaryDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'One or both user accounts not found'
      });
    }
    
    const primaryUser = serializeDoc(primaryDoc);
    const secondaryUser = serializeDoc(secondaryDoc);
    
    // Verify user has permission (admin or owns one of the accounts)
    const isAdmin = req.user.role === 'admin'; // Assuming admin role exists
    const ownsAccount = req.user.uid === primaryAccountId || req.user.uid === secondaryAccountId;
    
    if (!isAdmin && !ownsAccount) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to merge these accounts'
      });
    }
    
    console.log(`🔄 Merging accounts: ${secondaryAccountId} -> ${primaryAccountId}`);
    console.log(`Primary: ${primaryUser.email} (${primaryUser.displayName})`);
    console.log(`Secondary: ${secondaryUser.email} (${secondaryUser.displayName})`);
    
    // Prepare merged data
    const mergedData = {
      // Merge alternate emails
      alternateEmails: [
        ...(primaryUser.alternateEmails || []),
        ...(secondaryUser.alternateEmails || []),
        // Add secondary email if different from primary
        ...(secondaryUser.email && secondaryUser.email !== primaryUser.email ? [secondaryUser.email] : [])
      ].filter((email, index, arr) => arr.indexOf(email) === index && email !== primaryUser.email), // Remove duplicates and primary email
      
      // Merge linked providers
      linkedProviders: {
        ...(primaryUser.linkedProviders || {}),
        ...(secondaryUser.linkedProviders || {})
      },
      
      // Keep better display name if secondary has one and primary doesn't
      displayName: primaryUser.displayName || secondaryUser.displayName,
      
      // Keep better profile picture if secondary has one and primary doesn't
      profilePicture: primaryUser.profilePicture || secondaryUser.profilePicture,
      
      // Merge other fields intelligently
      firstName: primaryUser.firstName || secondaryUser.firstName,
      lastName: primaryUser.lastName || secondaryUser.lastName,
      phoneNumber: primaryUser.phoneNumber || secondaryUser.phoneNumber,
      bio: primaryUser.bio || secondaryUser.bio,
      location: primaryUser.location || secondaryUser.location,
      
      // Merge arrays (dropping both account ids — the accounts may have
      // followed each other, and nobody should follow themselves post-merge)
      followers: [...(primaryUser.followers || []), ...(secondaryUser.followers || [])]
        .filter((id, index, arr) => arr.indexOf(id) === index && id !== primaryAccountId && id !== secondaryAccountId),
      following: [...(primaryUser.following || []), ...(secondaryUser.following || [])]
        .filter((id, index, arr) => arr.indexOf(id) === index && id !== primaryAccountId && id !== secondaryAccountId),
      deviceTokens: [...(primaryUser.deviceTokens || []), ...(secondaryUser.deviceTokens || [])].filter((token, index, arr) => arr.indexOf(token) === index),
      pinnedPlaces: [...(primaryUser.pinnedPlaces || []), ...(secondaryUser.pinnedPlaces || [])].slice(0, 6), // Max 6
      
      // Update counts
      followersCount: 0, // Will be recalculated
      followingCount: 0, // Will be recalculated
      
      // Keep notification preferences from primary (user can update if needed)
      notificationPreferences: primaryUser.notificationPreferences || secondaryUser.notificationPreferences,
      
      updatedAt: new Date().toISOString()
    };
    
    // Recalculate counts
    mergedData.followersCount = mergedData.followers.length;
    mergedData.followingCount = mergedData.following.length;
    
    // Rewrite every reference from the secondary id to the primary id.
    // Batched writes (450/commit, under Firestore's 500 limit); re-running the
    // merge resumes cleanly since the queries only match docs still pointing
    // at the secondary id.
    let batch = db.batch();
    let pendingOps = 0;
    const commitIfFull = async () => {
      if (pendingOps >= 450) {
        await batch.commit();
        batch = db.batch();
        pendingOps = 0;
      }
    };
    const remapField = async (query, buildUpdate) => {
      const snapshot = await query.get();
      for (const doc of snapshot.docs) {
        batch.update(doc.ref, buildUpdate(doc));
        pendingOps++;
        await commitIfFull();
      }
      return snapshot.size;
    };
    // Array fields swap the id in place (computed in JS — Firestore can't
    // arrayRemove + arrayUnion the same field in one update) and dedupe in
    // case both accounts were already in the array
    const remapArrayField = async (query, field, extraUpdates = null) => {
      const snapshot = await query.get();
      for (const doc of snapshot.docs) {
        const current = field.split('.').reduce((obj, key) => (obj || {})[key], doc.data()) || [];
        const remapped = [...new Set(current.map(id => id === secondaryAccountId ? primaryAccountId : id))];
        const updates = { [field]: remapped, ...(extraUpdates ? extraUpdates(remapped) : {}) };
        batch.update(doc.ref, updates);
        pendingOps++;
        await commitIfFull();
      }
      return snapshot.size;
    };

    const now = new Date().toISOString();
    const remapped = {};

    // Ownership + authorship
    remapped.circles = await remapField(
      db.collection(COLLECTIONS.CIRCLES).where('owner', '==', secondaryAccountId),
      () => ({ owner: primaryAccountId, updatedAt: now }));
    remapped.places = await remapField(
      db.collection(COLLECTIONS.PLACES).where('addedBy', '==', secondaryAccountId),
      () => ({ addedBy: primaryAccountId, updatedAt: now }));
    remapped.comments = await remapField(
      db.collection('placeComments').where('userId', '==', secondaryAccountId),
      () => ({ userId: primaryAccountId }));
    remapped.activities = await remapField(
      db.collection(COLLECTIONS.ACTIVITIES).where('actorId', '==', secondaryAccountId),
      () => ({ actorId: primaryAccountId }));
    remapped.messages = await remapField(
      db.collection('messages').where('senderId', '==', secondaryAccountId),
      () => ({ senderId: primaryAccountId }));

    // Connections (both directions)
    remapped.connections = await remapField(
      db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', secondaryAccountId),
      () => ({ userId: primaryAccountId }));
    remapped.connections += await remapField(
      db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', secondaryAccountId),
      () => ({ connectedUserId: primaryAccountId }));

    // Array memberships: circle shares, venue likes/contributors, social graph
    remapped.sharedCircles = await remapArrayField(
      db.collection(COLLECTIONS.CIRCLES).where('sharedWith', 'array-contains', secondaryAccountId),
      'sharedWith');
    remapped.venueLikes = await remapArrayField(
      db.collection('globalPlaces').where('likes', 'array-contains', secondaryAccountId),
      'likes',
      likes => ({ likesCount: likes.length })); // Deduped count when both ids had liked
    remapped.venueContributions = await remapArrayField(
      db.collection('globalPlaces').where('userContributions.contributors', 'array-contains', secondaryAccountId),
      'userContributions.contributors');
    remapped.followerRefs = await remapArrayField(
      db.collection(COLLECTIONS.USERS).where('followers', 'array-contains', secondaryAccountId),
      'followers');
    remapped.followingRefs = await remapArrayField(
      db.collection(COLLECTIONS.USERS).where('following', 'array-contains', secondaryAccountId),
      'following');

    if (pendingOps > 0) {
      await batch.commit();
    }
    console.log('🔄 Reference remap complete:', remapped);

    // Finalize the user docs last, so a crash mid-remap leaves the merge
    // re-runnable rather than half-marked
    await db.runTransaction(async (transaction) => {
      transaction.update(primaryRef, mergedData);
      transaction.update(secondaryRef, {
        mergedInto: primaryAccountId,
        mergedAt: new Date().toISOString(),
        active: false
      });
    });
    
    console.log(`✅ Successfully merged ${secondaryAccountId} into ${primaryAccountId}`);
    
    // Get updated primary user
    const updatedPrimaryDoc = await primaryRef.get();
    const updatedUser = serializeDoc(updatedPrimaryDoc);
    
    res.status(200).json({
      success: true,
      message: 'Accounts merged successfully',
      primaryAccount: updatedUser,
      mergedData: {
        alternateEmailsAdded: mergedData.alternateEmails.filter(email => !(primaryUser.alternateEmails || []).includes(email)),
        providersLinked: Object.keys(secondaryUser.linkedProviders || {}),
        followersAdded: (secondaryUser.followers || []).length,
        followingAdded: (secondaryUser.following || []).length
      }
    });
    
  } catch (error) {
    console.error('Error merging accounts:', error);
    next(error);
  }
};
