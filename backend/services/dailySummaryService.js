const { getFirestore, FieldValue } = require('../config/firebase');
const notificationService = require('./notificationService');
const emailService = require('./emailService');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

class DailySummaryService {
  constructor() {
    this.batchSize = 50; // Process users in batches
  }

  // Send daily summaries to all eligible users.
  // Runs every hour: each user gets their summary at the hour of their
  // preferred summaryTime, evaluated in their own timezone (both from
  // notificationPreferences; defaults 12:00 America/New_York).
  async sendDailySummaries() {
    console.log('📊 Starting daily summary generation...');

    try {
      // Implement distributed lock to prevent concurrent executions
      const lockAcquired = await this.acquireDailySummaryLock();
      if (!lockAcquired) {
        console.log('⚠️ Daily summary already running for this hour - skipping execution');
        return;
      }

      console.log('🔒 Acquired daily summary execution lock');

      try {
        // Get all users with daily summary enabled
        const usersSnapshot = await db.collection(COLLECTIONS.USERS)
          .where('notificationPreferences.dailySummary', '==', true)
          .get();

      if (usersSnapshot.empty) {
        console.log('No users have daily summary enabled');
        return;
      }

      const allUsers = [];
      usersSnapshot.forEach(doc => allUsers.push({ id: doc.id, ...doc.data() }));

      // Only users whose local clock is at their chosen summary hour right now
      const users = allUsers.filter(user => this.isUsersSummaryHour(user));

      console.log(`📊 Processing daily summaries for ${users.length} of ${allUsers.length} enabled users (local-hour match)`);

      // Process users in batches
      for (let i = 0; i < users.length; i += this.batchSize) {
        const batch = users.slice(i, i + this.batchSize);
        await Promise.all(batch.map(user => this.generateAndSendSummary(user)));
      }

        console.log('✅ Daily summaries completed');
      } finally {
        // Always release the lock, even if there was an error
        await this.releaseDailySummaryLock();
        console.log('🔓 Released daily summary execution lock');
      }
    } catch (error) {
      console.error('❌ Error in sendDailySummaries:', error);
      // Make sure to release lock on error
      await this.releaseDailySummaryLock();
      throw error;
    }
  }

  // Generate and send summary for individual user
  async generateAndSendSummary(user) {
    try {
      const userId = user.id;
      const stats = await this.gatherUserStats(userId);
      
      // Check if user has already received today's summary
      if (await this.hasReceivedTodaysSummary(userId)) {
        console.log(`⏭️ User ${user.displayName || userId} already received today's summary`);
        return;
      }

      // Quiet days stay quiet: a summary only goes out when there is real
      // network activity to report. (The old "engagement prompt" fallback was
      // retired — the engagement reminder job already covers re-engagement,
      // and stacking both trained users to mute notifications.)
      if (!this.hasActivity(stats)) {
        console.log(`⏭️ Skipping summary for ${user.displayName || userId} - no activity`);
        return;
      }

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
      topContributors: [],
      connectionCount: 0,
      userPlaceCount: 0
    };

    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    yesterday.setHours(0, 0, 0, 0);

    try {
      // Get user's connections (need to check both userId and connectedUserId fields)
      const [connectionsAsUser, connectionsAsConnected] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', userId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('connectedUserId', '==', userId)
          .where('status', '==', 'accepted')
          .get()
      ]);

      const connectionIds = [];
      
      // Process connections where user is the initiator
      connectionsAsUser.forEach(doc => {
        const connection = doc.data();
        if (connection.connectedUserId) {
          connectionIds.push(connection.connectedUserId);
        }
      });
      
      // Process connections where user is the recipient
      connectionsAsConnected.forEach(doc => {
        const connection = doc.data();
        if (connection.userId) {
          connectionIds.push(connection.userId);
        }
      });
      
      // Remove duplicates
      const uniqueConnectionIds = [...new Set(connectionIds)];
      
      // Store total connection count
      stats.connectionCount = uniqueConnectionIds.length;
      
      // Replace connectionIds with unique ones
      connectionIds.length = 0;
      connectionIds.push(...uniqueConnectionIds);

