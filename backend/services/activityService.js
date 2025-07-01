// backend/services/activityService.js
// Service for tracking user activity and interactions

const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const db = getFirestore();

// Track when a user adds a new circle
const trackCircleCreated = async (circleId, createdByUserId) => {
  try {
    // Get all connections of the user who created the circle
    const connectionsSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', createdByUserId)
      .where('status', '==', 'accepted')
      .get();

    const batch = db.batch();
    
    connectionsSnapshot.docs.forEach(doc => {
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
    console.log(`Tracked circle creation activity for ${connectionsSnapshot.size} connections`);
  } catch (error) {
    console.error('Error tracking circle creation:', error);
  }
};

// Track when a user adds a new place
const trackPlaceAdded = async (placeId, circleId, addedByUserId) => {
  try {
    // Get all connections of the user who added the place
    const connectionsSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', addedByUserId)
      .where('status', '==', 'accepted')
      .get();

    const batch = db.batch();
    
    connectionsSnapshot.docs.forEach(doc => {
      const connectionRef = doc.ref;
      const activity = {
        type: 'place',
        entityId: placeId,
        circleId: circleId,
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
    console.log(`Tracked place addition activity for ${connectionsSnapshot.size} connections`);
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
    const connectionSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('connectedUserId', '==', connectedUserId)
      .limit(1)
      .get();

    if (!connectionSnapshot.empty) {
      const connectionRef = connectionSnapshot.docs[0].ref;
      await connectionRef.update({
        hasNewActivity: false,
        recentActivity: [], // Clear recent activity after viewing
        updatedAt: new Date().toISOString()
      });
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
        
        // Check if user recently added a place (within last 7 days)
        const sevenDaysAgo = new Date();
        sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
        const hasRecentPlace = connectionData.recentActivity?.some(activity => 
          activity.type === 'place' && 
          new Date(activity.createdAt) > sevenDaysAgo
        ) || false;
        
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

module.exports = {
  trackCircleCreated,
  trackPlaceAdded,
  trackConnectionView,
  clearActivityNotification,
  getConnectionsWithStats,
  cleanupOldActivity
};