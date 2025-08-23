// backend/services/notificationService.js
const { getFirestore, getMessaging } = require('../config/firebase');
const { COLLECTIONS, createNotification, validateNotification } = require('../models/FirestoreModels');
const emailService = require('./emailService');
const sseService = require('./sseService');

const db = getFirestore();
const messaging = getMessaging();

class NotificationService {
  constructor() {
    this.messaging = messaging;
    this.db = db;
  }

  // Send notification to a specific user
  async sendToUser(userId, notification) {
    try {
      console.log(`🔔 sendToUser called for ${userId} with notification type: ${notification.type}`);
      
      // Get user document
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (!userDoc.exists) {
        console.log(`🔔 User ${userId} not found in Firestore`);
        return { success: false, error: 'User not found' };
      }

      const userData = userDoc.data();
      
      const { deviceTokens = [], notificationPreferences = {} } = userData;
      
      console.log(`🔔 User ${userId} has ${deviceTokens.length} device tokens`);

      if (deviceTokens.length === 0) {
        console.log(`🔔 No device tokens for user ${userId}`);
        return { success: false, error: 'No device tokens' };
      }

      // Check if this notification type is enabled
      if (!this.isNotificationEnabled(notification.type, notificationPreferences)) {
        console.log(`🔔 Notification type ${notification.type} is disabled for user ${userId}`);
        return { success: false, error: 'Notification type disabled' };
      }

      // Check quiet hours
      if (this.isInQuietHours(notificationPreferences)) {
        console.log(`🔔 User ${userId} is in quiet hours, skipping notification`);
        return { success: false, error: 'Quiet hours' };
      }

      // Determine category based on notification type
      let category = null;
      switch (notification.type) {
        case 'new_message':
          category = 'NEW_MESSAGE';
          break;
        case 'connection_request':
          category = 'CONNECTION_REQUEST';
          break;
        case 'new_suggestion':
          category = 'PLACE_SUGGESTION';
          break;
        case 'new_place':
        case 'place_like':
        case 'place_comment':
          category = 'ACTIVITY_UPDATE';
          break;
        case 'daily_summary':
          category = 'DAILY_SUMMARY';
          break;
        case 'discovery_prompt':
          category = 'DISCOVERY_PROMPT';
          break;
        case 'weekend_recommendations':
          category = 'WEEKEND_RECOMMENDATIONS';
          break;
        case 'social_activity':
          category = 'SOCIAL_ACTIVITY';
          break;
        case 'milestone':
          category = 'MILESTONE';
          break;
        case 'check_in':
          category = 'CHECK_IN';
          break;
      }

      // Prepare the message with enhanced iOS configuration
      const message = {
        notification: {
          title: notification.title,
          body: notification.body
          // Note: Do NOT include 'sound' here - it causes FCM errors
        },
        data: notification.data || {},
        apns: {
          payload: {
            aps: {
              alert: {
                title: notification.title,
                body: notification.body,
                ...(notification.subtitle && { subtitle: notification.subtitle })
                // Removed 'sound' from alert object - it goes at aps level
              },
              badge: notification.badge !== undefined ? notification.badge : 1,
              sound: 'default',
              'content-available': 1,
              'mutable-content': 1, // Allows notification service extension to modify content
              'interruption-level': 'active', // iOS 15+ for prominent notifications
              'relevance-score': 1.0, // Ensures notifications persist in Notification Center
              'thread-id': notification.type || 'default', // Groups related notifications
              ...(category && { category }) // Add category if defined
            },
            // IMPORTANT: Add custom data at root level of payload (outside aps)
            // This ensures iOS can access the data when notification is tapped
            ...notification.data,
            // Also add type at root for easier access
            type: notification.type
          },
          headers: {
            'apns-priority': '10', // High priority for immediate delivery
            'apns-push-type': 'alert' // Explicitly set as alert notification
          }
        }
      };

      // Send to all device tokens
      const tokens = deviceTokens.map(dt => dt.token);
      console.log(`🔔 Sending ${notification.type} notification to ${tokens.length} tokens for user ${userId}`);
      
      const response = await this.messaging.sendEachForMulticast({
        ...message,
        tokens: tokens
      });

      console.log(`🔔 Notification send result - Success: ${response.successCount}, Failures: ${response.failureCount}`)
      
      // Handle failed tokens
      if (response.failureCount > 0) {
        const failedTokens = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.log(`🔔 ❌ Token failed: ${tokens[idx].substring(0, 20)}...`);
            console.log(`🔔 ❌ Error: ${resp.error?.message || 'Unknown error'}`);
            console.log(`🔔 ❌ Error code: ${resp.error?.code || 'No code'}`);
            failedTokens.push(tokens[idx]);
          }
        });
        
