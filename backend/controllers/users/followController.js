// backend/controllers/users/followController.js
// follow/unfollow, follower & following lists, follower-count repair
// Split out of firebaseUserController.js (handlers unchanged).
const { getFirestore, admin } = require('../../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');
const { normalizeUserId, isSameUser } = require('../../services/idService');
const { getPlaceCountMap } = require('../../services/userStatsCache');
const { buildConnectionMap } = require('../../services/connectionMap');

const db = getFirestore();

// @desc    Follow a user
// @route   POST /api/users/:id/follow
// @access  Private
exports.followUser = async (req, res, next) => {
  try {
    const targetUserId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('🔵 followUser called:', {
      targetUserIdOriginal: req.params.id,
      targetUserIdNormalized: targetUserId,
      currentUserIdOriginal: req.user.uid,
      currentUserIdNormalized: currentUserId,
      timestamp: new Date().toISOString()
    });
    
    // Can't follow yourself
    if (targetUserId === currentUserId) {
      return res.status(400).json({
        success: false,
        message: 'You cannot follow yourself'
      });
    }
    
    // Check if target user exists
    const targetUserRef = db.collection(COLLECTIONS.USERS).doc(targetUserId);
    const targetUserDoc = await targetUserRef.get();
    
    if (!targetUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    // Get current user - fetch fresh to ensure we have latest data
    const currentUserRef = db.collection(COLLECTIONS.USERS).doc(currentUserId);
    let currentUserDoc = await currentUserRef.get();
    
    if (!currentUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Current user not found'
      });
    }
    
    // Double-check by fetching again to ensure we have the absolute latest data
    // This helps avoid race conditions from rapid follow/unfollow actions
    await new Promise(resolve => setTimeout(resolve, 100)); // Small delay
    currentUserDoc = await currentUserRef.get();
    
    const currentUser = serializeDoc(currentUserDoc);
    const targetUser = serializeDoc(targetUserDoc);
    
    console.log('🔍 Current user following array BEFORE:', {
      userId: currentUserId,
      following: currentUser.following || [],
      followingCount: currentUser.followingCount || 0,
      followingLength: (currentUser.following || []).length,
      targetInArray: currentUser.following?.includes(targetUserId) || false,
      rawFollowingData: JSON.stringify(currentUser.following || [])
    });
    
    console.log('🔍 Target user followers array BEFORE:', {
      userId: targetUserId,
      followers: targetUser.followers || [],
      followersCount: targetUser.followersCount || 0,
      followersLength: (targetUser.followers || []).length,
      currentUserInArray: targetUser.followers?.includes(currentUserId) || false,
      rawFollowersData: JSON.stringify(targetUser.followers || [])
    });
    
    // Already following: succeed idempotently. Follow is a state, not an
    // event — surfaces like the notification "Follow back" button can't
    // always know the current state, and erroring on a no-op tap taught
    // users they'd done something wrong ("Error: you are already
    // following this user" on a legitimate tap).
    if (currentUser.following && currentUser.following.includes(targetUserId)) {
      return res.json({
        success: true,
        alreadyFollowing: true,
        message: 'Already following this user'
      });
    }
    
    // Initialize counts if they don't exist
    if (typeof currentUser.followingCount !== 'number') {
      console.log('⚠️ Initializing missing followingCount for user:', currentUserId);
      await currentUserRef.update({
        followingCount: (currentUser.following || []).length
      });
    }
    
    if (typeof targetUser.followersCount !== 'number') {
      console.log('⚠️ Initializing missing followersCount for user:', targetUserId);
      await targetUserRef.update({
        followersCount: (targetUser.followers || []).length
      });
    }
    
    // Update both users atomically with rollback capability
    const batch = db.batch();
    
    // Update current user's following list atomically
    batch.update(currentUserRef, {
      following: FieldValue.arrayUnion(targetUserId),
      followingCount: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });
    
    // Update target user's followers list atomically
    batch.update(targetUserRef, {
      followers: FieldValue.arrayUnion(currentUserId),
      followersCount: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });
    
    let followPiggyBank = null;
    try {
      await batch.commit();
      console.log('✅ Follow batch committed successfully');

      // Piggy bank: a dime for your first follow of this person, ever —
      // the already-following guard above plus the per-pair dedup key means
      // unfollow/refollow churn can't re-mint. Awaited for the coin-drop;
      // credit() never throws.
      followPiggyBank = await require('../../services/piggyBankService').credit({
        userId: currentUserId,
        eventType: 'user_followed',
        sourceRef: { followedUserId: targetUserId }
      });
    } catch (batchError) {
      console.error('❌ Follow batch failed, attempting rollback:', batchError);
      
      // Attempt rollback by reversing the operations
      try {
        const rollbackBatch = db.batch();
        
        // Remove the user from following if they were added
        rollbackBatch.update(currentUserRef, {
          following: FieldValue.arrayRemove(targetUserId),
          followingCount: FieldValue.increment(-1),
          updatedAt: new Date().toISOString()
        });
        
        // Remove the follower if they were added
        rollbackBatch.update(targetUserRef, {
          followers: FieldValue.arrayRemove(currentUserId),
          followersCount: FieldValue.increment(-1),
          updatedAt: new Date().toISOString()
        });
        
        await rollbackBatch.commit();
        console.log('✅ Follow rollback completed successfully');
      } catch (rollbackError) {
        console.error('❌ Follow rollback failed:', rollbackError);
        // Even rollback failed, log for manual intervention
        console.error('🚨 CRITICAL: Follow operation and rollback both failed for users:', {
          currentUserId,
          targetUserId,
          originalError: batchError.message,
          rollbackError: rollbackError.message,
          timestamp: new Date().toISOString()
        });
      }
      
      // Return error to client
      return res.status(500).json({
        success: false,
        message: 'Failed to follow user. Please try again.'
      });
    }
    
    // Get updated counts for SSE events
    const updatedCurrentUser = await currentUserRef.get();
    const updatedTargetUser = await targetUserRef.get();
    const currentUserData = serializeDoc(updatedCurrentUser);
    const targetUserData = serializeDoc(updatedTargetUser);
    
    // Validate array/count consistency after follow operation
    const followingArrayLength = (currentUserData.following || []).length;
    const followingCount = currentUserData.followingCount || 0;
    const followersArrayLength = (targetUserData.followers || []).length;
    const followersCount = targetUserData.followersCount || 0;
    
    console.log('🔍 Post-follow validation:', {
      currentUser: {
        id: currentUserId,
        followingArrayLength,
        followingCount,
        consistent: followingArrayLength === followingCount
      },
      targetUser: {
        id: targetUserId,
        followersArrayLength,
        followersCount,
        consistent: followersArrayLength === followersCount
      }
    });
    
    // Check for inconsistencies and repair if needed
    const followingInconsistent = followingArrayLength !== followingCount;
    const followersInconsistent = followersArrayLength !== followersCount;
    
    if (followingInconsistent || followersInconsistent) {
      console.error('❌ Follow operation resulted in inconsistent data:', {
        followingInconsistent,
        followersInconsistent,
        currentUserId,
        targetUserId
      });
      
      // Attempt to repair the inconsistency
      const repairBatch = db.batch();
      
      if (followingInconsistent) {
        console.log('🔧 Repairing following count for user:', currentUserId);
        repairBatch.update(currentUserRef, {
          followingCount: followingArrayLength,
          updatedAt: new Date().toISOString()
        });
      }
      
      if (followersInconsistent) {
        console.log('🔧 Repairing followers count for user:', targetUserId);
        repairBatch.update(targetUserRef, {
          followersCount: followersArrayLength,
          updatedAt: new Date().toISOString()
        });
      }
      
      await repairBatch.commit();
      console.log('✅ Inconsistency repair completed');
      
      // Re-fetch the corrected data
      const correctedCurrentUser = await currentUserRef.get();
      const correctedTargetUser = await targetUserRef.get();
      const correctedCurrentUserData = serializeDoc(correctedCurrentUser);
      const correctedTargetUserData = serializeDoc(correctedTargetUser);
      
      // Use corrected data for SSE events
      currentUserData.followingCount = correctedCurrentUserData.followingCount;
      targetUserData.followersCount = correctedTargetUserData.followersCount;
    }
    
    console.log('📊 After follow - Updated data:', {
      currentUser: {
        id: currentUserId,
        following: currentUserData.following || [],
        followingCount: currentUserData.followingCount || 0,
        followingLength: (currentUserData.following || []).length,
        targetNowInArray: currentUserData.following?.includes(targetUserId) || false,
        rawFollowingData: JSON.stringify(currentUserData.following || [])
      },
      targetUser: {
        id: targetUserId,
        followers: targetUserData.followers || [],
        followersCount: targetUserData.followersCount || 0,
        followersLength: (targetUserData.followers || []).length,
        currentUserNowInArray: targetUserData.followers?.includes(currentUserId) || false,
        rawFollowersData: JSON.stringify(targetUserData.followers || [])
      }
    });
    
    // Send notification to target user
    const notificationService = require('../../services/notificationService');
    await notificationService.sendFollowerNotification(
      targetUserId,
      currentUserId,
      currentUser.displayName
    );
    
    // Send SSE events to both users
    const sseService = require('../../services/sseService');
    
    // Notify current user about their new following
    sseService.notifyUser(currentUserId, 'following_added', {
      followingCount: currentUserData.followingCount || 0,
      following: currentUserData.following || [],
      targetUserId: targetUserId
    });
    
    // Notify target user about their new follower
    sseService.notifyUser(targetUserId, 'follower_added', {
      followersCount: targetUserData.followersCount || 0,
      followers: targetUserData.followers || [],
      followerId: currentUserId
    });
    
    // Return updated target user data including isFollowing status
    const responseUserData = {
      _id: targetUserId,
      email: targetUserData.email || '', // Include email field for iOS decoding with fallback
      displayName: targetUserData.displayName,
      profilePicture: targetUserData.profilePicture,
      bio: targetUserData.bio,
      location: targetUserData.location,
      createdAt: targetUserData.createdAt,
      followersCount: targetUserData.followersCount || 0,
      followingCount: targetUserData.followingCount || 0,
      isFollowing: true // Current user is now following this user
    };

    res.status(200).json({
      success: true,
      message: 'Successfully followed user',
      user: responseUserData,
      piggyBank: followPiggyBank
    });
    
  } catch (error) {
    console.error('Error following user:', error);
    next(error);
  }
};