      // Get new connections from yesterday
      try {
        const [newConnectionsAsUser, newConnectionsAsConnected] = await Promise.all([
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', userId)
            .where('status', '==', 'accepted')
            .where('acceptedAt', '>=', yesterday.toISOString())
            .get(),
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('connectedUserId', '==', userId)
            .where('status', '==', 'accepted')
            .where('acceptedAt', '>=', yesterday.toISOString())
            .get()
        ]);
        
        stats.newConnections = newConnectionsAsUser.size + newConnectionsAsConnected.size;
      } catch (error) {
        console.log('⚠️ Could not query new connections (index may be needed)');
        stats.newConnections = 0;
      }

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
      
      // Store user's total place count
      stats.userPlaceCount = userPlaceIds.length;

      if (userPlaceIds.length > 0) {
        // Get recent comments on user's places. Comments are keyed by the
        // canonical venue record (globalPlaceId); createdAt is filtered in
        // memory to avoid needing a new composite index.
        const userGlobalPlaceIds = [...new Set(
          userPlacesSnapshot.docs.map(doc => doc.data().globalPlaceId).filter(Boolean)
        )];
        const commentPromises = userGlobalPlaceIds.map(globalPlaceId =>
          db.collection('placeComments')
            .where('globalPlaceId', '==', globalPlaceId)
            .get()
        );

        const commentSnapshots = await Promise.all(commentPromises);
        const cutoff = yesterday.toISOString();
        commentSnapshots.forEach(snapshot => {
          snapshot.docs.forEach(doc => {
            if (String(doc.data().createdAt || '') >= cutoff) {
              stats.placeComments += 1;
            }
          });
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
    // Include new places from connections as activity!
    return stats.newPlaces > 0 || 
           stats.newConnections > 0 || 
           stats.unreadMessages > 0 || 
           stats.placeComments > 0 ||
           stats.placeLikes > 0;
  }

  // Build the summary notification
  buildSummaryNotification(stats, user) {
    const parts = [];
    const emojis = [];
    
    // New places from network
    if (stats.newPlaces > 0) {
      emojis.push('📍');
      parts.push(`${stats.newPlaces} new place${stats.newPlaces > 1 ? 's' : ''}`);
      
      // Add top category if significant
      const topCategory = Object.entries(stats.newPlacesByCategory)
        .sort((a, b) => b[1] - a[1])[0];
      if (topCategory && topCategory[1] >= 2) {
        // Include category name in parentheses for context
        const categoryName = topCategory[0].charAt(0).toUpperCase() + topCategory[0].slice(1);
        parts[parts.length - 1] += ` (${topCategory[1]} ${categoryName})`;
      }
    }

    // New connections
    if (stats.newConnections > 0) {
      emojis.push('👥');
      parts.push(`${stats.newConnections} new connection${stats.newConnections > 1 ? 's' : ''}`);
    }

    // Unread messages
    if (stats.unreadMessages > 0) {
      emojis.push('💬');
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
      emojis.push('❤️');
      parts.push(activityParts.join(' & ') + ' on your places');
    }

    // Build title and body with more detail
    const greeting = this.getGreeting(user);
    const title = `Your Daily Summary`;
    
    // Create a concise but informative body
    let body = '';
    if (parts.length === 0) {
      body = 'Check out what\'s new in your network';
    } else if (parts.length === 1) {
      body = parts[0];
    } else if (parts.length === 2) {
      body = parts.join(' • ');
    } else {
      // For 3+ items, show first two with count of remaining
      body = parts.slice(0, 2).join(' • ') + ` + ${parts.length - 2} more`;
    }

    // Add emoji prefix to body for visual appeal
    const emojiPrefix = emojis.slice(0, 3).join(' ');
    if (emojiPrefix) {
      body = emojiPrefix + ' ' + body;
    }

    // Add top contributor mention if significant
    let contributorNote = '';
    if (stats.topContributors.length > 0 && stats.topContributors[0].count >= 2) {
      contributorNote = ` (${stats.topContributors[0].name} shared ${stats.topContributors[0].count})`;
    }

    // Format date for subtitle
    const today = new Date();
    const dateFormatter = new Intl.DateTimeFormat('en-US', { 
      month: 'long', 
      day: 'numeric',
      year: 'numeric'
    });
    const subtitle = dateFormatter.format(today);

    return {
      type: 'daily_summary',
      title,
      subtitle, // Add subtitle with formatted date
      body: body + contributorNote,
      // Daily summaries should not affect badge count - they're informational only
      badge: 0,
      data: {
        // Keep only essential fields to stay under APNS 4KB limit
        type: 'daily_summary',
        summaryDate: new Date().toISOString().split('T')[0]
        // Removed large fields that were causing APNS payload to exceed 4KB limit
        // The app can fetch full summary data via API when notification is tapped
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

  // True when the user's local clock is currently in the hour of their chosen
  // summaryTime. Invalid/missing timezone falls back to America/New_York,
  // which matches the historical noon-ET behavior.
  isUsersSummaryHour(user) {
    const prefs = user.notificationPreferences || {};
    const preferredHour = parseInt(String(prefs.summaryTime || '12:00').split(':')[0], 10);
    if (isNaN(preferredHour)) return false;

    let localHour;
    try {
      localHour = parseInt(new Intl.DateTimeFormat('en-US', {
        timeZone: prefs.timezone || 'America/New_York',
        hour: 'numeric',
        hour12: false
      }).format(new Date()), 10) % 24;
    } catch (error) {
      localHour = parseInt(new Intl.DateTimeFormat('en-US', {
        timeZone: 'America/New_York',
        hour: 'numeric',
        hour12: false
      }).format(new Date()), 10) % 24;
    }

    return localHour === preferredHour;
  }

  // Check if user already received summary today. A rolling 20-hour window
  // instead of a calendar-date compare: it is timezone-proof (the server's
  // "today" is not the user's "today") and still allows the next day's
  // summary at the same local hour, including across DST shifts.
  async hasReceivedTodaysSummary(userId) {
    try {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (!userDoc.exists) return false;

      const userData = userDoc.data();
      if (!userData.lastDailySummary) return false;

      const hoursSinceLast = (Date.now() - new Date(userData.lastDailySummary).getTime()) / (1000 * 60 * 60);
      return hoursSinceLast < 20;
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
                <a href="https://api.favcircles.com/app/open?path=settings/notifications" style="color: #4CAF50;">Manage notification preferences</a>
              </p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `;
  }

  // Acquire distributed lock for daily summary execution
  async acquireDailySummaryLock() {
    // Keyed by UTC date+hour: the job runs hourly (each hour serves the users
    // whose local time matches), so the lock only guards against concurrent
    // runs within the same hour, not against later hours the same day
    const now = new Date();
    const today = `${now.toISOString().split('T')[0]}-${String(now.getUTCHours()).padStart(2, '0')}`;
    const lockId = `daily-summary-${today}`;
    const lockDoc = db.collection('system_locks').doc(lockId);
    
    try {
      // Try to create the lock document atomically
      await lockDoc.create({
        lockType: 'daily_summary',
        date: today,
        acquiredAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(), // 2 hour expiry
        status: 'acquired'
      });
      
      console.log(`🔒 Successfully acquired lock for daily summary: ${lockId}`);
      return true;
    } catch (error) {
      if (error.code === 6) { // ALREADY_EXISTS error code
        console.log(`⚠️ Daily summary lock already exists for ${today} - another process is running`);
        return false;
      } else {
        console.error('Error acquiring daily summary lock:', error);
        throw error;
      }
    }
  }

  // Release distributed lock for daily summary execution
  async releaseDailySummaryLock() {
    const now = new Date();
    const today = `${now.toISOString().split('T')[0]}-${String(now.getUTCHours()).padStart(2, '0')}`;
    const lockId = `daily-summary-${today}`;
    const lockDoc = db.collection('system_locks').doc(lockId);
    
    try {
      await lockDoc.update({
        status: 'completed',
        completedAt: new Date().toISOString()
      });
      console.log(`🔓 Successfully released lock for daily summary: ${lockId}`);
    } catch (error) {
      // Don't throw error on lock release failure - just log it
      console.warn('Warning: Could not release daily summary lock:', error.message);
    }
  }
}

// Create singleton instance
const dailySummaryService = new DailySummaryService();

module.exports = dailySummaryService;