        // Only remove tokens with specific unrecoverable errors
        const unrecoverableErrors = ['messaging/invalid-registration-token', 'messaging/registration-token-not-registered'];
        const tokensToRemove = [];
        
        response.responses.forEach((resp, idx) => {
          if (!resp.success && resp.error?.code && unrecoverableErrors.includes(resp.error.code)) {
            tokensToRemove.push(tokens[idx]);
          }
        });
        
        if (tokensToRemove.length > 0) {
          console.log(`🔔 Removing ${tokensToRemove.length} invalid tokens`);
          await this.removeInvalidTokens(userId, tokensToRemove);
        }
      }

      return { 
        success: true, 
        successCount: response.successCount, 
        failureCount: response.failureCount,
        userId: userId,
        type: notification.type
      };
    } catch (error) {
      console.error('🔔 Error sending notification:', error);
      throw error;
    }
  }

  // Send notification to multiple users
  async sendToUsers(userIds, notification) {
    const results = [];
    for (const userId of userIds) {
      try {
        const result = await this.sendToUser(userId, notification);
        results.push({ userId, success: true, result });
      } catch (error) {
        results.push({ userId, success: false, error: error.message });
      }
    }
    return results;
  }

  // Check if notification type is enabled
  isNotificationEnabled(type, preferences) {
    const defaultPreferences = {
      newMessages: true,
      newSuggestions: true,
      newPlaces: true,
      connectionRequests: true,
      circleInvites: true,
      checkIns: true,
      dailySummary: true,
      discoveryPrompts: true,
      weekendRecommendations: true,
      socialActivity: true,
      milestones: true
    };

    const typeMap = {
      'new_message': 'newMessages',
      'new_suggestion': 'newSuggestions',
      'new_place': 'newPlaces',
      'connection_request': 'connectionRequests',
      'circle_invite': 'circleInvites',
      'check_in': 'checkIns',
      'daily_summary': 'dailySummary',
      'discovery_prompt': 'discoveryPrompts',
      'weekend_recommendations': 'weekendRecommendations',
      'social_activity': 'socialActivity',
      'milestone': 'milestones'
    };

    const preferencesKey = typeMap[type];
    if (!preferencesKey) return true; // Allow unknown types by default

    return preferences[preferencesKey] !== false;
  }

  // Check if current time is in quiet hours
  isInQuietHours(preferences) {
    if (!preferences.quietHoursEnabled) return false;

    const now = new Date();
    const currentTime = now.getHours() * 60 + now.getMinutes();

    const [startHour, startMin] = (preferences.quietHoursStart || '22:00').split(':').map(Number);
    const [endHour, endMin] = (preferences.quietHoursEnd || '08:00').split(':').map(Number);

    const startTime = startHour * 60 + startMin;
    const endTime = endHour * 60 + endMin;

    if (startTime <= endTime) {
      // Quiet hours don't cross midnight
      return currentTime >= startTime && currentTime < endTime;
    } else {
      // Quiet hours cross midnight
      return currentTime >= startTime || currentTime < endTime;
    }
  }

  // Remove invalid device tokens
  async removeInvalidTokens(userId, invalidTokens) {
    try {
      const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
      const userDoc = await userRef.get();
      
      if (!userDoc.exists) return;

      const userData = userDoc.data();
      const deviceTokens = userData.deviceTokens || [];
      
      const validTokens = deviceTokens.filter(dt => !invalidTokens.includes(dt.token));
      
      await userRef.update({
        deviceTokens: validTokens,
        updatedAt: new Date().toISOString()
      });

      // Invalid tokens removed
    } catch (error) {
      console.error('🔔 Error removing invalid tokens:', error);
    }
  }

  // Notification templates
  async notifyNewMessage(senderId, recipientId, message) {
    const senderDoc = await db.collection(COLLECTIONS.USERS).doc(senderId).get();
    const senderName = senderDoc.exists ? senderDoc.data().displayName : 'Someone';

    // Format the message body based on type
    let notificationBody = message.content || 'Sent a message';
    
    // Handle different message types
    if (message.type === 'suggestion') {
      notificationBody = '📍 Sent a place suggestion';
    } else if (message.type === 'connection_request') {
      notificationBody = '👋 Wants to connect with you';
    } else if (message.mediaUrl) {
      notificationBody = '📷 Sent a photo';
    }
    
    // Truncate long messages for notification
    if (notificationBody.length > 100) {
      notificationBody = notificationBody.substring(0, 97) + '...';
    }

    await this.sendToUser(recipientId, {
      type: 'new_message',
      title: `💬 ${senderName}`,
      body: notificationBody,
      badge: 1, // This will increment the app badge
      data: {
        type: 'new_message',
        senderId: senderId,
        messageId: message.id,
        conversationId: message.conversationId
      }
    });
  }

  async notifyNewSuggestion(suggestionData, targetUserIds) {
    const creatorDoc = await db.collection(COLLECTIONS.USERS).doc(suggestionData.userId).get();
    const creatorName = creatorDoc.exists ? creatorDoc.data().displayName : 'Someone';

    await this.sendToUsers(targetUserIds, {
      type: 'new_suggestion',
      title: 'New Suggestion',
      body: `${creatorName} created a suggestion: "${suggestionData.title}"`,
      data: {
        type: 'new_suggestion',
        suggestionId: suggestionData.id,
        creatorId: suggestionData.userId
      }
    });
  }

  async notifyNewPlace(placeData, circleData, interestedUserIds) {
    const adderDoc = await db.collection(COLLECTIONS.USERS).doc(placeData.addedBy).get();
    const adderName = adderDoc.exists ? adderDoc.data().displayName : 'Someone';

    await this.sendToUsers(interestedUserIds, {
      type: 'new_place',
      title: 'New Place Added',
      body: `${adderName} added "${placeData.name}" to ${circleData.name}`,
      data: {
        type: 'new_place',
        placeId: placeData.id,
        circleId: circleData.id,
        adderId: placeData.addedBy
      }
    });
  }

  async notifyConnectionRequest(fromUserId, toUserId, connectionId = null) {
    const fromUserDoc = await db.collection(COLLECTIONS.USERS).doc(fromUserId).get();
    const fromUserName = fromUserDoc.exists ? fromUserDoc.data().displayName : 'Someone';
    const fromUserPhoto = fromUserDoc.exists ? fromUserDoc.data().profilePicture : null;
    
    const toUserDoc = await db.collection(COLLECTIONS.USERS).doc(toUserId).get();
    const toUserEmail = toUserDoc.exists ? toUserDoc.data().email : null;

    // Save notification to Firestore
    const notificationData = createNotification({
      userId: toUserId,
      type: 'connection_request',
      title: 'New Connection Request',
      body: `${fromUserName} wants to connect with you`,
      data: {
        fromUserId: fromUserId,
        fromUserName: fromUserName,
        fromUserPhoto: fromUserPhoto,
        connectionId: connectionId
      }
    });

    const validationErrors = validateNotification(notificationData);
    if (validationErrors.length === 0) {
      const notificationRef = await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      
      // Send SSE event for real-time notification count update
      sseService.notifyUser(toUserId, 'new_notification', {
        notificationId: notificationRef.id,
        type: 'connection_request',
        title: notificationData.title,
        body: notificationData.body,
        data: notificationData.data
      });
    } else {
      console.error('❌ Validation errors for connection request notification:', validationErrors);
    }

    // Send push notification
    await this.sendToUser(toUserId, {
      type: 'connection_request',
      title: 'New Connection Request',
      body: `${fromUserName} wants to connect with you`,
      data: {
        type: 'connection_request',
        fromUserId: fromUserId
      }
    });
    
    // Also send email notification
    if (toUserEmail) {
      try {
        await emailService.sendConnectionRequestEmail(toUserEmail, fromUserName, fromUserId);
      } catch (emailError) {
        console.error('Failed to send connection request email:', emailError);
        // Don't throw - email failure shouldn't break the notification
      }
    }
  }

  async notifyCircleInvite(inviterUserId, invitedUserId, circleData) {
    const inviterDoc = await db.collection(COLLECTIONS.USERS).doc(inviterUserId).get();
    const inviterName = inviterDoc.exists ? inviterDoc.data().displayName : 'Someone';

    await this.sendToUser(invitedUserId, {
      type: 'circle_invite',
      title: 'Circle Invitation',
      body: `${inviterName} invited you to view "${circleData.name}"`,
      data: {
        type: 'circle_invite',
        circleId: circleData.id,
        inviterId: inviterUserId
      }
    });
  }

  // Update badge count for a user
  async updateBadgeCount(userId) {
    try {
      // Calculate total unread count
      let totalUnread = 0;

      // Count unread messages
      const messageReadsSnapshot = await db.collection(COLLECTIONS.MESSAGE_READS)
        .where('userId', '==', userId)
        .where('isRead', '==', false)
        .get();
      
      totalUnread += messageReadsSnapshot.size;

      // Count pending connection requests
      const connectionSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'pending')
        .get();
      
      totalUnread += connectionSnapshot.size;

      // Send silent notification to update badge
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (!userDoc.exists) return;

      const { deviceTokens = [] } = userDoc.data();
      if (deviceTokens.length === 0) return;

      const message = {
        data: {
          badge: totalUnread.toString()
        },
        apns: {
          payload: {
            aps: {
              badge: totalUnread,
              'content-available': 1
            }
          }
        }
      };

      const tokens = deviceTokens.map(dt => dt.token);
      await this.messaging.sendEachForMulticast({
        ...message,
        tokens: tokens
      });

      // Badge count updated
    } catch (error) {
      console.error('🔔 Error updating badge count:', error);
    }
  }

  async sendPlaceCommentNotification(toUserId, fromUserId, placeId, placeName, commentText) {
    try {
      // Get the commenting user's details
      const userDoc = await this.db.collection(COLLECTIONS.USERS).doc(fromUserId).get();
      if (!userDoc.exists) {
        console.log('🔔 Commenter user not found');
        return;
      }
      const fromUser = userDoc.data();

      const notification = {
        title: `${fromUser.displayName} commented on ${placeName}`,
        body: commentText.substring(0, 100) + (commentText.length > 100 ? '...' : ''),
        data: {
          type: 'place_comment',
          placeId: placeId,
          fromUserId: fromUserId
        }
      };

      await this.sendToUser(toUserId, notification);
    } catch (error) {
      console.error('🔔 Error sending place comment notification:', error);
    }
  }

  async sendPlaceLikeNotification(toUserId, fromUserId, placeId, placeName) {
    try {
      // Get the liking user's details
      const userDoc = await this.db.collection(COLLECTIONS.USERS).doc(fromUserId).get();
      if (!userDoc.exists) {
        console.log('🔔 Liking user not found');
        return;
      }
      const fromUser = userDoc.data();

      // Get the place details to find circleId
      const placeDoc = await this.db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      const place = placeDoc.exists ? placeDoc.data() : {};

      const notificationTitle = `${fromUser.displayName} liked ${placeName}`;
      const notificationBody = `Your place "${placeName}" received a new like!`;

      // Save notification to Firestore
      const notificationData = createNotification({
        userId: toUserId,
        type: 'place_like',
        title: notificationTitle,
        body: notificationBody,
        data: {
          fromUserId: fromUserId,
          fromUserName: fromUser.displayName,
          fromUserPhoto: fromUser.profilePicture || null,
          placeId: placeId,
          placeName: placeName,
          circleId: place.circleId || null
        }
      });

      const validationErrors = validateNotification(notificationData);
      if (validationErrors.length === 0) {
        await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      }

      // Also send push notification
      const pushNotification = {
        title: notificationTitle,
        body: notificationBody,
        data: {
          type: 'place_like',
          placeId: placeId,
          fromUserId: fromUserId
        }
      };

      await this.sendToUser(toUserId, pushNotification);
    } catch (error) {
      console.error('🔔 Error sending place like notification:', error);
    }
  }

  async sendPlaceCommentNotification(toUserId, fromUserId, placeId, placeName, commentText) {
    try {
      // Get the commenting user's details
      const userDoc = await this.db.collection(COLLECTIONS.USERS).doc(fromUserId).get();
      if (!userDoc.exists) {
        console.log('🔔 Commenting user not found');
        return;
      }
      const fromUser = userDoc.data();

      // Get the place details to find circleId
      const placeDoc = await this.db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      const place = placeDoc.exists ? placeDoc.data() : {};

      const notificationTitle = `${fromUser.displayName} commented on ${placeName}`;
      const notificationBody = commentText.length > 50 ? commentText.substring(0, 50) + '...' : commentText;

      // Save notification to Firestore
      const notificationData = createNotification({
        userId: toUserId,
        type: 'place_comment',
        title: notificationTitle,
        body: notificationBody,
        data: {
          fromUserId: fromUserId,
          fromUserName: fromUser.displayName,
          fromUserPhoto: fromUser.profilePicture || null,
          placeId: placeId,
          placeName: placeName,
          circleId: place.circleId || null,
          commentText: commentText
        }
      });

      const validationErrors = validateNotification(notificationData);
      if (validationErrors.length === 0) {
        await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      }

      // Also send push notification
      const pushNotification = {
        title: notificationTitle,
        body: notificationBody,
        data: {
          type: 'place_comment',
          placeId: placeId,
          fromUserId: fromUserId
        }
      };

      await this.sendToUser(toUserId, pushNotification);
    } catch (error) {
      console.error('🔔 Error sending place comment notification:', error);
    }
  }

  // Send notification for new follower
  async sendFollowerNotification(toUserId, fromUserId, fromUserName) {
    try {
      // Get the recipient user to check notification preferences
      const toUserDoc = await this.db.collection(COLLECTIONS.USERS).doc(toUserId).get();
      if (!toUserDoc.exists) {
        console.log('🔔 Recipient user not found for follower notification');
        return { success: false, message: 'Recipient user not found' };
      }

      const toUser = toUserDoc.data();

      // Check if user wants follower notifications
      if (toUser.notificationPreferences && !toUser.notificationPreferences.newFollowers) {
        console.log('🔔 User has disabled follower notifications');
        return { success: false, message: 'User has disabled follower notifications' };
      }

      // Create notification title and body
      const notificationTitle = 'New Follower';
      const notificationBody = `${fromUserName} started following you`;

      // Save notification to Firestore
      const notificationData = createNotification({
        userId: toUserId,
        type: 'new_follower',
        title: notificationTitle,
        body: notificationBody,
        data: {
          fromUserId: fromUserId,
          fromUserName: fromUserName
        }
      });

      const validationErrors = validateNotification(notificationData);
      if (validationErrors.length === 0) {
        await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      }

      // Send push notification
      const pushNotification = {
        title: notificationTitle,
        body: notificationBody,
        data: {
          type: 'new_follower',
          fromUserId: fromUserId
        }
      };

      await this.sendToUser(toUserId, pushNotification);

      return { success: true, message: 'Follower notification sent' };
    } catch (error) {
      console.error('🔔 Error sending follower notification:', error);
      return { success: false, message: 'Failed to send notification', error };
    }
  }
}

module.exports = new NotificationService();