// backend/services/activity/stats.js
// Activity service — connection stats and activity cleanup.
// Split from services/activityService.js (Phase 6); that path is now a barrel.

const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');
const db = getFirestore();


// Get all connections with sorting by view count and place count
const getConnectionsWithStats = async (userId) => {
  try {
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

    // Connections found

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
        // Get total places count for this user
        const userCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
          .where('owner', '==', connectedUserId)
          .get();
        
        let totalPlaces = 0;
        for (const circleDoc of userCirclesSnapshot.docs) {
          const circleData = circleDoc.data();
          totalPlaces += (circleData.places || []).length;
        }
        
        // Check for unviewed activities (Instagram-style)
        const recentActivity = connectionData.recentActivity || [];
        const hasUnviewedActivity = recentActivity.some(activity => {
          // Check if this user hasn't viewed this activity yet
          const viewedBy = activity.viewedBy || [];
          return !viewedBy.includes(userId);
        });
        
        // Count unviewed activities by type
        const unviewedCounts = {
          places: 0,
          circles: 0,
          suggestions: 0
        };
        
        recentActivity.forEach(activity => {
          const viewedBy = activity.viewedBy || [];
          if (!viewedBy.includes(userId)) {
            if (activity.type === 'place') unviewedCounts.places++;
            else if (activity.type === 'circle') unviewedCounts.circles++;
            else if (activity.type === 'suggestion') unviewedCounts.suggestions++;
          }
        });
        
        // Calculate unviewed activities
        
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
          hasRecentPlace: hasUnviewedActivity, // Now means hasUnviewedActivity
          hasUnviewedActivity: hasUnviewedActivity,
          unviewedCounts: unviewedCounts,
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
      
      // Second priority: unviewed activity
      const aHasActivity = a.hasUnviewedActivity;
      const bHasActivity = b.hasUnviewedActivity;
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
      // Old activity cleaned up
    }
  } catch (error) {
    console.error('Error cleaning up old activity:', error);
  }
};

module.exports = {
  getConnectionsWithStats,
  cleanupOldActivity,
};
