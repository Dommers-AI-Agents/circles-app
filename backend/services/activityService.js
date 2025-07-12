// backend/services/activityService.js
// Service for tracking user activity and interactions

const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const db = getFirestore();

// Import createActivity helper from activity controller
const { createActivity } = require('../controllers/activityController');

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
    
    allConnections.forEach(doc => {
      const connectionRef = doc.ref;
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
    });

    await batch.commit();
    console.log(`Tracked place addition activity for ${allConnections.length} connections`);
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
        
        // Get the current user's lastLogin to check for new places since then
        const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
        const lastLogin = currentUserDoc.exists ? currentUserDoc.data().lastLogin : null;
        
        // Check if user added a place since the current user's last login
        let hasRecentPlace = false;
        
        if (lastLogin) {
          const lastLoginDate = new Date(lastLogin);
          hasRecentPlace = connectionData.recentActivity?.some(activity => 
            activity.type === 'place' && 
            new Date(activity.createdAt) > lastLoginDate
          ) || false;
          console.log(`📅 Activity check - places since ${lastLogin}: ${hasRecentPlace}`);
        } else {
          // No lastLogin, don't show activity indicators
          console.log(`⚠️ No lastLogin for user ${userId}, no activity indicators`);
          hasRecentPlace = false;
        }
        
        // Properly serialize the connection document
        const serializedConnection = serializeDoc(doc);
        const serializedUser = serializeDoc(userDoc);
        
        // Ensure all fields have defaults for backwards compatibility
        connections.push({
          ...serializedConnection,
          connectedUser: serializedUser,
          totalPlaces: totalPlaces,
          hasRecentPlace: hasRecentPlace,
          viewCount: serializedConnection.viewCount || 0,
          recentActivity: serializedConnection.recentActivity || [],
          hasNewActivity: serializedConnection.hasNewActivity || false,
          lastViewedAt: serializedConnection.lastViewedAt || null
        });
      }
    }

    // Sort connections by criteria
    connections.sort((a, b) => {
      // First priority: view count
      if (a.viewCount !== b.viewCount) {
        return b.viewCount - a.viewCount;
      }
      
      // Second priority: total places count
      if (a.totalPlaces !== b.totalPlaces) {
        return b.totalPlaces - a.totalPlaces;
      }
      
      // Third priority: recent place activity
      if (a.hasRecentPlace !== b.hasRecentPlace) {
        return a.hasRecentPlace ? -1 : 1;
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

module.exports = {
  trackCircleCreated,
  trackPlaceAdded,
  trackConnectionView,
  trackCircleView,
  trackPlaceView,
  clearActivityNotification,
  getConnectionsWithStats,
  cleanupOldActivity
};