// @desc    Unfollow a user
// @route   POST /api/users/:id/unfollow
// @access  Private
exports.unfollowUser = async (req, res, next) => {
  try {
    const targetUserId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('🔴 unfollowUser called:', {
      targetUserIdOriginal: req.params.id,
      targetUserIdNormalized: targetUserId,
      currentUserIdOriginal: req.user.uid,
      currentUserIdNormalized: currentUserId,
      timestamp: new Date().toISOString()
    });
    
    // Can't unfollow yourself
    if (targetUserId === currentUserId) {
      return res.status(400).json({
        success: false,
        message: 'You cannot unfollow yourself'
      });
    }
    
    // Get current user - fetch fresh to ensure we have latest data
    const currentUserRef = db.collection(COLLECTIONS.USERS).doc(currentUserId);
    let currentUserDoc = await currentUserRef.get();
    
    if (!currentUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Current user not found'
      });
    }
    
    // Double-check by fetching again to ensure we have the absolute latest data
    // This helps avoid race conditions from rapid follow/unfollow actions
    await new Promise(resolve => setTimeout(resolve, 100)); // Small delay
    currentUserDoc = await currentUserRef.get();
    
    // Get target user
    const targetUserRef = db.collection(COLLECTIONS.USERS).doc(targetUserId);
    const targetUserDoc = await targetUserRef.get();
    
    if (!targetUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const currentUser = serializeDoc(currentUserDoc);
    const targetUser = serializeDoc(targetUserDoc);
    
    console.log('🔍 Current user following array before unfollow:', {
      userId: currentUserId,
      following: currentUser.following || [],
      followingCount: currentUser.followingCount || 0,
      targetInArray: currentUser.following?.includes(targetUserId) || false
    });
    
    // Check if following
    if (!currentUser.following || !currentUser.following.includes(targetUserId)) {
      console.log('⚠️ User not following target:', {
        currentUserId,
        targetUserId,
        followingArray: currentUser.following || []
      });
      return res.status(400).json({
        success: false,
        message: 'You are not following this user'
      });
    }
    
    // Update both users atomically with rollback capability
    const batch = db.batch();
    
    // Update current user's following list atomically
    batch.update(currentUserRef, {
      following: FieldValue.arrayRemove(targetUserId),
      followingCount: FieldValue.increment(-1),
      updatedAt: new Date().toISOString()
    });
    
    // Update target user's followers list atomically
    batch.update(targetUserRef, {
      followers: FieldValue.arrayRemove(currentUserId),
      followersCount: FieldValue.increment(-1),
      updatedAt: new Date().toISOString()
    });
    
    try {
      await batch.commit();
      console.log('✅ Unfollow batch committed successfully');
    } catch (batchError) {
      console.error('❌ Unfollow batch failed, attempting rollback:', batchError);
      
      // Attempt rollback by reversing the operations
      try {
        const rollbackBatch = db.batch();
        
        // Re-add the user to following if they were removed
        rollbackBatch.update(currentUserRef, {
          following: FieldValue.arrayUnion(targetUserId),
          followingCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        });
        
        // Re-add the follower if they were removed
        rollbackBatch.update(targetUserRef, {
          followers: FieldValue.arrayUnion(currentUserId),
          followersCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        });
        
        await rollbackBatch.commit();
        console.log('✅ Unfollow rollback completed successfully');
      } catch (rollbackError) {
        console.error('❌ Unfollow rollback failed:', rollbackError);
        // Even rollback failed, log for manual intervention
        console.error('🚨 CRITICAL: Unfollow operation and rollback both failed for users:', {
          currentUserId,
          targetUserId,
          originalError: batchError.message,
          rollbackError: rollbackError.message,
          timestamp: new Date().toISOString()
        });
      }
      
      // Return error to client
      return res.status(500).json({
        success: false,
        message: 'Failed to unfollow user. Please try again.'
      });
    }
    
    // Get updated data for SSE events
    const updatedCurrentUser = await currentUserRef.get();
    const updatedTargetUser = await targetUserRef.get();
    const currentUserData = serializeDoc(updatedCurrentUser);
    const targetUserData = serializeDoc(updatedTargetUser);
    
    // Validate array/count consistency after unfollow operation
    const followingArrayLength = (currentUserData.following || []).length;
    const followingCount = currentUserData.followingCount || 0;
    const followersArrayLength = (targetUserData.followers || []).length;
    const followersCount = targetUserData.followersCount || 0;
    
    console.log('🔍 Post-unfollow validation:', {
      currentUser: {
        id: currentUserId,
        followingArrayLength,
        followingCount,
        consistent: followingArrayLength === followingCount
      },
      targetUser: {
        id: targetUserId,
        followersArrayLength,
        followersCount,
        consistent: followersArrayLength === followersCount
      }
    });
    
    // Check for inconsistencies and repair if needed
    const followingInconsistent = followingArrayLength !== followingCount;
    const followersInconsistent = followersArrayLength !== followersCount;
    
    if (followingInconsistent || followersInconsistent) {
      console.error('❌ Unfollow operation resulted in inconsistent data:', {
        followingInconsistent,
        followersInconsistent,
        currentUserId,
        targetUserId
      });
      
      // Attempt to repair the inconsistency
      const repairBatch = db.batch();
      
      if (followingInconsistent) {
        console.log('🔧 Repairing following count for user:', currentUserId);
        repairBatch.update(currentUserRef, {
          followingCount: followingArrayLength,
          updatedAt: new Date().toISOString()
        });
      }
      
      if (followersInconsistent) {
        console.log('🔧 Repairing followers count for user:', targetUserId);
        repairBatch.update(targetUserRef, {
          followersCount: followersArrayLength,
          updatedAt: new Date().toISOString()
        });
      }
      
      await repairBatch.commit();
      console.log('✅ Inconsistency repair completed');
      
      // Re-fetch the corrected data
      const correctedCurrentUser = await currentUserRef.get();
      const correctedTargetUser = await targetUserRef.get();
      const correctedCurrentUserData = serializeDoc(correctedCurrentUser);
      const correctedTargetUserData = serializeDoc(correctedTargetUser);
      
      // Use corrected data for SSE events
      currentUserData.followingCount = correctedCurrentUserData.followingCount;
      targetUserData.followersCount = correctedTargetUserData.followersCount;
    }
    
    console.log('📊 After unfollow - Updated data:', {
      currentUser: {
        id: currentUserId,
        following: currentUserData.following || [],
        followingCount: currentUserData.followingCount || 0,
        targetStillInArray: currentUserData.following?.includes(targetUserId) || false
      },
      targetUser: {
        id: targetUserId,
        followers: targetUserData.followers || [],
        followersCount: targetUserData.followersCount || 0,
        currentUserStillInArray: targetUserData.followers?.includes(currentUserId) || false
      }
    });
    
    // Send SSE events to both users
    const sseService = require('../../services/sseService');
    
    // Notify current user about removing following
    sseService.notifyUser(currentUserId, 'following_removed', {
      followingCount: currentUserData.followingCount || 0,
      following: currentUserData.following || [],
      targetUserId: targetUserId
    });
    
    // Notify target user about losing follower
    sseService.notifyUser(targetUserId, 'follower_removed', {
      followersCount: targetUserData.followersCount || 0,
      followers: targetUserData.followers || [],
      followerId: currentUserId
    });
    
    // Return updated target user data including isFollowing status
    const responseUserData = {
      _id: targetUserId,
      email: targetUserData.email || '', // Include email field for iOS decoding with fallback
      displayName: targetUserData.displayName,
      profilePicture: targetUserData.profilePicture,
      bio: targetUserData.bio,
      location: targetUserData.location,
      createdAt: targetUserData.createdAt,
      followersCount: targetUserData.followersCount || 0,
      followingCount: targetUserData.followingCount || 0,
      isFollowing: false // Current user is no longer following this user
    };

    res.status(200).json({
      success: true,
      message: 'Successfully unfollowed user',
      user: responseUserData
    });
    
  } catch (error) {
    console.error('Error unfollowing user:', error);
    next(error);
  }
};

