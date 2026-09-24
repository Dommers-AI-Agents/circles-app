// backend/services/sseService.js
const { getFirestore } = require('../config/firebase');
const { chunk } = require('../utils/firestoreChunks');
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

    // Listen for new notifications
    const notificationListener = db.collection(COLLECTIONS.NOTIFICATIONS)
      .where('userId', '==', userId)
      .where('read', '==', false)
      .orderBy('createdAt', 'desc')
      .limit(1)
      .onSnapshot((snapshot) => {
        snapshot.docChanges().forEach(change => {
          if (change.type === 'added') {
            const notification = { id: change.doc.id, ...change.doc.data() };
            console.log(`📡 SSE: New notification for user ${userId}:`, notification.type);
            this.sendEvent(userId, {
              type: 'new_notification',
              data: notification,
              timestamp: new Date().toISOString()
            });
            
            // Also send a notification count update
            // Get unread count for badge update
            db.collection(COLLECTIONS.NOTIFICATIONS)
              .where('userId', '==', userId)
              .where('read', '==', false)
              .get()
              .then(unreadSnapshot => {
                this.sendEvent(userId, {
                  type: 'notification_count',
                  data: { count: unreadSnapshot.size },
                  timestamp: new Date().toISOString()
                });
              })
              .catch(error => console.error(`📡 SSE: unread count failed for ${userId}:`, error.message));
          }
        });
      }, (error) => {
        // Needs the (read, userId, createdAt) composite index; without it
        // this logs once per SSE session instead of surfacing as an
        // unhandled stream error.
        console.error(`📡 SSE: notification listener failed for ${userId}:`, error.message);
      });
    unsubscribers.push(notificationListener);

    // Listen for new activities in user's network. The viewer context is
    // built once per session (and rebuilt when it goes stale) so every row
    // the listener sees is judged by the same gates as the feed: circle,
    // place, moment, check-in audience, and the actor's "who can see my
    // activity" grid. This push used to send every raw row to every
    // connection.
    const { buildViewerContext } = require('./viewerContext');
    const { filterActivitiesForViewer, loadActivityPrivacyByActor } = require('./activityPrivacy');
    const CTX_TTL_MS = 60 * 1000;
    let ctxCache = null;
    const viewerContextFor = async () => {
      if (!ctxCache || Date.now() - ctxCache.builtAt > CTX_TTL_MS) {
        ctxCache = { ctx: await buildViewerContext(userId), builtAt: Date.now() };
      }
      return ctxCache.ctx;
    };
    const gridCache = new Map(); // actorId → { settingsByActor, at }
    const settingsFor = async (actorId) => {
      const hit = gridCache.get(actorId);
      if (hit && Date.now() - hit.at < CTX_TTL_MS) return hit.settingsByActor;
      const settingsByActor = await loadActivityPrivacyByActor([actorId]);
      gridCache.set(actorId, { settingsByActor, at: Date.now() });
      return settingsByActor;
    };
    const mayShow = async (activity) => {
      const ctx = await viewerContextFor();
      const circleId = activity.targetType === 'circle' ? activity.targetId : activity.circleId;
      const circlesById = new Map();
      if (circleId) {
        const doc = await db.collection(COLLECTIONS.CIRCLES).doc(String(circleId)).get();
        if (doc.exists) circlesById.set(doc.id, doc.data());
      }
      return filterActivitiesForViewer({
        activities: [activity], viewerId: userId, viewerCtx: ctx, circlesById,
        settingsByActor: await settingsFor(activity.actorId)
      }).length === 1;
    };

    buildViewerContext(userId)
      .then(ctx => {
        ctxCache = { ctx, builtAt: Date.now() };
        const connectedUserIds = new Set(ctx.connections);
        connectedUserIds.add(userId); // Include self

        if (connectedUserIds.size > 0) {
          // Firestore caps 'in' at 30 values and a listener can't be
          // paged, so a well-connected user gets one listener per chunk
          // of connections (same chunking as the one-shot feed queries).
          // A listener error is logged, not thrown: an unhandled error
          // here used to take the whole SSE session's watches down.
          for (const idsChunk of chunk(Array.from(connectedUserIds))) {
            const activityListener = db.collection(COLLECTIONS.ACTIVITIES)
              .where('actorId', 'in', idsChunk)
              .orderBy('timestamp', 'desc')
              .limit(5)
              .onSnapshot((snapshot) => {
                snapshot.docChanges().forEach(change => {
                  if (change.type !== 'added') return;
                  const activity = { id: change.doc.id, ...change.doc.data() };
                  mayShow(activity)
                    .then(ok => {
                      if (!ok) return;
                      this.sendEvent(userId, {
                        type: 'new_activity',
                        data: activity,
                        timestamp: new Date().toISOString()
                      });
                    })
                    .catch(error => console.error(`📡 SSE: activity gate failed for ${userId}:`, error.message));
                });
              }, (error) => {
                console.error(`📡 SSE: activity listener failed for ${userId}:`, error.message);
              });
            unsubscribers.push(activityListener);
          }
        }
      })
      .catch(error => console.error(`📡 SSE: connection lookup failed for ${userId}:`, error.message));

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

  // Broadcast an event to every connected client (all users)
  broadcast(eventType, data) {
    this.clients.forEach((clientSet, userId) => {
      this.sendEvent(userId, {
        type: eventType,
        data: data,
        timestamp: new Date().toISOString()
      });
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

  // Broadcast video engagement updates to all connected clients
  broadcastVideoEngagement(videoId, eventType, data) {
    // Send to all connected clients
    this.clients.forEach((clientSet, userId) => {
      this.sendEvent(userId, {
        type: 'video_engagement_update',
        subType: eventType,
        videoId: videoId,
        data: data,
        timestamp: new Date().toISOString()
      });
    });
  }

  // Listen for video engagement for specific video
  listenToVideoEngagement(userId, videoId) {
    // This could be enhanced to create specific listeners for a video
    // For now, the broadcastVideoEngagement method will handle updates
    console.log(`📡 SSE: User ${userId} listening to video ${videoId} engagement`);
  }
}

// Export singleton instance
module.exports = new SSEService();