const { getFirestore, FieldValue } = require('../config/firebase');
const notificationService = require('./notificationService');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

class EngagementNotificationService {
  constructor() {
    this.db = db;
  }

  // ==================== FRIEND ACTIVITY ALERTS ====================
  
  /**
   * Send notification when a connection adds multiple places
   * Called in real-time when places are added
   */
  async sendFriendActivityAlert(actorUserId, placeCount, placeCategory = null) {
    try {
      console.log(`👥 Sending friend activity alert for ${actorUserId} adding ${placeCount} places`);
      
      // Get the actor's details
      const actorDoc = await db.collection(COLLECTIONS.USERS).doc(actorUserId).get();
      if (!actorDoc.exists) return;
      
      const actor = actorDoc.data();
      const actorName = actor.displayName || 'Someone in your network';
      
      // Get all connections of this user
      const [connectionsAsUser, connectionsAsConnected] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', actorUserId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('connectedUserId', '==', actorUserId)
          .where('status', '==', 'accepted')
          .get()
      ]);
      
      const connectionUserIds = new Set();
      connectionsAsUser.forEach(doc => {
        const conn = doc.data();
        if (conn.connectedUserId) connectionUserIds.add(conn.connectedUserId);
      });
      connectionsAsConnected.forEach(doc => {
        const conn = doc.data();
        if (conn.userId) connectionUserIds.add(conn.userId);
      });
      
      // Prepare notification
      let body = `${actorName} just added ${placeCount} new`;
      if (placeCategory) {
        body += ` ${placeCategory}${placeCount > 1 ? 's' : ''}!`;
      } else {
        body += ` place${placeCount > 1 ? 's' : ''}!`;
      }
      
      const notification = {
        type: 'social_activity',
        title: '🆕 New places from your network',
        body,
        data: {
          type: 'social_activity',
          actorUserId,
          actorName,
          placeCount: placeCount.toString(),
          category: placeCategory || ''
        }
      };
      
      // Send to all connections
      const sendPromises = Array.from(connectionUserIds).map(userId => 
        notificationService.sendToUser(userId, notification)
      );
      