// @desc    Get user's followers (owner only)
// @route   GET /api/users/:id/followers
// @access  Private
exports.getUserFollowers = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('👥 getUserFollowers called:', {
      userIdOriginal: req.params.id,
      userIdNormalized: userId,
      currentUserIdOriginal: req.user.uid,
      currentUserIdNormalized: currentUserId
    });
    
    // Allow any authenticated user to view followers lists
    // This enables social discovery through connections' networks
    
    // Get user
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const user = serializeDoc(userDoc);
    const followerIds = user.followers || [];
    
    // Get current user's following list to determine isFollowing status
    let currentUserFollowing = [];
    if (currentUserId !== userId) {
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
      if (currentUserDoc.exists) {
        const currentUserData = serializeDoc(currentUserDoc);
        currentUserFollowing = (currentUserData.following || []).map(id => normalizeUserId(id));
      }
    } else {
      // If viewing own followers, use the profile owner's following list
      currentUserFollowing = (user.following || []).map(id => normalizeUserId(id));
    }
    
    // Get follower details with batch fetching for performance
    const followers = [];
    
    if (followerIds.length > 0) {
      // Normalize all follower IDs
      const normalizedFollowerIds = followerIds.map(id => normalizeUserId(id));
      
      // Batch fetch all followers in chunks of 10 (Firestore limit for 'in' queries)
      const chunkSize = 10;
      for (let i = 0; i < normalizedFollowerIds.length; i += chunkSize) {
        const chunk = normalizedFollowerIds.slice(i, i + chunkSize);
        
        const followersSnapshot = await db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', chunk)
          .get();
        
        followersSnapshot.forEach(doc => {
          const follower = serializeDoc(doc);
          // Check if current user is following this follower
          const normalizedFollowerId = normalizeUserId(follower.id);
          const isFollowing = currentUserFollowing.includes(normalizedFollowerId);
          
          followers.push({
            id: normalizeUserId(follower.id), // Always return normalized ID
            email: follower.email || '', // Include email field for iOS decoding
            displayName: follower.displayName,
            profilePicture: follower.profilePicture || null,
            bio: follower.bio || null,
            firstName: follower.firstName || null,
            lastName: follower.lastName || null,
            isFollowing: isFollowing
          });
        });
      }
      
      // Log any missing followers
      const foundIds = followers.map(f => f.id);
      const missingIds = normalizedFollowerIds.filter(id => !foundIds.includes(id));
      if (missingIds.length > 0) {
        console.warn('⚠️ Followers not found:', missingIds);
      }
    }
    
    res.status(200).json({
      success: true,
      count: followers.length,
      followers: followers
    });
    
  } catch (error) {
    console.error('Error fetching followers:', error);
    next(error);
  }
};

