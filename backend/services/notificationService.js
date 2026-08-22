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
        case 'engagement_reminder':
          category = 'ENGAGEMENT_REMINDER';
          break;
        case 'weekly_summary':
          category = 'WEEKLY_SUMMARY';
          break;
        case 'monthly_summary':
          category = 'MONTHLY_SUMMARY';
          break;
        case 'special_event':
          category = 'SPECIAL_EVENT';
          break;
        case 'network_growth':
          category = 'NETWORK_GROWTH';
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
            // The SPECIFIC subtype (data.type) wins in the delivered payload —
            // the generic wrapper type used for preference gating was
            // overwriting it, so taps routed on the wrong string
            type: (notification.data && notification.data.type) || notification.type
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
      'connection_accepted': 'connectionRequests',
      'circle_invite': 'circleInvites',
      'check_in': 'checkIns',
      'daily_summary': 'dailySummary',
      'discovery_prompt': 'discoveryPrompts',
      'weekend_recommendations': 'weekendRecommendations',
      'social_activity': 'socialActivity',
      'social_notification': 'socialActivity',
      'place_like': 'socialActivity',
      'place_comment': 'socialActivity',
      'new_follower': 'newFollowers',
      'engagement_reminder': 'reengagement',
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
    const senderPhoto = senderDoc.exists ? senderDoc.data().profilePicture : null;

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

    const notificationTitle = `💬 ${senderName}`;

    // Save notification to Firestore
    const notificationData = createNotification({
      userId: recipientId,
      type: 'new_message',
      title: notificationTitle,
      body: notificationBody,
      data: {
        senderId: senderId,
        senderName: senderName,
        senderPhoto: senderPhoto,
        messageId: message.id,
        conversationId: message.conversationId,
        messageContent: message.content
      }
    });

    const validationErrors = validateNotification(notificationData);
    if (validationErrors.length === 0) {
      const notificationRef = await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      
      // Send SSE event for real-time notification count update
      sseService.notifyUser(recipientId, 'new_notification', {
        notificationId: notificationRef.id,
        type: 'new_message',
        title: notificationData.title,
        body: notificationData.body,
        data: notificationData.data
      });
    } else {
      console.error('❌ Validation errors for message notification:', validationErrors);
    }

    // Also send push notification
    await this.sendToUser(recipientId, {
      type: 'new_message',
      title: notificationTitle,
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

  // Directed suggestion (recommend a place to one person). Persists an in-app
  // notification — recipients with push off must still see "X suggested … for
  // you" — then fires SSE and a best-effort push. Mirrors notifyConnectionRequest.
  async notifyDirectedSuggestion(suggestionData, recipientId) {
    const authorDoc = await db.collection(COLLECTIONS.USERS).doc(suggestionData.userId).get();
    const authorName = authorDoc.exists ? authorDoc.data().displayName : 'Someone';
    const authorPhoto = authorDoc.exists ? authorDoc.data().profilePicture : null;

    const placeName = (suggestionData.placeDetails && suggestionData.placeDetails.name) || 'a place';
    const body = `${authorName} suggested ${placeName} for you`;
    const notifData = {
      fromUserId: suggestionData.userId,
      fromUserName: authorName,
      fromUserPhoto: authorPhoto,
      suggestionId: suggestionData.id || suggestionData._id || null,
      placeId: suggestionData.placeId || null
    };

    // In-app notification doc (visible regardless of push settings)
    const notificationData = createNotification({
      userId: recipientId,
      type: 'new_suggestion',
      title: 'New Suggestion',
      body,
      data: notifData
    });
    const validationErrors = validateNotification(notificationData);
    if (validationErrors.length === 0) {
      const notificationRef = await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      sseService.notifyUser(recipientId, 'new_notification', {
        notificationId: notificationRef.id,
        type: 'new_suggestion',
        title: notificationData.title,
        body,
        data: notifData
      });
    } else {
      console.error('❌ Validation errors for directed suggestion notification:', validationErrors);
    }

    // Best-effort push
    await this.sendToUser(recipientId, {
      type: 'new_suggestion',
      title: 'New Suggestion',
      body,
      data: { type: 'new_suggestion', ...notifData }
    });
  }

  // A store-ownership claim needs admin review. Notifies the admin account
  // (ADMIN_NOTIFY_EMAIL) in-app + SSE + push so the claim isn't buried in
  // email. Mirrors notifyDirectedSuggestion.
  async notifyStoreClaimSubmitted(claim, claimId) {
    const adminEmail = process.env.ADMIN_NOTIFY_EMAIL || 'sgroiwes@gmail.com';
    const adminSnap = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', adminEmail).limit(1).get();
    if (adminSnap.empty) {
      console.error(`❌ store_claim notification: no user found for admin email ${adminEmail}`);
      return;
    }
    const adminUserId = adminSnap.docs[0].id;

    const businessName = claim.venueName || claim.placeName || 'a business';
    const claimerName = claim.userDisplayName || claim.contactName || 'Someone';
    const body = `${claimerName} claimed ${businessName} — tap to review`;
    const notifData = {
      claimId,
      fromUserId: claim.userId || null,
      fromUserName: claimerName,
      placeId: claim.placeId || claim.globalPlaceId || null,
      placeName: businessName
    };

    // In-app notification doc (visible regardless of push settings)
    const notificationData = createNotification({
      userId: adminUserId,
      type: 'store_claim',
      title: 'Store Claim to Review',
      body,
      data: notifData
    });
    const validationErrors = validateNotification(notificationData);
    if (validationErrors.length === 0) {
      const notificationRef = await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      sseService.notifyUser(adminUserId, 'new_notification', {
        notificationId: notificationRef.id,
        type: 'store_claim',
        title: notificationData.title,
        body,
        data: notifData
      });
    } else {
      console.error('❌ Validation errors for store claim notification:', validationErrors);
    }

    // Best-effort push (FCM data values must be strings; skip nulls)
    const pushData = { type: 'store_claim', claimId };
    for (const [k, v] of Object.entries(notifData)) {
      if (typeof v === 'string' && v) pushData[k] = v;
    }
    await this.sendToUser(adminUserId, {
      type: 'store_claim',
      title: 'Store Claim to Review',
      body,
      data: pushData
    });
  }

  // A new paying subscriber — consumer premium or FavCircles Business — is
  // revenue the owner wants to hear about the moment it happens. Notifies the
  // admin account (ADMIN_NOTIFY_EMAIL) in-app + SSE + push, mirroring
  // notifyStoreClaimSubmitted. Callers fire only on the signup TRANSITION
  // (not on routine re-verifies), so every alert is a genuinely new sub.
  async notifyAdminPremiumSignup({ scope, userId, userName, userEmail, productId, status, venueId }) {
    const adminEmail = process.env.ADMIN_NOTIFY_EMAIL || 'sgroiwes@gmail.com';
    const adminSnap = await db.collection(COLLECTIONS.USERS)
      .where('email', '==', adminEmail).limit(1).get();
    if (adminSnap.empty) {
      console.error(`❌ premium_signup notification: no user found for admin email ${adminEmail}`);
      return;
    }
    const adminUserId = adminSnap.docs[0].id;

    // Best-effort venue name for Business subs — the alert reads better as
    // "Business sub for Demo Cafe" than a bare venue id.
    let venueName = null;
    if (venueId) {
      try {
        const venueDoc = await db.collection('stickerVenues').doc(venueId).get();
        if (venueDoc.exists) venueName = venueDoc.data().venueName || null;
      } catch (e) { /* name is decoration; the alert still goes out */ }
    }

    const who = userName || userEmail || userId || 'Someone';
    const isTrial = status === 'trial';
    const title = scope === 'business'
      ? `🏪 New Business subscriber${isTrial ? ' (trial)' : ''}`
      : `⭐ New premium subscriber${isTrial ? ' (trial)' : ''}`;
    const body = scope === 'business'
      ? `${who} subscribed to FavCircles Business${venueName ? ` for ${venueName}` : ''}`
      : `${who} signed up for premium`;

    const notifData = {
      scope,
      subscriberUserId: userId || null,
      subscriberName: who,
      productId: productId || null,
      status: status || null,
      venueId: venueId || null,
      venueName
    };

    // In-app notification doc (visible regardless of push settings)
    const notificationData = createNotification({
      userId: adminUserId,
      type: 'premium_signup',
      title,
      body,
      data: notifData
    });
    const validationErrors = validateNotification(notificationData);
    if (validationErrors.length === 0) {
      const notificationRef = await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      sseService.notifyUser(adminUserId, 'new_notification', {
        notificationId: notificationRef.id,
        type: 'premium_signup',
        title,
        body,
        data: notifData
      });
    } else {
      console.error('❌ Validation errors for premium signup notification:', validationErrors);
    }

    // Best-effort push (FCM data values must be strings; skip nulls)
    const pushData = { type: 'premium_signup' };
    for (const [k, v] of Object.entries(notifData)) {
      if (typeof v === 'string' && v) pushData[k] = v;
    }
    await this.sendToUser(adminUserId, {
      type: 'premium_signup',
      title,
      body,
      data: pushData
    });
  }

  // The claimant becomes a store owner the moment an admin approves — tell
  // them, or they only find out by stumbling into owner mode on their place.
  async notifyStoreClaimApproved(claim, claimId, venueId) {
    if (!claim.userId) {
      console.error(`❌ store_claim_approved: claim ${claimId} has no userId`);
      return;
    }

    const businessName = claim.venueName || claim.placeName || 'your store';
    const body = `You now manage ${businessName} on FavCircles — tap to set up your store`;
    const notifData = {
      claimId,
      venueId: venueId || null,
      placeId: claim.placeId || claim.globalPlaceId || null,
      placeName: businessName
    };

    // In-app notification doc (visible regardless of push settings)
    const notificationData = createNotification({
      userId: claim.userId,
      type: 'store_claim_approved',
      title: 'Store claim approved! 🎉',
      body,
      data: notifData
    });
    const validationErrors = validateNotification(notificationData);
    if (validationErrors.length === 0) {
      const notificationRef = await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      sseService.notifyUser(claim.userId, 'new_notification', {
        notificationId: notificationRef.id,
        type: 'store_claim_approved',
        title: notificationData.title,
        body,
        data: notifData
      });
    } else {
      console.error('❌ Validation errors for claim-approved notification:', validationErrors);
    }

    // Best-effort push (FCM data values must be strings; skip nulls)
    const pushData = { type: 'store_claim_approved', claimId };
    for (const [k, v] of Object.entries(notifData)) {
      if (typeof v === 'string' && v) pushData[k] = v;
    }
    await this.sendToUser(claim.userId, {
      type: 'store_claim_approved',
      title: 'Store claim approved! 🎉',
      body,
      data: pushData
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
        fromUserId: fromUserId,
        // iOS's Accept/Decline notification actions read requestId
        requestId: connectionId || null,
        connectionId: connectionId || null
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

  // Connection ACCEPTED: persist an in-app notification + SSE + push for the
  // original requester. (This used to be a bare push from the controller, so
  // the Notifications screen never showed "X accepted your request" — and when
  // the push failed, the event vanished entirely.)
  async notifyConnectionAccepted(acceptingUserId, requesterUserId, connectionId = null) {
    const acceptingDoc = await db.collection(COLLECTIONS.USERS).doc(acceptingUserId).get();
    const acceptingName = acceptingDoc.exists ? acceptingDoc.data().displayName : 'Someone';
    const acceptingPhoto = acceptingDoc.exists ? acceptingDoc.data().profilePicture : null;

    const notificationData = createNotification({
      userId: requesterUserId,
      type: 'connection_accepted',
      title: 'Connection Accepted',
      body: `${acceptingName} accepted your connection request`,
      data: {
        fromUserId: acceptingUserId,
        fromUserName: acceptingName,
        fromUserPhoto: acceptingPhoto,
        connectionId: connectionId
      }
    });

    const validationErrors = validateNotification(notificationData);
    if (validationErrors.length === 0) {
      const notificationRef = await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      sseService.notifyUser(requesterUserId, 'new_notification', {
        notificationId: notificationRef.id,
        type: 'connection_accepted',
        title: notificationData.title,
        body: notificationData.body,
        data: notificationData.data
      });
    } else {
      console.error('❌ Validation errors for connection accepted notification:', validationErrors);
    }

    await this.sendToUser(requesterUserId, {
      type: 'connection_accepted',
      title: 'Connection Accepted',
      body: `${acceptingName} accepted your connection request`,
      data: {
        type: 'connection_accepted',
        acceptedByUserId: acceptingUserId
      }
    });
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
        type: 'place_comment',
        title: `${fromUser.displayName} commented on ${placeName}`,
        body: commentText.substring(0, 100) + (commentText.length > 100 ? '...' : ''),
        data: {
          // iOS's tap router handles 'place_commented' (opens the place WITH
          // comments); 'place_comment' fell to the default and lost them
          type: 'place_commented',
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
        type: 'place_like',
        title: notificationTitle,
        body: notificationBody,
        data: {
          type: 'place_liked', // the string iOS's tap router handles
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
        type: 'place_comment',
        title: notificationTitle,
        body: notificationBody,
        data: {
          // iOS's tap router handles 'place_commented' (opens the place WITH
          // comments); 'place_comment' fell to the default and lost them
          type: 'place_commented',
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

      // Check if user wants follower notifications. Block ONLY on an explicit
      // opt-out — a missing newFollowers key must default to ON, matching the
      // `!== false` convention isNotificationEnabled uses for every other type.
      // (Legacy accounts have a sparse notificationPreferences like
      // {dailySummary:true}; the old `&& !newFollowers` test silently blocked
      // every one of them.)
      if (toUser.notificationPreferences && toUser.notificationPreferences.newFollowers === false) {
        console.log('🔔 User has disabled follower notifications');
        return { success: false, message: 'User has disabled follower notifications' };
      }

      // Create notification title and body
      const notificationTitle = 'New Follower';
      const notificationBody = `${fromUserName} started following you`;

      // The follower's avatar rides along so the notification row shows the
      // right face — without it, iOS cells had nothing to load and reused
      // cells kept the previous row's photo. Best-effort.
      let fromUserPhoto = null;
      try {
        const fromUserDoc = await this.db.collection(COLLECTIONS.USERS).doc(fromUserId).get();
        if (fromUserDoc.exists) fromUserPhoto = fromUserDoc.data().profilePicture || null;
      } catch (e) { /* photo is cosmetic */ }

      // Save notification to Firestore
      const notificationData = createNotification({
        userId: toUserId,
        type: 'new_follower',
        title: notificationTitle,
        body: notificationBody,
        data: {
          fromUserId: fromUserId,
          fromUserName: fromUserName,
          ...(fromUserPhoto ? { fromUserPhoto } : {})
        }
      });

      const validationErrors = validateNotification(notificationData);
      if (validationErrors.length === 0) {
        await this.db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
      }

      // Send push notification
      const pushNotification = {
        type: 'new_follower',
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