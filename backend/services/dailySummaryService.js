const { getFirestore, FieldValue } = require('../config/firebase');
const notificationService = require('./notificationService');
const emailService = require('./emailService');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

class DailySummaryService {
  constructor() {
    this.batchSize = 50; // Process users in batches
  }

  // Send daily summaries to all eligible users
  async sendDailySummaries() {
    console.log('📊 Starting daily summary generation...');
    
    try {
      // Get all users with daily summary enabled
      const usersSnapshot = await db.collection(COLLECTIONS.USERS)
        .where('notificationPreferences.dailySummary', '==', true)
        .get();

      if (usersSnapshot.empty) {
        console.log('No users have daily summary enabled');
        return;
      }

      const users = [];
      usersSnapshot.forEach(doc => users.push({ id: doc.id, ...doc.data() }));
      
      console.log(`📊 Processing daily summaries for ${users.length} users`);

      // Process users in batches
      for (let i = 0; i < users.length; i += this.batchSize) {
        const batch = users.slice(i, i + this.batchSize);
        await Promise.all(batch.map(user => this.generateAndSendSummary(user)));
      }

      console.log('✅ Daily summaries completed');
    } catch (error) {
      console.error('❌ Error in sendDailySummaries:', error);
      throw error;
    }
  }

  // Generate and send summary for individual user
  async generateAndSendSummary(user) {
    try {
      const userId = user.id;
      const stats = await this.gatherUserStats(userId);
      
      // Skip if no activity
      if (!this.hasActivity(stats)) {
        console.log(`⏭️ Skipping summary for ${user.displayName || userId} - no activity`);
        return;
      }

      // Build notification
      const notification = this.buildSummaryNotification(stats, user);
      
      // Send push notification
      await notificationService.sendToUser(userId, notification);
      
      // Send email summary
      await this.sendSummaryEmail(user, stats, notification);
      
      // Record that we sent today's summary
      await this.recordSummarySent(userId);
      
      console.log(`✅ Sent daily summary to ${user.displayName || userId}`);
    } catch (error) {
      console.error(`❌ Error sending summary to user ${user.id}:`, error);
    }
  }

  // Gather statistics for user's network activity
  async gatherUserStats(userId) {
    const stats = {
      newPlaces: 0,
      newPlacesByCategory: {},
      newConnections: 0,
      unreadMessages: 0,
      circleUpdates: 0,
      placeComments: 0,
      placeLikes: 0,
      topContributors: []
    };

    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    yesterday.setHours(0, 0, 0, 0);

    try {
      // Get user's connections
      const connectionsSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('participants', 'array-contains', userId)
        .where('status', '==', 'accepted')
        .get();

      const connectionIds = [];
      connectionsSnapshot.forEach(doc => {
        const connection = doc.data();
        const otherUserId = connection.participants.find(id => id !== userId);
        if (otherUserId) connectionIds.push(otherUserId);
      });

      // Get new connections from yesterday
      const newConnectionsSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
        .where('participants', 'array-contains', userId)
        .where('status', '==', 'accepted')
        .where('acceptedAt', '>=', yesterday.toISOString())
        .get();
      
      stats.newConnections = newConnectionsSnapshot.size;

      if (connectionIds.length > 0) {
        // Get new places from network (batch query due to Firestore limits)
        const placePromises = [];
        for (let i = 0; i < connectionIds.length; i += 10) {
          const batch = connectionIds.slice(i, i + 10);
          placePromises.push(
            db.collection(COLLECTIONS.PLACES)
              .where('addedBy', 'in', batch)
              .where('createdAt', '>=', yesterday.toISOString())
              .get()
          );
        }

        const placeSnapshots = await Promise.all(placePromises);
        const contributorCounts = {};

        placeSnapshots.forEach(snapshot => {
          snapshot.forEach(doc => {
            const place = doc.data();
            stats.newPlaces++;
            
            // Count by category
            const category = place.category || 'other';
            stats.newPlacesByCategory[category] = (stats.newPlacesByCategory[category] || 0) + 1;
            
            // Track contributors
            contributorCounts[place.addedBy] = (contributorCounts[place.addedBy] || 0) + 1;
          });
        });

        // Get top contributors
        const topContributorIds = Object.entries(contributorCounts)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 3)
          .map(([userId, count]) => ({ userId, count }));

        // Fetch contributor names
        for (const contributor of topContributorIds) {
          const userDoc = await db.collection(COLLECTIONS.USERS).doc(contributor.userId).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            stats.topContributors.push({
              name: userData.displayName || 'A connection',
              count: contributor.count
            });
          }
        }
      }

      // Get unread messages count
      const conversationsSnapshot = await db.collection(COLLECTIONS.CONVERSATIONS)
        .where('participants', 'array-contains', userId)
        .get();

      for (const convDoc of conversationsSnapshot.docs) {
        const conversation = convDoc.data();
        const unreadCount = conversation.unreadCounts?.[userId] || 0;
        stats.unreadMessages += unreadCount;
      }