      await Promise.allSettled(sendPromises);
      console.log(`✅ Sent friend activity alerts to ${connectionUserIds.size} users`);
      
    } catch (error) {
      console.error('Error sending friend activity alert:', error);
    }
  }

  // ==================== MILESTONE NOTIFICATIONS ====================
  
  /**
   * Check and send milestone notifications for a user
   * Called after user adds places, connections, etc.
   */
  async checkAndSendMilestone(userId, type = 'places') {
    try {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (!userDoc.exists) return;
      
      const user = userDoc.data();
      let notification = null;
      
      switch (type) {
        case 'places':
          const placesCount = await this.getUserPlacesCount(userId);
          notification = this.getPlacesMilestoneNotification(placesCount);
          break;
          
        case 'connections':
          const connectionsCount = await this.getUserConnectionsCount(userId);
          notification = this.getConnectionsMilestoneNotification(connectionsCount);
          break;
          
        case 'moments':
          const momentsCount = await this.getUserMomentsCount(userId);
          notification = this.getMomentsMilestoneNotification(momentsCount);
          break;
      }
      
      if (notification) {
        // Check if we've already sent this milestone
        const milestoneKey = `${type}_${notification.milestone}`;
        const sentMilestones = user.sentMilestones || [];
        
        if (!sentMilestones.includes(milestoneKey)) {
          // Send the notification
          await notificationService.sendToUser(userId, notification);
          
          // Record that we sent this milestone
          await db.collection(COLLECTIONS.USERS).doc(userId).update({
            sentMilestones: FieldValue.arrayUnion(milestoneKey)
          });
          
          console.log(`🎉 Sent ${type} milestone notification to ${userId}: ${notification.milestone}`);
        }
      }
    } catch (error) {
      console.error(`Error checking milestones for ${userId}:`, error);
    }
  }
  
  getPlacesMilestoneNotification(count) {
    const milestones = [
      { value: 1, title: '🎉 Your first place!', body: 'Welcome to Circles! You\'ve added your first favorite spot.' },
      { value: 10, title: '🌟 10 places added!', body: 'Your circle is growing! Keep discovering.' },
      { value: 25, title: '🏆 25 places milestone!', body: 'You\'re building an amazing collection!' },
      { value: 50, title: '🎯 50 places!', body: 'Half a century of favorites! You\'re a pro curator.' },
      { value: 100, title: '💯 100 places!', body: 'Incredible! You\'ve added 100 amazing places to your circles.' },
      { value: 250, title: '🚀 250 places!', body: 'You\'re a Circles superstar! 250 places and counting.' },
      { value: 500, title: '👑 500 places!', body: 'Legendary status achieved! 500 favorite spots catalogued.' }
    ];
    
    const milestone = milestones.find(m => m.value === count);
    if (!milestone) return null;
    
    return {
      type: 'milestone',
      title: milestone.title,
      body: milestone.body,
      milestone: milestone.value,
      data: {
        type: 'milestone',
        milestoneType: 'places',
        milestoneValue: milestone.value.toString()
      }
    };
  }
  
  getConnectionsMilestoneNotification(count) {
    const milestones = [
      { value: 1, title: '👥 Your first connection!', body: 'Welcome to the Circles network!' },
      { value: 5, title: '🌱 5 connections!', body: 'Your network is growing!' },
      { value: 10, title: '🌟 10 connections!', body: 'Double digits! Your circle is expanding.' },
      { value: 25, title: '🎊 25 connections!', body: 'You\'re well connected! 25 people in your network.' },
      { value: 50, title: '🎯 50 connections!', body: 'Impressive network! 50 connections strong.' },
      { value: 100, title: '💫 100 connections!', body: 'You\'re a networking pro! 100 connections reached.' }
    ];
    
    const milestone = milestones.find(m => m.value === count);
    if (!milestone) return null;
    
    return {
      type: 'milestone',
      title: milestone.title,
      body: milestone.body,
      milestone: milestone.value,
      data: {
        type: 'milestone',
        milestoneType: 'connections',
        milestoneValue: milestone.value.toString()
      }
    };
  }
  
  getMomentsMilestoneNotification(count) {
    const milestones = [
      { value: 1, title: '📸 Your first moment!', body: 'Great start! Share more experiences with your network.' },
      { value: 10, title: '🎬 10 moments shared!', body: 'You\'re capturing great memories!' },
      { value: 25, title: '📹 25 moments!', body: 'You\'re a storytelling pro! 25 moments shared.' },
      { value: 50, title: '🌟 50 moments!', body: 'Amazing! 50 moments of experiences shared.' }
    ];
    
    const milestone = milestones.find(m => m.value === count);
    if (!milestone) return null;
    
    return {
      type: 'milestone',
      title: milestone.title,
      body: milestone.body,
      milestone: milestone.value,
      data: {
        type: 'milestone',
        milestoneType: 'moments',
        milestoneValue: milestone.value.toString()
      }
    };
  }

  // ==================== ENGAGEMENT REMINDERS ====================
  
  /**
   * Send engagement reminders to inactive users
   * Scheduled to run at 3 PM daily
   */
  async sendEngagementReminders() {
    console.log('📱 Starting engagement reminder process...');
    
    try {
      // Get all users
      const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
      const users = [];
      usersSnapshot.forEach(doc => users.push({ id: doc.id, ...doc.data() }));
      
      // Check each user's activity
      for (const user of users) {
        try {
          // Skip if user has notifications disabled
          if (user.notificationPreferences?.engagementReminders === false) continue;
          
          // Check if user was active today
          const wasActiveToday = await this.checkUserActivityToday(user.id);
          
          // Check if user already received daily summary
          const receivedDailySummary = await this.receivedDailySummaryToday(user.id);
          
          // Only send reminder if:
          // 1. User wasn't active today
          // 2. User didn't receive daily summary (no activity to report)
          if (!wasActiveToday && !receivedDailySummary) {
            const reminderType = await this.selectEngagementReminder(user.id);
            await this.sendEngagementReminder(user.id, reminderType);
          }
          
        } catch (error) {
          console.error(`Error processing engagement reminder for user ${user.id}:`, error);
        }
      }
      
      console.log('✅ Engagement reminders process completed');
    } catch (error) {
      console.error('Error in sendEngagementReminders:', error);
    }
  }
  
  /**
   * Select which type of engagement reminder to send
   * Rotates between different types based on user history
   */
  async selectEngagementReminder(userId) {
    try {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      const user = userDoc.data();
      
      // Get last reminder type sent
      const lastReminderType = user.lastEngagementReminderType || null;
      const reminderTypes = ['moments', 'checkin', 'places'];
      
      // Rotate to next type
      let nextType;
      if (!lastReminderType) {
        nextType = reminderTypes[0];
      } else {
        const currentIndex = reminderTypes.indexOf(lastReminderType);
        nextType = reminderTypes[(currentIndex + 1) % reminderTypes.length];
      }
      
      // Update user's last reminder type
      await db.collection(COLLECTIONS.USERS).doc(userId).update({
        lastEngagementReminderType: nextType,
        lastEngagementReminderDate: new Date().toISOString()
      });
      
      return nextType;
    } catch (error) {
      console.error('Error selecting engagement reminder:', error);
      return 'places'; // Default
    }
  }
  
  /**
   * Send specific engagement reminder to user
   */
  async sendEngagementReminder(userId, type) {
    let notification;
    
    switch (type) {
      case 'moments':
        notification = {
          type: 'engagement_reminder',
          title: '📸 Try adding a moment!',
          body: 'Share what you\'re up to! Tap to add your first moment.',
          data: {
            type: 'engagement_reminder',
            reminderType: 'moments',
            deepLink: 'circles://moments/create'
          }
        };
        break;
        
      case 'checkin':
        notification = {
          type: 'engagement_reminder',
          title: '📍 Try the check-in feature!',
          body: 'Let friends know where you are. Check in at your favorite spot!',
          data: {
            type: 'engagement_reminder',
            reminderType: 'checkin',
            deepLink: 'circles://checkin'
          }
        };
        break;
        
      case 'places':
        notification = {
          type: 'engagement_reminder',
          title: '🏠 Been a homebody?',
          body: 'You haven\'t added any new places this week. Discovered anything new? 😉',
          data: {
            type: 'engagement_reminder',
            reminderType: 'places',
            deepLink: 'circles://add-place'
          }
        };
        break;
        
      default:
        notification = {
          type: 'engagement_reminder',
          title: '👋 We miss you!',
          body: 'Check out what your network has been up to',
          data: {
            type: 'engagement_reminder',
            reminderType: 'general',
            deepLink: 'circles://home'
          }
        };
    }
    
    await notificationService.sendToUser(userId, notification);
    console.log(`📱 Sent ${type} engagement reminder to user ${userId}`);
  }

  // ==================== WEEKLY SUMMARY ====================
  
  /**
   * Send weekly summary every Monday at 9 AM
   */
  async sendWeeklySummaries() {
    console.log('📊 Starting weekly summary generation...');
    
    try {
      const usersSnapshot = await db.collection(COLLECTIONS.USERS)
        .where('notificationPreferences.weeklySummary', '!=', false)
        .get();
      
      const users = [];
      usersSnapshot.forEach(doc => users.push({ id: doc.id, ...doc.data() }));
      
      for (const user of users) {
        try {
          const stats = await this.gatherWeeklyStats(user.id);
          
          if (this.hasWeeklyActivity(stats)) {
            const notification = this.buildWeeklySummaryNotification(stats, user);
            await notificationService.sendToUser(user.id, notification);
          }
        } catch (error) {
          console.error(`Error sending weekly summary to ${user.id}:`, error);
        }
      }
      
      console.log('✅ Weekly summaries completed');
    } catch (error) {
      console.error('Error in sendWeeklySummaries:', error);
    }
  }
  
  buildWeeklySummaryNotification(stats, user) {
    const parts = [];
    
    if (stats.newPlaces > 0) {
      parts.push(`${stats.newPlaces} new places`);
    }
    if (stats.newConnections > 0) {
      parts.push(`${stats.newConnections} new connections`);
    }
    if (stats.newMoments > 0) {
      parts.push(`${stats.newMoments} moments shared`);
    }
    
    const body = parts.length > 0 
      ? parts.join(', ') + ' from your network'
      : 'Check out trending places from your network';
    
    return {
      type: 'weekly_summary',
      title: '📊 Your weekly recap',
      body,
      data: {
        type: 'weekly_summary',
        weekStartDate: stats.weekStartDate,
        stats: JSON.stringify(stats)
      }
    };
  }

  // ==================== MONTHLY SUMMARY ====================
  
  /**
   * Send monthly summary on the 1st of each month
   */
  async sendMonthlySummaries() {
    console.log('📅 Starting monthly summary generation...');
    
    try {
      const usersSnapshot = await db.collection(COLLECTIONS.USERS)
        .where('notificationPreferences.monthlySummary', '!=', false)
        .get();
      
      const users = [];
      usersSnapshot.forEach(doc => users.push({ id: doc.id, ...doc.data() }));
      
      const lastMonth = new Date();
      lastMonth.setMonth(lastMonth.getMonth() - 1);
      const monthName = lastMonth.toLocaleString('default', { month: 'long' });
      
      for (const user of users) {
        try {
          const stats = await this.gatherMonthlyStats(user.id);
          
          if (this.hasMonthlyActivity(stats)) {
            const notification = {
              type: 'monthly_summary',
              title: `🎯 Your ${monthName} highlights`,
              body: `${stats.totalPlaces} places discovered, ${stats.totalConnections} connections made!`,
              data: {
                type: 'monthly_summary',
                month: monthName,
                stats: JSON.stringify(stats)
              }
            };
            
            await notificationService.sendToUser(user.id, notification);
          }
        } catch (error) {
          console.error(`Error sending monthly summary to ${user.id}:`, error);
        }
      }
      
      console.log('✅ Monthly summaries completed');
    } catch (error) {
      console.error('Error in sendMonthlySummaries:', error);
    }
  }

  // ==================== SPECIAL EVENTS ====================
  
  /**
   * Send special event notifications based on holidays/seasons
   */
  async sendSpecialEventNotification(eventType) {
    console.log(`🎉 Sending ${eventType} special event notifications...`);
    
    const events = {
      'christmas': {
        title: '🎄 Share your holiday favorites!',
        body: 'What are your go-to spots for the holiday season?',
        emoji: '🎄'
      },
      'valentines': {
        title: '❤️ Valentine\'s Day ideas',
        body: 'Romantic restaurants from your network',
        emoji: '❤️'
      },
      'summer': {
        title: '☀️ Summer is here!',
        body: 'Beach spots and outdoor dining from your circle',
        emoji: '☀️'
      },
      'thanksgiving': {
        title: '🦃 Thanksgiving gathering spots',
        body: 'Where is your network celebrating?',
        emoji: '🦃'
      },
      'newyear': {
        title: '🎊 New Year, new places!',
        body: 'Start the year with new discoveries',
        emoji: '🎊'
      }
    };
    
    const event = events[eventType];
    if (!event) return;
    
    try {
      const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
      
      const notification = {
        type: 'special_event',
        title: event.title,
        body: event.body,
        data: {
          type: 'special_event',
          eventType,
          emoji: event.emoji
        }
      };
      
      const users = [];
      usersSnapshot.forEach(doc => users.push(doc.id));
      
      // Send in batches
      for (let i = 0; i < users.length; i += 50) {
        const batch = users.slice(i, i + 50);
        await Promise.allSettled(
          batch.map(userId => notificationService.sendToUser(userId, notification))
        );
      }
      
      console.log(`✅ Sent ${eventType} notifications to ${users.length} users`);
    } catch (error) {
      console.error(`Error sending special event notifications:`, error);
    }
  }

  // ==================== NETWORK GROWTH ====================
  
  /**
   * Send network growth notifications
   */
  async sendNetworkGrowthAlert(userId, newConnectionsCount) {
    try {
      const notification = {
        type: 'network_growth',
        title: '🎊 Your network is growing!',
        body: `${newConnectionsCount} ${newConnectionsCount === 1 ? 'person joined' : 'people joined'} your network this week!`,
        data: {
          type: 'network_growth',
          newConnections: newConnectionsCount.toString()
        }
      };
      
      await notificationService.sendToUser(userId, notification);
      console.log(`📈 Sent network growth alert to ${userId}`);
    } catch (error) {
      console.error('Error sending network growth alert:', error);
    }
  }

  // ==================== HELPER METHODS ====================
  
  async getUserPlacesCount(userId) {
    const snapshot = await db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', userId)
      .get();
    return snapshot.size;
  }
  
  async getUserConnectionsCount(userId) {
    const [asUser, asConnected] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    return asUser.size + asConnected.size;
  }
  
  async getUserMomentsCount(userId) {
    const snapshot = await db.collection('placeVideos')
      .where('userId', '==', userId)
      .get();
    return snapshot.size;
  }
  
  async checkUserActivityToday(userId) {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStr = today.toISOString();
    
    // Check various activity types
    const [places, moments, checkins] = await Promise.all([
      db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', userId)
        .where('createdAt', '>=', todayStr)
        .limit(1)
        .get(),
      db.collection('placeVideos')
        .where('userId', '==', userId)
        .where('createdAt', '>=', todayStr)
        .limit(1)
        .get(),
      db.collection('checkIns')
        .where('userId', '==', userId)
        .where('createdAt', '>=', todayStr)
        .limit(1)
        .get()
    ]);
    
    return !places.empty || !moments.empty || !checkins.empty;
  }
  
  async receivedDailySummaryToday(userId) {
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) return false;
    
    const user = userDoc.data();
    if (!user.lastDailySummary) return false;
    
    const lastSummary = new Date(user.lastDailySummary);
    const today = new Date();
    
    return lastSummary.toDateString() === today.toDateString();
  }
  
  async gatherWeeklyStats(userId) {
    const weekAgo = new Date();
    weekAgo.setDate(weekAgo.getDate() - 7);
    const weekAgoStr = weekAgo.toISOString();
    
    // Get user's network activity
    const [connections, places, moments] = await Promise.all([
      this.getNetworkConnectionsLastWeek(userId, weekAgoStr),
      this.getNetworkPlacesLastWeek(userId, weekAgoStr),
      this.getNetworkMomentsLastWeek(userId, weekAgoStr)
    ]);
    
    return {
      weekStartDate: weekAgoStr,
      newPlaces: places,
      newConnections: connections,
      newMoments: moments
    };
  }
  
  async gatherMonthlyStats(userId) {
    const monthAgo = new Date();
    monthAgo.setMonth(monthAgo.getMonth() - 1);
    const monthAgoStr = monthAgo.toISOString();
    
    const [places, connections] = await Promise.all([
      db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', userId)
        .where('createdAt', '>=', monthAgoStr)
        .get(),
      this.getNewConnectionsCount(userId, monthAgoStr)
    ]);
    
    return {
      totalPlaces: places.size,
      totalConnections: connections
    };
  }
  
  async getNetworkPlacesLastWeek(userId, since) {
    // Get user's connections
    const connectionIds = await this.getUserConnectionIds(userId);
    if (connectionIds.length === 0) return 0;
    
    // Query places from connections
    let total = 0;
    for (let i = 0; i < connectionIds.length; i += 10) {
      const batch = connectionIds.slice(i, i + 10);
      const snapshot = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', 'in', batch)
        .where('createdAt', '>=', since)
        .get();
      total += snapshot.size;
    }
    
    return total;
  }
  
  async getNetworkConnectionsLastWeek(userId, since) {
    const [asUser, asConnected] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .where('acceptedAt', '>=', since)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .where('acceptedAt', '>=', since)
        .get()
    ]);
    
    return asUser.size + asConnected.size;
  }
  
  async getNetworkMomentsLastWeek(userId, since) {
    const connectionIds = await this.getUserConnectionIds(userId);
    if (connectionIds.length === 0) return 0;
    
    let total = 0;
    for (let i = 0; i < connectionIds.length; i += 10) {
      const batch = connectionIds.slice(i, i + 10);
      const snapshot = await db.collection('placeVideos')
        .where('userId', 'in', batch)
        .where('createdAt', '>=', since)
        .get();
      total += snapshot.size;
    }
    
    return total;
  }
  
  async getUserConnectionIds(userId) {
    const [asUser, asConnected] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const ids = new Set();
    asUser.forEach(doc => {
      const conn = doc.data();
      if (conn.connectedUserId) ids.add(conn.connectedUserId);
    });
    asConnected.forEach(doc => {
      const conn = doc.data();
      if (conn.userId) ids.add(conn.userId);
    });
    
    return Array.from(ids);
  }
  
  async getNewConnectionsCount(userId, since) {
    const [asUser, asConnected] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .where('acceptedAt', '>=', since)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .where('acceptedAt', '>=', since)
        .get()
    ]);
    
    return asUser.size + asConnected.size;
  }
  
  hasWeeklyActivity(stats) {
    return stats.newPlaces > 0 || stats.newConnections > 0 || stats.newMoments > 0;
  }
  
  hasMonthlyActivity(stats) {
    return stats.totalPlaces > 0 || stats.totalConnections > 0;
  }
}

// Create singleton instance
const engagementNotificationService = new EngagementNotificationService();

module.exports = engagementNotificationService;