// backend/services/activityService.js
// Service for tracking user activity and interactions

const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const db = getFirestore();

// Import createActivity helper from activity controller
const { createActivity } = require('../controllers/activityController');

// Import SSE service for real-time notifications
const SSEService = require('./sseService');

// Track when a user adds a new circle
const trackCircleCreated = async (circleId, createdByUserId) => {
  try {
    // Get circle details
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
    }
    
    // Create activity record in the activities collection
    await createActivity(
      'circle_created',
      createdByUserId,
      'circle',
      circleId,
      circleName,
      {
        circleId: circleId,
        circleName: circleName
      }
    );

    // Get all connections of the user who created the circle (both directions)
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', createdByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', createdByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);

    const batch = db.batch();
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionRef = doc.ref;
      const activity = {
        type: 'circle',
        entityId: circleId,
        createdAt: new Date().toISOString()
      };
      
      // Update connection with new activity
      batch.update(connectionRef, {
        hasNewActivity: true,
        recentActivity: admin.firestore.FieldValue.arrayUnion(activity),
        updatedAt: new Date().toISOString()
      });
    });

    await batch.commit();
    console.log(`Tracked circle creation activity for ${allConnections.length} connections`);
    
    // Send real-time SSE events to all connections
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      // Determine which user should receive the notification
      const notifyUserId = connectionData.userId === createdByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Send circle creation event
      SSEService.sendEvent(notifyUserId, {
        type: 'circle_created',
        data: {
          circleId: circleId,
          circleName: circleName,
          createdByUserId: createdByUserId,
          connectionId: doc.id,
          timestamp: new Date().toISOString()
        }
      });
      
      // Also send connection activity event
      SSEService.sendEvent(notifyUserId, {
        type: 'connection_activity',
        data: {
          connectionId: doc.id,
          activityType: 'circle',
          entityId: circleId,
          entityName: circleName,
          timestamp: new Date().toISOString()
        }
      });
    });
    
  } catch (error) {
    console.error('Error tracking circle creation:', error);
  }
};

// Track when a user adds a new place
const trackPlaceAdded = async (placeId, circleId, placeName, circleName, addedByUserId) => {
  try {
    // Create activity record in the activities collection
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    let placePhoto = null;
    let placeAddress = null;
    
    if (placeDoc.exists) {
      const placeData = placeDoc.data();
      placePhoto = placeData.photos && placeData.photos.length > 0 ? placeData.photos[0] : null;
      placeAddress = placeData.address || null;
    }
    
    await createActivity(
      'place_added',
      addedByUserId,
      'place',
      placeId,
      placeName || 'Unknown Place',
      {
        circleId: circleId,
        circleName: circleName || 'Unknown Circle',
        placePhoto: placePhoto,
        placeAddress: placeAddress
      }
    );

    // Get the circle to check privacy settings and shared connections
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    if (!circleDoc.exists) {
      console.log('Circle not found, skipping activity tracking');
      return;
    }
    
    const circleData = circleDoc.data();
    const circlePrivacy = circleData.privacy || 'private';
    const sharedWith = circleData.sharedWith || [];
    
    // Get all connections of the user who added the place (both directions)
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', addedByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', addedByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);

    const batch = db.batch();
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    let updatedConnectionsCount = 0;
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const connectionRef = doc.ref;
      
      // Determine the other user's ID in this connection
      const otherUserId = connectionData.userId === addedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Check if this connection should see the activity based on circle privacy
      let shouldShowActivity = false;
      
      if (circlePrivacy === 'public') {
        // Public circles - all connections see the activity
        shouldShowActivity = true;
      } else if (circlePrivacy === 'myNetwork') {
        // My Network circles - all connections see the activity
        shouldShowActivity = true;
      } else if (circlePrivacy === 'private') {
        // Private circles - only if explicitly shared with this connection
        shouldShowActivity = sharedWith.includes(otherUserId);
      }
      
      // Only update connections who should see this activity
      if (shouldShowActivity) {
        const activity = {
          type: 'place',
          entityId: placeId,
          circleId: circleId,
          placeName: placeName || 'Unknown Place',
          circleName: circleName || 'Unknown Circle',
          createdAt: new Date().toISOString(),
          viewedAt: null // Track when this specific activity was viewed
        };
        
        // Update connection with new activity
        // Don't persist hasRecentPlace - it will be calculated dynamically
        batch.update(connectionRef, {
          hasNewActivity: true,
          // hasRecentPlace: true, // REMOVED - calculated dynamically in getConnections
          recentActivity: admin.firestore.FieldValue.arrayUnion(activity),
          updatedAt: new Date().toISOString()
        });
        
        updatedConnectionsCount++;
      }
    });

    await batch.commit();
    console.log(`Tracked place addition activity for ${updatedConnectionsCount} connections (out of ${allConnections.length} total connections)`);
    
    // Send real-time SSE events to connections who should see this activity
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === addedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Check if this connection should see the activity based on circle privacy  
      let shouldShowActivity = false;
      if (circlePrivacy === 'public' || circlePrivacy === 'myNetwork') {
        shouldShowActivity = true;
      } else if (circlePrivacy === 'private') {
        shouldShowActivity = sharedWith.includes(otherUserId);
      }
      
      if (shouldShowActivity) {
        // Send place added event
        SSEService.sendEvent(otherUserId, {
          type: 'place_added',
          data: {
            placeId: placeId,
            placeName: placeName || 'Unknown Place',
            circleId: circleId,
            circleName: circleName || 'Unknown Circle',
            addedByUserId: addedByUserId,
            connectionId: doc.id,
            timestamp: new Date().toISOString()
          }
        });
        
        // Also send connection activity event
        SSEService.sendEvent(otherUserId, {
          type: 'connection_activity',
          data: {
            connectionId: doc.id,
            activityType: 'place',
            entityId: placeId,
            entityName: placeName || 'Unknown Place',
            circleId: circleId,
            circleName: circleName || 'Unknown Circle',
            timestamp: new Date().toISOString()
          }
        });
      }
    });
    
  } catch (error) {
    console.error('Error tracking place addition:', error);
  }
};