// @desc    Get user's following (owner only)
// @route   GET /api/users/:id/following
// @access  Private
exports.getUserFollowing = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('👥 getUserFollowing called:', {
      userIdOriginal: req.params.id,
      userIdNormalized: userId,
      currentUserIdOriginal: req.user.uid,
      currentUserIdNormalized: currentUserId
    });
    
    // Allow any authenticated user to view following lists
    // This enables social discovery through connections' networks
    
    // Get user
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const user = serializeDoc(userDoc);
    const followingIds = user.following || [];

    // Get current user's following list to determine isFollowing status.
    // We also need the caller's own followers (for followsYou), their
    // connection map (so a row can show Connect / Requested / Message rather
    // than assuming every followed person is a stranger), and place counts —
    // without these the client can't tell a one-way follow from a mutual one.
    let currentUserFollowing = [];
    let callerFollowers = new Set();
    const [connectionMap, placeCounts] = await Promise.all([
      buildConnectionMap(currentUserId),
      getPlaceCountMap()
    ]);

    if (currentUserId !== userId) {
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
      if (currentUserDoc.exists) {
        const currentUserData = serializeDoc(currentUserDoc);
        currentUserFollowing = (currentUserData.following || []).map(id => normalizeUserId(id));
        callerFollowers = new Set((currentUserData.followers || []).map(id => normalizeUserId(id)));
      }
    } else {
      // If viewing own following list, all users are followed by definition
      currentUserFollowing = followingIds.map(id => normalizeUserId(id));
      callerFollowers = new Set((user.followers || []).map(id => normalizeUserId(id)));
    }

    // Get following details with batch fetching for performance
    const following = [];
    
    if (followingIds.length > 0) {
      // Normalize all following IDs
      const normalizedFollowingIds = followingIds.map(id => normalizeUserId(id));
      
      // Batch fetch all following users in chunks of 10 (Firestore limit for 'in' queries)
      const chunkSize = 10;
      for (let i = 0; i < normalizedFollowingIds.length; i += chunkSize) {
        const chunk = normalizedFollowingIds.slice(i, i + chunkSize);
        
        const followingSnapshot = await db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', chunk)
          .get();
        
        followingSnapshot.forEach(doc => {
          const followingUser = serializeDoc(doc);
          // Check if current user is following this user
          const normalizedFollowingUserId = normalizeUserId(followingUser.id);
          const isFollowing = currentUserFollowing.includes(normalizedFollowingUserId);
          
          const conn = connectionMap.get(normalizedFollowingUserId) || {};
          const counts = placeCounts.get(normalizedFollowingUserId) || { placesCount: 0, circlesCount: 0 };

          following.push({
            id: normalizedFollowingUserId, // Always return normalized ID
            email: followingUser.email || '', // Include email field for iOS decoding
            displayName: followingUser.displayName,
            profilePicture: followingUser.profilePicture || null,
            bio: followingUser.bio || null,
            location: followingUser.location || null,
            firstName: followingUser.firstName || null,
            lastName: followingUser.lastName || null,
            isFollowing: isFollowing,
            // Mutual-follow detection: without this the client shows every
            // followed person as a one-way follow and never offers Connect.
            followsYou: callerFollowers.has(normalizedFollowingUserId),
            connectionStatus: conn.status || 'none',
            connectionDirection: conn.direction || null,
            connectionId: conn.connectionId || null,
            placesCount: counts.placesCount,
            circlesCount: counts.circlesCount,
            // Carried so decorateUserCards can use the cached assumption
            // without re-reading the user doc
            assumedLocation: followingUser.assumedLocation || null,
            // Carried so decorateUserCards can honor the show-my-city pref
            preferences: followingUser.preferences || null
          });
        });
      }

      // Fill a missing location with the city assumed from their places
      const { decorateUserCards } = require('../../services/userCardEnrichment');
      await decorateUserCards(following, { activityReason: false });
      
      // Log any missing following users
      const foundIds = following.map(f => f.id);
      const missingIds = normalizedFollowingIds.filter(id => !foundIds.includes(id));
      if (missingIds.length > 0) {
        console.warn('⚠️ Following users not found:', missingIds);
      }
    }
    
    res.status(200).json({
      success: true,
      count: following.length,
      following: following
    });
    
  } catch (error) {
    console.error('Error fetching following:', error);
    next(error);
  }
};

