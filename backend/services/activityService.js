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
    let circlePrivacy = 'private';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
    }
    
    // Only create activity for public and myNetwork circles
    // Private circles should not generate activities
    if (circlePrivacy !== 'private') {
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
    }

    // Only create connection activities and notifications for non-private circles
    if (circlePrivacy !== 'private') {
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
        const connectionData = doc.data();
        const connectionRef = doc.ref;
        
        // Determine the other user's ID in this connection
        const otherUserId = connectionData.userId === createdByUserId 
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
        }
        // Private circles already excluded above
        
        if (shouldShowActivity) {
          const activity = {
            type: 'circle',
            entityId: circleId,
            entityName: circleName,
            createdAt: new Date().toISOString(),
            viewedBy: [createdByUserId] // Creator has already "viewed" their own activity
          };
          
          // Update connection with new activity
          batch.update(connectionRef, {
            hasNewActivity: true,
            recentActivity: admin.firestore.FieldValue.arrayUnion(activity),
            updatedAt: new Date().toISOString()
          });
        }
      });

      await batch.commit();
      // Circle creation activity tracked
      
      // Send real-time SSE events to connections who should see this activity
      allConnections.forEach(doc => {
        const connectionData = doc.data();
        const otherUserId = connectionData.userId === createdByUserId 
          ? connectionData.connectedUserId 
          : connectionData.userId;
        
        // Check if this connection should see the activity based on circle privacy
        let shouldShowActivity = false;
        if (circlePrivacy === 'public' || circlePrivacy === 'myNetwork') {
          shouldShowActivity = true;
        }
        
        if (shouldShowActivity) {
          // Send circle creation event
          SSEService.sendEvent(otherUserId, {
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
          SSEService.sendEvent(otherUserId, {
            type: 'connection_activity',
            data: {
              connectionId: doc.id,
              activityType: 'circle',
              entityId: circleId,
              entityName: circleName,
              timestamp: new Date().toISOString()
            }
          });
        }
      });
    }
    
  } catch (error) {
    console.error('Error tracking circle creation:', error);
  }
};

// Track when a user adds a new place
const trackPlaceAdded = async (placeId, circleId, placeName, circleName, addedByUserId) => {
  try {
    // Get the circle to check privacy settings first
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    if (!circleDoc.exists) {
      console.log('Circle not found, skipping activity tracking');
      return;
    }
    
    const circleData = circleDoc.data();
    const circlePrivacy = circleData.privacy || 'private';
    const sharedWith = circleData.sharedWith || [];
    
    // Only create activity record for non-private circles
    if (circlePrivacy !== 'private') {
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
    }
    
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
      }
      // Private circles NEVER generate activities, per user requirements
      
      // Only update connections who should see this activity
      if (shouldShowActivity) {
        const activity = {
          type: 'place',
          entityId: placeId,
          entityName: placeName || 'Unknown Place',
          circleId: circleId,
          circleName: circleName || 'Unknown Circle',
          createdAt: new Date().toISOString(),
          viewedBy: [addedByUserId] // Creator has already "viewed" their own activity
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
    // Place addition activity tracked
    
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
      }
      // Private circles NEVER generate SSE events, per user requirements
      
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
      
      // Mark all activities as viewed by this user
      const connectionData = connectionSnapshot.docs[0].data();
      const updatedActivities = (connectionData.recentActivity || []).map(activity => {
        // Add viewer to viewedBy array if not already present
        if (!activity.viewedBy || !activity.viewedBy.includes(userId)) {
          return {
            ...activity,
            viewedBy: [...(activity.viewedBy || []), userId]
          };
        }
        return activity;
      });
      
      await connectionRef.update({
        hasNewActivity: false,
        recentActivity: updatedActivities,
        updatedAt: new Date().toISOString()
      });
      
      // Activity notification cleared
    }
  } catch (error) {
    console.error('Error clearing activity notification:', error);
  }
};

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
        
        // Circle activities marked as viewed
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
        
        // Place marked as viewed
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

    // Get circle details and privacy settings
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    let circlePrivacy = 'private';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
    }

    // Only track likes for public and myNetwork circles
    // Private circles should never generate like activities
    if (circlePrivacy !== 'private') {
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

      // Circle like activity tracked
    }
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

    // Get circle details and privacy settings
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    let circlePrivacy = 'private';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
    }

    // Only track comments for public and myNetwork circles
    // Private circles should never generate comment activities
    if (circlePrivacy !== 'private') {
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

      // Circle comment activity tracked
    }
  } catch (error) {
    console.error('Error tracking circle comment:', error);
  }
};

// Mark a specific circle's activities as viewed
const markCircleActivitiesAsViewed = async (userId, circleId) => {
  try {
    // Get all connections for this user
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);

    const batch = db.batch();
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    let updateCount = 0;

    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const recentActivity = connectionData.recentActivity || [];
      
      // Update activities for this circle
      const updatedActivities = recentActivity.map(activity => {
        // Mark place activities in this circle as viewed
        if (activity.type === 'place' && activity.circleId === circleId) {
          if (!activity.viewedBy || !activity.viewedBy.includes(userId)) {
            return {
              ...activity,
              viewedBy: [...(activity.viewedBy || []), userId]
            };
          }
        }
        // Mark circle creation activity as viewed
        else if (activity.type === 'circle' && activity.entityId === circleId) {
          if (!activity.viewedBy || !activity.viewedBy.includes(userId)) {
            return {
              ...activity,
              viewedBy: [...(activity.viewedBy || []), userId]
            };
          }
        }
        return activity;
      });

      // Only update if something changed
      if (JSON.stringify(updatedActivities) !== JSON.stringify(recentActivity)) {
        batch.update(doc.ref, {
          recentActivity: updatedActivities,
          updatedAt: new Date().toISOString()
        });
        updateCount++;
      }
    });

    if (updateCount > 0) {
      await batch.commit();
      // Circle activities marked as viewed
    }
  } catch (error) {
    console.error('Error marking circle activities as viewed:', error);
  }
};

// Mark a specific place as viewed
const markPlaceAsViewed = async (userId, placeId, circleId) => {
  try {
    // Get all connections for this user
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);

    const batch = db.batch();
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    let updateCount = 0;

    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const recentActivity = connectionData.recentActivity || [];
      
      // Update activities for this place
      const updatedActivities = recentActivity.map(activity => {
        if (activity.type === 'place' && activity.entityId === placeId) {
          if (!activity.viewedBy || !activity.viewedBy.includes(userId)) {
            return {
              ...activity,
              viewedBy: [...(activity.viewedBy || []), userId]
            };
          }
        }
        return activity;
      });

      // Only update if something changed
      if (JSON.stringify(updatedActivities) !== JSON.stringify(recentActivity)) {
        batch.update(doc.ref, {
          recentActivity: updatedActivities,
          updatedAt: new Date().toISOString()
        });
        updateCount++;
      }
    });

    if (updateCount > 0) {
      await batch.commit();
      // Place marked as viewed
    }
  } catch (error) {
    console.error('Error marking place as viewed:', error);
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
  cleanupOldActivity,
  markCircleActivitiesAsViewed,
  markPlaceAsViewed
};