// Track when a user views another user's circles or profile
const trackConnectionView = async (viewerUserId, viewedUserId) => {
  try {
    // Find the connection between these users
    const connectionSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', viewerUserId)
      .where('connectedUserId', '==', viewedUserId)
      .where('status', '==', 'accepted')
      .limit(1)
      .get();

    if (!connectionSnapshot.empty) {
      const connectionRef = connectionSnapshot.docs[0].ref;
      const now = new Date().toISOString();
      
      await connectionRef.update({
        lastViewedAt: now,
        viewCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now
      });
    }
  } catch (error) {
    console.error('Error tracking connection view:', error);
  }
};

// Clear activity notification (when user views the connection)
const clearActivityNotification = async (userId, connectedUserId) => {
  try {
    // Check both directions since connections can be stored either way
    const [connectionSnapshot1, connectionSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', connectedUserId)
        .limit(1)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', connectedUserId)
        .where('connectedUserId', '==', userId)
        .limit(1)
        .get()
    ]);

    // Update whichever direction exists
    const connectionSnapshot = !connectionSnapshot1.empty ? connectionSnapshot1 : connectionSnapshot2;

    if (!connectionSnapshot.empty) {
      const connectionRef = connectionSnapshot.docs[0].ref;
      
      // Clear activity indicators but keep activity history
      // Only clear hasNewActivity - hasRecentPlace is calculated dynamically
      await connectionRef.update({
        hasNewActivity: false,
        // hasRecentPlace is not persisted anymore - calculated from recentActivity
        // Don't clear recentActivity array - we need it for proper calculation
        updatedAt: new Date().toISOString()
      });
      
      console.log(`Cleared activity notification for connection between ${userId} and ${connectedUserId}`);
    } else {
      console.log(`No connection found between ${userId} and ${connectedUserId}`);
    }
  } catch (error) {
    console.error('Error clearing activity notification:', error);
  }
};