      // Get activity on user's places (comments and likes)
      const userPlacesSnapshot = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', userId)
        .get();

      const userPlaceIds = userPlacesSnapshot.docs.map(doc => doc.id);

      if (userPlaceIds.length > 0) {
        // Get recent comments on user's places
        const commentPromises = userPlaceIds.map(placeId =>
          db.collection('placeComments')
            .where('placeId', '==', placeId)
            .where('createdAt', '>=', yesterday.toISOString())
            .get()
        );

        const commentSnapshots = await Promise.all(commentPromises);
        commentSnapshots.forEach(snapshot => {
          stats.placeComments += snapshot.size;
        });

        // Get recent likes on user's places
        const likePromises = userPlaceIds.map(placeId =>
          db.collection('placeLikes')
            .where('placeId', '==', placeId)
            .where('createdAt', '>=', yesterday.toISOString())
            .get()
        );

        const likeSnapshots = await Promise.all(likePromises);
        likeSnapshots.forEach(snapshot => {
          stats.placeLikes += snapshot.size;
        });
      }

    } catch (error) {
      console.error(`Error gathering stats for user ${userId}:`, error);
    }

    return stats;
  }

  // Check if user has any activity to report
  hasActivity(stats) {
    return stats.newPlaces > 0 || 
           stats.newConnections > 0 || 
           stats.unreadMessages > 0 || 
           stats.placeComments > 0 ||
           stats.placeLikes > 0;
  }

  // Build the summary notification
  buildSummaryNotification(stats, user) {
    const parts = [];
    
    // New places from network
    if (stats.newPlaces > 0) {
      parts.push(`${stats.newPlaces} new places`);
      
      // Add top category if significant
      const topCategory = Object.entries(stats.newPlacesByCategory)
        .sort((a, b) => b[1] - a[1])[0];
      if (topCategory && topCategory[1] > 3) {
        parts.push(`(${topCategory[1]} ${topCategory[0]}s)`);
      }
    }

    // New connections
    if (stats.newConnections > 0) {
      parts.push(`${stats.newConnections} new connection${stats.newConnections > 1 ? 's' : ''}`);
    }

    // Unread messages
    if (stats.unreadMessages > 0) {
      parts.push(`${stats.unreadMessages} unread message${stats.unreadMessages > 1 ? 's' : ''}`);
    }

    // Activity on user's places
    const activityParts = [];
    if (stats.placeComments > 0) {
      activityParts.push(`${stats.placeComments} comment${stats.placeComments > 1 ? 's' : ''}`);
    }
    if (stats.placeLikes > 0) {
      activityParts.push(`${stats.placeLikes} like${stats.placeLikes > 1 ? 's' : ''}`);
    }
    if (activityParts.length > 0) {
      parts.push(activityParts.join(' and ') + ' on your places');
    }

    // Build title and body
    const greeting = this.getGreeting(user);
    const title = `${greeting} Your Circles Update`;
    const body = parts.length > 0 ? parts.join(', ') : 'Check out what\'s new in your network';

    // Add top contributor mention if applicable
    let contributorNote = '';
    if (stats.topContributors.length > 0 && stats.topContributors[0].count >= 3) {
      contributorNote = ` • ${stats.topContributors[0].name} added ${stats.topContributors[0].count} places`;
    }

    return {
      type: 'daily_summary',
      title,
      body: body + contributorNote,
      // Daily summaries should not affect badge count - they're informational only
      badge: 0,
      data: {
        // Firebase pushes data fields to root level, so we need type here too
        type: 'daily_summary',
        summaryDate: new Date().toISOString().split('T')[0],
        newPlaces: stats.newPlaces.toString(),
        newConnections: stats.newConnections.toString(),
        unreadMessages: stats.unreadMessages.toString(),
        placeComments: stats.placeComments.toString(),
        placeLikes: stats.placeLikes.toString(),
        placeCategories: JSON.stringify(stats.newPlacesByCategory),
        topContributors: JSON.stringify(stats.topContributors.slice(0, 3))
      },
      // Also add at root level for iOS compatibility
      customData: {
        type: 'daily_summary'
      }
    };
  }

  // Get appropriate greeting emoji
  getGreeting(user) {
    const hour = new Date().getHours();
    if (hour < 12) return '🌅';
    if (hour < 17) return '☀️';
    return '🌙';
  }

  // Record that summary was sent today
  async recordSummarySent(userId) {
    try {
      await db.collection(COLLECTIONS.USERS).doc(userId).update({
        lastDailySummary: new Date().toISOString()
      });
    } catch (error) {
      console.error(`Error recording summary sent for ${userId}:`, error);
    }
  }

  // Check if user already received summary today
  async hasReceivedTodaysSummary(userId) {
    try {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (!userDoc.exists) return false;

      const userData = userDoc.data();
      if (!userData.lastDailySummary) return false;

      const lastSummary = new Date(userData.lastDailySummary);
      const today = new Date();
      
      return lastSummary.toDateString() === today.toDateString();
    } catch (error) {
      console.error(`Error checking summary status for ${userId}:`, error);
      return false;
    }
  }

  // Send summary email
  async sendSummaryEmail(user, stats, notification) {
    try {
      if (!user.email) {
        console.log(`⚠️ No email for user ${user.displayName}`);
        return;
      }

      const emailHtml = this.buildSummaryEmailHtml(user, stats, notification);
      
      await emailService.sendEmail({
        to: user.email,
        subject: notification.title,
        html: emailHtml
      });

      console.log(`📧 Sent summary email to ${user.email}`);
    } catch (error) {
      console.error(`❌ Error sending summary email to ${user.email}:`, error);
      // Don't throw - email failure shouldn't stop the process
    }
  }

  // Build HTML email for daily summary
  buildSummaryEmailHtml(user, stats, notification) {
    const today = new Date().toLocaleDateString('en-US', { 
      weekday: 'long', 
      year: 'numeric', 
      month: 'long', 
      day: 'numeric' 
    });

    const statsHtml = [];
    
    if (stats.newPlaces > 0) {
      const categoryList = Object.entries(stats.newPlacesByCategory)
        .sort((a, b) => b[1] - a[1])
        .map(([cat, count]) => `${count} ${cat}${count > 1 ? 's' : ''}`)
        .join(', ');
      
      statsHtml.push(`
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
          <h3 style="margin: 0 0 10px 0; color: #4CAF50;">🆕 ${stats.newPlaces} New Places</h3>
          <p style="margin: 0; color: #666;">${categoryList}</p>
          ${stats.topContributors.length > 0 ? `
            <p style="margin: 10px 0 0 0; color: #666;">
              Top contributors: ${stats.topContributors.slice(0, 3)
                .map(c => `${c.name} (${c.count})`)
                .join(', ')}
            </p>
          ` : ''}
        </div>
      `);
    }

    if (stats.newConnections > 0) {
      statsHtml.push(`
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
          <h3 style="margin: 0 0 10px 0; color: #2196F3;">👥 ${stats.newConnections} New Connection${stats.newConnections > 1 ? 's' : ''}</h3>
          <p style="margin: 0; color: #666;">Your network is growing!</p>
        </div>
      `);
    }

    if (stats.unreadMessages > 0) {
      statsHtml.push(`
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
          <h3 style="margin: 0 0 10px 0; color: #FF9800;">💬 ${stats.unreadMessages} Unread Message${stats.unreadMessages > 1 ? 's' : ''}</h3>
          <p style="margin: 0; color: #666;">Check your messages to stay connected</p>
        </div>
      `);
    }

    if (stats.placeComments > 0 || stats.placeLikes > 0) {
      const activities = [];
      if (stats.placeComments > 0) activities.push(`${stats.placeComments} comment${stats.placeComments > 1 ? 's' : ''}`);
      if (stats.placeLikes > 0) activities.push(`${stats.placeLikes} like${stats.placeLikes > 1 ? 's' : ''}`);
      
      statsHtml.push(`
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
          <h3 style="margin: 0 0 10px 0; color: #E91E63;">❤️ Activity on Your Places</h3>
          <p style="margin: 0; color: #666;">${activities.join(' and ')}</p>
        </div>
      `);
    }

    return `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>${notification.title}</title>
      </head>
      <body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff;">
          <!-- Header -->
          <div style="background-color: #4CAF50; padding: 30px 20px; text-align: center;">
            <h1 style="margin: 0; color: #ffffff; font-size: 24px;">Circles</h1>
            <p style="margin: 10px 0 0 0; color: #ffffff; font-size: 16px;">Your Daily Summary</p>
          </div>
          
          <!-- Content -->
          <div style="padding: 30px 20px;">
            <h2 style="margin: 0 0 20px 0; color: #333; font-size: 20px;">
              Hi ${user.displayName || 'there'} 👋
            </h2>
            
            <p style="color: #666; line-height: 1.6; margin: 0 0 20px 0;">
              Here's what happened in your Circles network yesterday:
            </p>
            
            ${statsHtml.join('')}
            
            <!-- CTA Button -->
            <div style="text-align: center; margin: 30px 0;">
              <a href="circles://daily-summary" style="display: inline-block; background-color: #4CAF50; color: #ffffff; text-decoration: none; padding: 12px 30px; border-radius: 25px; font-weight: 600;">
                View in App
              </a>
            </div>
            
            <!-- Footer -->
            <div style="border-top: 1px solid #eee; margin-top: 40px; padding-top: 20px; text-align: center;">
              <p style="color: #999; font-size: 14px; margin: 0;">
                ${today}
              </p>
              <p style="color: #999; font-size: 12px; margin: 10px 0 0 0;">
                You're receiving this because you have daily summaries enabled.<br>
                <a href="circles://settings/notifications" style="color: #4CAF50;">Manage notification preferences</a>
              </p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `;
  }
}

// Create singleton instance
const dailySummaryService = new DailySummaryService();

module.exports = dailySummaryService;