// @desc    Recalculate follower/following counts for a user
// @route   POST /api/users/:id/recalculate-counts
// @access  Private (Admin or owner only)
exports.recalculateFollowerCounts = async (req, res, next) => {
  try {
    const targetUserId = normalizeUserId(req.params.id);
    const currentUserId = normalizeUserId(req.user.uid);
    
    console.log('🔄 recalculateFollowerCounts called:', {
      targetUserId,
      currentUserId,
      isOwner: isSameUser(targetUserId, currentUserId)
    });
    
    // Only allow user to recalculate their own counts
    // TODO: Add admin check for admin users
    if (!isSameUser(targetUserId, currentUserId)) {
      return res.status(403).json({
        success: false,
        message: 'You can only recalculate your own follower counts'
      });
    }
    
    // Get the user document
    const userRef = db.collection(COLLECTIONS.USERS).doc(targetUserId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const userData = userDoc.data();
    
    // Calculate actual counts from arrays
    const actualFollowersCount = (userData.followers || []).length;
    const actualFollowingCount = (userData.following || []).length;
    
    // Get current counts
    const currentFollowersCount = userData.followersCount || 0;
    const currentFollowingCount = userData.followingCount || 0;
    
    console.log('📊 Count comparison:', {
      currentFollowersCount,
      actualFollowersCount,
      currentFollowingCount,
      actualFollowingCount,
      needsUpdate: currentFollowersCount !== actualFollowersCount || currentFollowingCount !== actualFollowingCount
    });
    
    // Update the counts
    await userRef.update({
      followersCount: actualFollowersCount,
      followingCount: actualFollowingCount,
      updatedAt: new Date().toISOString()
    });
    
    // Return the updated user data
    const updatedUserDoc = await userRef.get();
    const updatedUser = serializeDoc(updatedUserDoc);
    
    res.status(200).json({
      success: true,
      message: 'Follower counts recalculated successfully',
      previousCounts: {
        followers: currentFollowersCount,
        following: currentFollowingCount
      },
      updatedCounts: {
        followers: actualFollowersCount,
        following: actualFollowingCount
      },
      user: {
        id: updatedUser.id,
        displayName: updatedUser.displayName,
        email: updatedUser.email,
        followersCount: updatedUser.followersCount,
        followingCount: updatedUser.followingCount
      }
    });
    
  } catch (error) {
    console.error('Error recalculating follower counts:', error);
    next(error);
  }
};