// Get all connections with sorting by view count and place count
const getConnectionsWithStats = async (userId) => {
  try {
    console.log(`Getting connections with stats for user: ${userId}`);
    
    // Get connections where user is either the requester or the target
    const connectionsQuery1 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted');
      
    const connectionsQuery2 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted');

    const [snapshot1, snapshot2] = await Promise.all([
      connectionsQuery1.get(),
      connectionsQuery2.get()
    ]);

    console.log(`Found ${snapshot1.size} connections as userId, ${snapshot2.size} as connectedUserId`);
    console.log(`User ID format: ${userId}, length: ${userId.length}`);

    // Combine results and remove duplicates
    const allDocs = [...snapshot1.docs, ...snapshot2.docs];
    const uniqueDocs = allDocs.filter((doc, index, self) => 
      index === self.findIndex(d => d.id === doc.id)
    );

    const connections = [];
    
    for (const doc of uniqueDocs) {
      const connectionData = doc.data();
      
      // Determine which user is the connected one
      const connectedUserId = connectionData.userId === userId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Get connected user details
      const userDoc = await db.collection(COLLECTIONS.USERS)
        .doc(connectedUserId)
        .get();
      
      if (userDoc.exists) {
        console.log(`Processing connection with user: ${connectedUserId}`);
        
        // Get total places count for this user
        const userCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
          .where('owner', '==', connectedUserId)
          .get();
        
        let totalPlaces = 0;
        for (const circleDoc of userCirclesSnapshot.docs) {
          const circleData = circleDoc.data();
          totalPlaces += (circleData.places || []).length;
        }
        
        // Check for recent activity using real-time SSE approach (no lastLogin dependency)
        // Show activity for places added within the last 24 hours
        let hasRecentPlace = false;
        const twentyFourHoursAgo = new Date();
        twentyFourHoursAgo.setHours(twentyFourHoursAgo.getHours() - 24);
        
        if (connectionData.recentActivity && connectionData.recentActivity.length > 0) {
          hasRecentPlace = connectionData.recentActivity.some(activity => 
            activity.type === 'place' && 
            new Date(activity.createdAt) > twentyFourHoursAgo
          );
          console.log(`📅 SSE Activity check - recent places within 24h: ${hasRecentPlace}`);
        } else {
          console.log(`📅 No recent activity found for connection ${doc.id}`);
        }
        
        // Also check for recent circle creation
        const hasRecentCircle = connectionData.recentActivity?.some(activity => 
          activity.type === 'circle' && 
          new Date(activity.createdAt) > twentyFourHoursAgo
        ) || false;
        
        // Show activity indicator for either places or circles
        const hasAnyRecentActivity = hasRecentPlace || hasRecentCircle;
        console.log(`📅 Combined activity check - places: ${hasRecentPlace}, circles: ${hasRecentCircle}, total: ${hasAnyRecentActivity}`);
        
        // Properly serialize the connection document
        const serializedConnection = serializeDoc(doc);
        const serializedUser = serializeDoc(userDoc);
        
        // Get last message info for this connection
        let lastMessageAt = null;
        let lastMessageSenderId = null;
        let hasRecentMessage = false;
        
        // Find conversations between current user and connected user
        const conversationQuery1 = db.collection(COLLECTIONS.CONVERSATIONS)
          .where('type', '==', 'direct')
          .where('participants', 'array-contains', userId)
          .get();
          
        const conversationSnapshot = await conversationQuery1;
        
        // Filter to find conversation with this specific connected user
        const conversation = conversationSnapshot.docs.find(doc => {
          const data = doc.data();
          return data.participants.includes(connectedUserId);
        });
        
        if (conversation) {
          const convData = conversation.data();
          if (convData.lastMessageTime) {
            lastMessageAt = convData.lastMessageTime;
            lastMessageSenderId = convData.lastMessageSenderId || null;
            
            // Check if message is recent (within last 7 days)
            const messageDate = new Date(convData.lastMessageTime);
            const sevenDaysAgo = new Date();
            sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
            hasRecentMessage = messageDate > sevenDaysAgo;
          }
        }
        
        // Ensure all fields have defaults for backwards compatibility
        connections.push({
          ...serializedConnection,
          connectedUser: serializedUser,
          totalPlaces: totalPlaces,
          hasRecentPlace: hasAnyRecentActivity,
          viewCount: serializedConnection.viewCount || 0,
          recentActivity: serializedConnection.recentActivity || [],
          hasNewActivity: serializedConnection.hasNewActivity || false,
          lastViewedAt: serializedConnection.lastViewedAt || null,
          lastMessageAt: lastMessageAt,
          lastMessageSenderId: lastMessageSenderId,
          hasRecentMessage: hasRecentMessage
        });
      }
    }

    // Sort connections by criteria - messages first, then activity
    connections.sort((a, b) => {
      // First priority: recent messages (most recent first)
      if (a.lastMessageAt && b.lastMessageAt) {
        // Both have messages - sort by most recent
        return new Date(b.lastMessageAt) - new Date(a.lastMessageAt);
      } else if (a.lastMessageAt) {
        return -1; // a has messages, b doesn't - a comes first
      } else if (b.lastMessageAt) {
        return 1; // b has messages, a doesn't - b comes first
      }
      
      // Second priority: recent activity (places or circles)
      const aHasActivity = a.hasRecentPlace || a.hasNewActivity;
      const bHasActivity = b.hasRecentPlace || b.hasNewActivity;
      if (aHasActivity !== bHasActivity) {
        return aHasActivity ? -1 : 1;
      }
      
      // Third priority: view count (only if user has viewed them)
      if ((a.viewCount > 0 || b.viewCount > 0) && a.viewCount !== b.viewCount) {
        return b.viewCount - a.viewCount;
      }
      
      // Fourth priority: total places count
      if (a.totalPlaces !== b.totalPlaces) {
        return b.totalPlaces - a.totalPlaces;
      }
      
      // Final: alphabetical by name
      const nameA = a.connectedUser.displayName || '';
      const nameB = b.connectedUser.displayName || '';
      return nameA.localeCompare(nameB);
    });

    console.log(`Returning ${connections.length} connections with stats`);
    return connections;
  } catch (error) {
    console.error('Error getting connections with stats:', error);
    return [];
  }
};

