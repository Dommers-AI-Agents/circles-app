// backend/services/sseService.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

class SSEService {
  constructor() {
    this.clients = new Map(); // userId -> Set of response objects
    this.listeners = new Map(); // userId -> Firestore unsubscribe functions
  }

  // Add a new SSE client
  addClient(userId, res) {
    console.log(`📡 SSE: Adding client for user ${userId}`);
    
    // Set SSE headers
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*'
    });

    // Send initial connection message
    res.write(`data: ${JSON.stringify({ type: 'connected', message: 'SSE connection established' })}\n\n`);

    // Add client to map
    if (!this.clients.has(userId)) {
      this.clients.set(userId, new Set());
    }
    this.clients.get(userId).add(res);

    // Set up Firestore listeners for this user
    this.setupListeners(userId);

    // Handle client disconnect
    res.on('close', () => {
      console.log(`📡 SSE: Client disconnected for user ${userId}`);
      this.removeClient(userId, res);
    });

    // Send heartbeat every 30 seconds to keep connection alive
    const heartbeat = setInterval(() => {
      try {
        res.write(`:heartbeat\n\n`);
      } catch (error) {
        clearInterval(heartbeat);
        this.removeClient(userId, res);
      }
    }, 30000);

    // Store heartbeat interval on response object for cleanup
    res.heartbeatInterval = heartbeat;
  }

  // Remove SSE client
  removeClient(userId, res) {
    const clients = this.clients.get(userId);
    if (clients) {
      clients.delete(res);
      
      // Clear heartbeat interval
      if (res.heartbeatInterval) {
        clearInterval(res.heartbeatInterval);
      }

      // If no more clients for this user, remove listeners
      if (clients.size === 0) {
        this.clients.delete(userId);
        this.removeListeners(userId);
      }
    }
  }

  // Set up Firestore listeners for real-time updates
  setupListeners(userId) {
    if (this.listeners.has(userId)) {
      return; // Listeners already set up
    }

    const unsubscribers = [];

    // Listen for new connection requests
    const connectionListener = db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'pending')
      .onSnapshot((snapshot) => {
        snapshot.docChanges().forEach(change => {
          if (change.type === 'added') {
            const connection = { id: change.doc.id, ...change.doc.data() };
            this.sendEvent(userId, {
              type: 'connection_request',
              data: connection,
              timestamp: new Date().toISOString()
            });
          }
        });
      });
    unsubscribers.push(connectionListener);

    // Listen for connection status changes (for requests sent by this user)
    const sentConnectionListener = db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .onSnapshot((snapshot) => {
        snapshot.docChanges().forEach(change => {
          if (change.type === 'modified') {
            const connection = { id: change.doc.id, ...change.doc.data() };
            if (connection.status === 'accepted') {
              this.sendEvent(userId, {
                type: 'connection_accepted',
                data: connection,
                timestamp: new Date().toISOString()
              });
            } else if (connection.status === 'declined') {
              this.sendEvent(userId, {
                type: 'connection_declined',
                data: connection,
                timestamp: new Date().toISOString()
              });
            }
          }
        });
      });
    unsubscribers.push(sentConnectionListener);

    // Listen for new messages
    const messageListener = db.collection(COLLECTIONS.MESSAGES)
      .where('recipientId', '==', userId)
      .where('read', '==', false)
      .orderBy('timestamp', 'desc')
      .limit(1)
      .onSnapshot((snapshot) => {
        snapshot.docChanges().forEach(change => {
          if (change.type === 'added') {
            const message = { id: change.doc.id, ...change.doc.data() };
            this.sendEvent(userId, {
              type: 'new_message',
              data: message,
              timestamp: new Date().toISOString()
            });
          }
        });
      });
    unsubscribers.push(messageListener);

    // Listen for follower changes
    const userListener = db.collection(COLLECTIONS.USERS)
      .doc(userId)
      .onSnapshot((snapshot) => {
        if (snapshot && snapshot.exists) {
          const data = snapshot.data();
          const previousData = (snapshot.metadata && snapshot.metadata.hasPendingWrites) ? null : snapshot.data();
          
          // Check for follower/following changes
          if (previousData) {
            const prevFollowersCount = previousData.followersCount || 0;
            const currFollowersCount = data.followersCount || 0;
            const prevFollowingCount = previousData.followingCount || 0;
            const currFollowingCount = data.followingCount || 0;
            
            if (prevFollowersCount < currFollowersCount) {
              this.sendEvent(userId, {
                type: 'follower_added',
                data: {
                  followersCount: currFollowersCount,
                  followers: data.followers || []
                },
                timestamp: new Date().toISOString()
              });
            } else if (prevFollowersCount > currFollowersCount) {
              this.sendEvent(userId, {
                type: 'follower_removed',
                data: {
                  followersCount: currFollowersCount,
                  followers: data.followers || []
                },
                timestamp: new Date().toISOString()
              });
            }
            
            if (prevFollowingCount < currFollowingCount) {
              this.sendEvent(userId, {
                type: 'following_added',
                data: {
                  followingCount: currFollowingCount,
                  following: data.following || []
                },
                timestamp: new Date().toISOString()
              });
            } else if (prevFollowingCount > currFollowingCount) {
              this.sendEvent(userId, {
                type: 'following_removed',
                data: {
                  followingCount: currFollowingCount,
                  following: data.following || []
                },
                timestamp: new Date().toISOString()
              });
            }
          }
        }
      });
    unsubscribers.push(userListener);

    // Listen for new suggestions
    const suggestionListener = db.collection(COLLECTIONS.SUGGESTIONS)
      .where('toUserId', '==', userId)
      .where('isRead', '==', false)
      .orderBy('createdAt', 'desc')
      .limit(1)
      .onSnapshot((snapshot) => {
        snapshot.docChanges().forEach(change => {
          if (change.type === 'added') {
            const suggestion = { id: change.doc.id, ...change.doc.data() };
            this.sendEvent(userId, {
              type: 'new_suggestion',
              data: suggestion,
              timestamp: new Date().toISOString()
            });
          }
        });
      });
    unsubscribers.push(suggestionListener);

    // Listen for new activities in user's network
    // First, get user's connections to know which activities to listen for
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted')
      .get()
      .then(connections1 => {
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('connectedUserId', '==', userId)
          .where('status', '==', 'accepted')
          .get()
          .then(connections2 => {
            const connectedUserIds = new Set();
            connections1.docs.forEach(doc => connectedUserIds.add(doc.data().connectedUserId));
            connections2.docs.forEach(doc => connectedUserIds.add(doc.data().userId));
            connectedUserIds.add(userId); // Include self
            
            if (connectedUserIds.size > 0) {
              const userIdsArray = Array.from(connectedUserIds);
              
              // Listen for new activities from network
              const activityListener = db.collection(COLLECTIONS.ACTIVITIES)
                .where('actorId', 'in', userIdsArray)
                .orderBy('timestamp', 'desc')
                .limit(5)
                .onSnapshot((snapshot) => {
                  snapshot.docChanges().forEach(change => {
                    if (change.type === 'added') {
                      const activity = { id: change.doc.id, ...change.doc.data() };
                      this.sendEvent(userId, {
                        type: 'new_activity',
                        data: activity,
                        timestamp: new Date().toISOString()
                      });
                    }
                  });
                });
              unsubscribers.push(activityListener);
            }
          });
      });

    // Store unsubscribe functions
    this.listeners.set(userId, unsubscribers);
  }

  // Remove Firestore listeners
  removeListeners(userId) {
    const unsubscribers = this.listeners.get(userId);
    if (unsubscribers) {
      unsubscribers.forEach(unsubscribe => unsubscribe());
      this.listeners.delete(userId);
    }
  }

  // Send event to all clients for a user
  sendEvent(userId, event) {
    const clients = this.clients.get(userId);
    if (clients) {
      const eventData = `data: ${JSON.stringify(event)}\n\n`;
      
      // Send to all connected clients for this user
      clients.forEach(res => {
        try {
          res.write(eventData);
        } catch (error) {
          console.error(`📡 SSE: Error sending event to client:`, error);
          this.removeClient(userId, res);
        }
      });
    }
  }

  // Send event to specific user (called from other services)
  notifyUser(userId, eventType, data) {
    this.sendEvent(userId, {
      type: eventType,
      data: data,
      timestamp: new Date().toISOString()
    });
  }

  // Get connected users count
  getConnectedUsersCount() {
    return this.clients.size;
  }

  // Check if user is connected
  isUserConnected(userId) {
    return this.clients.has(userId) && this.clients.get(userId).size > 0;
  }
}

// Export singleton instance
module.exports = new SSEService();