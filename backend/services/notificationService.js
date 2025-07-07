// backend/services/notificationService.js
const { getFirestore, getMessaging } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const emailService = require('./emailService');

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
      // Get user document
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (!userDoc.exists) {
        console.log(`🔔 User ${userId} not found`);
        return;
      }

      const userData = userDoc.data();
      const { deviceTokens = [], notificationPreferences = {} } = userData;

      if (deviceTokens.length === 0) {
        console.log(`🔔 No device tokens for user ${userId}`);
        return;
      }

      // Check if this notification type is enabled
      if (!this.isNotificationEnabled(notification.type, notificationPreferences)) {
        console.log(`🔔 Notification type ${notification.type} disabled for user ${userId}`);
        return;
      }

      // Check quiet hours
      if (this.isInQuietHours(notificationPreferences)) {
        console.log(`🔔 User ${userId} is in quiet hours`);
        return;
      }

      // Prepare the message with enhanced iOS configuration
      const message = {
        notification: {
          title: notification.title,
          body: notification.body,
          badge: notification.badge?.toString() || '1'
        },
        data: notification.data || {},
        apns: {
          payload: {
            aps: {
              alert: {
                title: notification.title,
                body: notification.body,
                sound: 'default'
              },
              badge: notification.badge || 1,
              sound: 'default',
              'content-available': 1,
              'mutable-content': 1, // Allows notification service extension to modify content
              'interruption-level': 'active' // iOS 15+ for prominent notifications
            }
          },
          headers: {
            'apns-priority': '10', // High priority for immediate delivery
            'apns-push-type': 'alert' // Explicitly set as alert notification
          }
        }
      };

      // Send to all device tokens
      const tokens = deviceTokens.map(dt => dt.token);
      const response = await this.messaging.sendMulticast({
        ...message,
        tokens: tokens
      });

      console.log(`🔔 Sent notification to ${response.successCount}/${tokens.length} devices for user ${userId}`);
      
      // Handle failed tokens
      if (response.failureCount > 0) {
        const failedTokens = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            failedTokens.push(tokens[idx]);
            console.log(`🔔 Failed to send to token: ${resp.error?.message}`);
          }
        });
        
        // Remove invalid tokens
        await this.removeInvalidTokens(userId, failedTokens);
      }

      return response;
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
      circleInvites: true
    };

    const typeMap = {
      'new_message': 'newMessages',
      'new_suggestion': 'newSuggestions',
      'new_place': 'newPlaces',
      'connection_request': 'connectionRequests',
      'circle_invite': 'circleInvites'
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

      console.log(`🔔 Removed ${invalidTokens.length} invalid tokens for user ${userId}`);
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

  async notifyConnectionRequest(fromUserId, toUserId) {
    const fromUserDoc = await db.collection(COLLECTIONS.USERS).doc(fromUserId).get();
    const fromUserName = fromUserDoc.exists ? fromUserDoc.data().displayName : 'Someone';
    
    const toUserDoc = await db.collection(COLLECTIONS.USERS).doc(toUserId).get();
    const toUserEmail = toUserDoc.exists ? toUserDoc.data().email : null;

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
      await this.messaging.sendMulticast({
        ...message,
        tokens: tokens
      });

      console.log(`🔔 Updated badge count to ${totalUnread} for user ${userId}`);
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

      const notification = {
        title: `${fromUser.displayName} liked ${placeName}`,
        body: `Your place "${placeName}" received a new like!`,
        data: {
          type: 'place_like',
          placeId: placeId,
          fromUserId: fromUserId
        }
      };

      await this.sendToUser(toUserId, notification);
    } catch (error) {
      console.error('🔔 Error sending place like notification:', error);
    }
  }
}

module.exports = new NotificationService();