// Clean up old activity records (run periodically)
const cleanupOldActivity = async (daysToKeep = 30) => {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - daysToKeep);
    const cutoffDateStr = cutoffDate.toISOString();

    const connectionsSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('recentActivity', '!=', [])
      .get();

    const batch = db.batch();
    let updateCount = 0;

    connectionsSnapshot.docs.forEach(doc => {
      const data = doc.data();
      if (data.recentActivity && data.recentActivity.length > 0) {
        const filteredActivity = data.recentActivity.filter(
          activity => activity.createdAt > cutoffDateStr
        );
        
        if (filteredActivity.length !== data.recentActivity.length) {
          batch.update(doc.ref, {
            recentActivity: filteredActivity,
            updatedAt: new Date().toISOString()
          });
          updateCount++;
        }
      }
    });

    if (updateCount > 0) {
      await batch.commit();
      console.log(`Cleaned up old activity for ${updateCount} connections`);
    }
  } catch (error) {
    console.error('Error cleaning up old activity:', error);
  }
};

// Track when a user views a circle with new places
const trackCircleView = async (viewerUserId, circleId, connectionUserId) => {
  try {
    // Find the connection between these users
    const [connectionSnapshot1, connectionSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', viewerUserId)
        .where('connectedUserId', '==', connectionUserId)
        .where('status', '==', 'accepted')
        .limit(1)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', connectionUserId)
        .where('connectedUserId', '==', viewerUserId)
        .where('status', '==', 'accepted')
        .limit(1)
        .get()
    ]);

    const connectionSnapshot = !connectionSnapshot1.empty ? connectionSnapshot1 : connectionSnapshot2;

    if (!connectionSnapshot.empty) {
      const connectionRef = connectionSnapshot.docs[0].ref;
      const connectionData = connectionSnapshot.docs[0].data();
      
      // Mark activities for this circle as viewed
      if (connectionData.recentActivity && connectionData.recentActivity.length > 0) {
        const updatedActivities = connectionData.recentActivity.map(activity => {
          if (activity.circleId === circleId && activity.type === 'place' && !activity.viewedAt) {
            return { ...activity, viewedAt: new Date().toISOString() };
          }
          return activity;
        });
        
        await connectionRef.update({
          recentActivity: updatedActivities,
          updatedAt: new Date().toISOString()
        });
        
        console.log(`Marked circle ${circleId} activities as viewed for connection`);
      }
    }
  } catch (error) {
    console.error('Error tracking circle view:', error);
  }
};

// Track when a user views a specific place
const trackPlaceView = async (viewerUserId, placeId, connectionUserId) => {
  try {
    // Find the connection between these users
    const [connectionSnapshot1, connectionSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', viewerUserId)
        .where('connectedUserId', '==', connectionUserId)
        .where('status', '==', 'accepted')
        .limit(1)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', connectionUserId)
        .where('connectedUserId', '==', viewerUserId)
        .where('status', '==', 'accepted')
        .limit(1)
        .get()
    ]);

    const connectionSnapshot = !connectionSnapshot1.empty ? connectionSnapshot1 : connectionSnapshot2;

    if (!connectionSnapshot.empty) {
      const connectionRef = connectionSnapshot.docs[0].ref;
      const connectionData = connectionSnapshot.docs[0].data();
      
      // Mark this specific place activity as viewed
      if (connectionData.recentActivity && connectionData.recentActivity.length > 0) {
        const updatedActivities = connectionData.recentActivity.map(activity => {
          if (activity.entityId === placeId && activity.type === 'place' && !activity.viewedAt) {
            return { ...activity, viewedAt: new Date().toISOString() };
          }
          return activity;
        });
        
        await connectionRef.update({
          recentActivity: updatedActivities,
          updatedAt: new Date().toISOString()
        });
        
        console.log(`Marked place ${placeId} as viewed for connection`);
      }
    }
  } catch (error) {
    console.error('Error tracking place view:', error);
  }
};

// Track when a user likes a circle
const trackCircleLiked = async (circleId, likedByUserId, circleOwnerId) => {
  try {
    // Don't track if user likes their own circle
    if (likedByUserId === circleOwnerId) {
      return;
    }

    // Get circle details
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
    }

    // Create activity record
    await createActivity(
      'circle_liked',
      likedByUserId,
      'circle',
      circleId,
      circleName,
      {
        circleId: circleId,
        circleName: circleName,
        likedByUserId: likedByUserId
      }
    );

    // Send real-time notification to circle owner
    SSEService.sendEvent(circleOwnerId, {
      type: 'circle_liked',
      data: {
        circleId: circleId,
        circleName: circleName,
        likedByUserId: likedByUserId,
        timestamp: new Date().toISOString()
      }
    });

    console.log(`Tracked circle like activity: ${likedByUserId} liked circle ${circleId}`);
  } catch (error) {
    console.error('Error tracking circle like:', error);
  }
};

// Track when a user comments on a circle
const trackCircleCommented = async (circleId, commentedByUserId, circleOwnerId, commentText) => {
  try {
    // Don't track if user comments on their own circle
    if (commentedByUserId === circleOwnerId) {
      return;
    }

    // Get circle details
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
    }

    // Create activity record
    await createActivity(
      'circle_commented',
      commentedByUserId,
      'circle',
      circleId,
      circleName,
      {
        circleId: circleId,
        circleName: circleName,
        commentedByUserId: commentedByUserId,
        commentText: commentText.substring(0, 100) // Truncate long comments
      }
    );

    // Send real-time notification to circle owner
    SSEService.sendEvent(circleOwnerId, {
      type: 'circle_commented',
      data: {
        circleId: circleId,
        circleName: circleName,
        commentedByUserId: commentedByUserId,
        commentText: commentText.substring(0, 100),
        timestamp: new Date().toISOString()
      }
    });

    console.log(`Tracked circle comment activity: ${commentedByUserId} commented on circle ${circleId}`);
  } catch (error) {
    console.error('Error tracking circle comment:', error);
  }
};

module.exports = {
  trackCircleCreated,
  trackPlaceAdded,
  trackConnectionView,
  trackCircleView,
  trackPlaceView,
  trackCircleLiked,
  trackCircleCommented,
  clearActivityNotification,
  getConnectionsWithStats,
  cleanupOldActivity
};