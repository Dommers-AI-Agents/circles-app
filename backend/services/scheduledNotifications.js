const cron = require('node-cron');
const { getFirestore } = require('../config/firebase');
const notificationService = require('./notificationService');
const dailySummaryService = require('./dailySummaryService');
const engagementNotificationService = require('./engagementNotificationService');
const milestoneService = require('./milestoneService');

const db = getFirestore();

class ScheduledNotifications {
  constructor() {
    this.jobs = new Map();
  }

  // Initialize all scheduled jobs
  initialize() {
    console.log('🕐 Initializing scheduled notifications...');
    
    // Daily summary at noon (12:00 PM) every day
    this.scheduleDailySummary();
    
    // Engagement reminders at 3 PM for inactive users
    this.scheduleEngagementReminders();
    
    // Weekly summary every Monday at 9 AM
    this.scheduleWeeklySummary();
    
    // Monthly summary on the 1st at 10 AM
    this.scheduleMonthlySummary();
    
    // Discovery prompts at strategic times
    this.scheduleDiscoveryPrompts();
    
    // Weekend recommendations
    this.scheduleWeekendRecommendations();
    
    // Weekly network growth check (Sunday nights)
    this.scheduleNetworkGrowthCheck();
    
    // Monthly top contributors (last day of month)
    this.scheduleTopContributors();
    
    // Special event notifications
    this.scheduleSpecialEvents();
    
    console.log('✅ Scheduled notifications initialized');
  }

  // Schedule daily summary notifications
  scheduleDailySummary() {
    // Run at 12:00 PM every day
    const job = cron.schedule('0 12 * * *', async () => {
      console.log('🌟 Running daily summary notifications...');
      try {
        await dailySummaryService.sendDailySummaries();
        console.log('✅ Daily summaries sent successfully');
      } catch (error) {
        console.error('❌ Error sending daily summaries:', error);
      }
    }, {
      scheduled: true,
      timezone: "America/New_York" // Default timezone, will be customized per user
    });

    this.jobs.set('dailySummary', job);
  }

  // Schedule engagement reminders for inactive users
  scheduleEngagementReminders() {
    // Run at 3:00 PM every day
    const job = cron.schedule('0 15 * * *', async () => {
      console.log('📱 Running engagement reminders...');
      try {
        await engagementNotificationService.sendEngagementReminders();
        console.log('✅ Engagement reminders sent successfully');
      } catch (error) {
        console.error('❌ Error sending engagement reminders:', error);
      }
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });

    this.jobs.set('engagementReminders', job);
  }

  // Schedule weekly summary
  scheduleWeeklySummary() {
    // Run every Monday at 9:00 AM
    const job = cron.schedule('0 9 * * 1', async () => {
      console.log('📊 Running weekly summary...');
      try {
        await engagementNotificationService.sendWeeklySummaries();
        console.log('✅ Weekly summaries sent successfully');
      } catch (error) {
        console.error('❌ Error sending weekly summaries:', error);
      }
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });

    this.jobs.set('weeklySummary', job);
  }

  // Schedule monthly summary
  scheduleMonthlySummary() {
    // Run on the 1st of each month at 10:00 AM
    const job = cron.schedule('0 10 1 * *', async () => {
      console.log('📅 Running monthly summary...');
      try {
        await engagementNotificationService.sendMonthlySummaries();
        console.log('✅ Monthly summaries sent successfully');
      } catch (error) {
        console.error('❌ Error sending monthly summaries:', error);
      }
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });

    this.jobs.set('monthlySummary', job);
  }

  // Schedule morning discovery prompts
  scheduleDiscoveryPrompts() {
    // Morning coffee spots (8:30 AM on weekdays)
    const morningJob = cron.schedule('30 8 * * 1-5', async () => {
      console.log('☕ Sending morning discovery prompts...');
      try {
        await this.sendDiscoveryPrompts('morning');
      } catch (error) {
        console.error('❌ Error sending morning prompts:', error);
      }
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });

    // Lunch recommendations (11:45 AM on weekdays)
    const lunchJob = cron.schedule('45 11 * * 1-5', async () => {
      console.log('🍽️ Sending lunch discovery prompts...');
      try {
        await this.sendDiscoveryPrompts('lunch');
      } catch (error) {
        console.error('❌ Error sending lunch prompts:', error);
      }
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });

    this.jobs.set('morningDiscovery', morningJob);
    this.jobs.set('lunchDiscovery', lunchJob);
  }

  // Schedule weekend recommendations
  scheduleWeekendRecommendations() {
    // Friday at 5:00 PM
    const weekendJob = cron.schedule('0 17 * * 5', async () => {
      console.log('🎉 Sending weekend recommendations...');
      try {
        await this.sendWeekendRecommendations();
      } catch (error) {
        console.error('❌ Error sending weekend recommendations:', error);
      }
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });

    this.jobs.set('weekendRecommendations', weekendJob);
  }

  // Schedule weekly network growth check
  scheduleNetworkGrowthCheck() {
    // Run every Sunday at 8:00 PM
    const job = cron.schedule('0 20 * * 0', async () => {
      console.log('📈 Checking weekly network growth...');
      try {
        await milestoneService.checkWeeklyNetworkGrowth();
        console.log('✅ Network growth check completed');
      } catch (error) {
        console.error('❌ Error checking network growth:', error);
      }
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });

    this.jobs.set('networkGrowth', job);
  }

  // Schedule top contributors check
  scheduleTopContributors() {
    // Run on the last day of each month at 6:00 PM
    const job = cron.schedule('0 18 28-31 * *', async () => {
      // Check if today is the last day of the month
      const today = new Date();
      const tomorrow = new Date(today);
      tomorrow.setDate(tomorrow.getDate() + 1);
      
      if (tomorrow.getDate() === 1) {
        console.log('🏆 Checking top contributors...');
        try {
          await milestoneService.checkTopContributors();
          console.log('✅ Top contributors check completed');
        } catch (error) {
          console.error('❌ Error checking top contributors:', error);
        }
      }
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });

    this.jobs.set('topContributors', job);
  }

  // Schedule special event notifications
  scheduleSpecialEvents() {
    // Christmas - December 20th at 10 AM
    const christmasJob = cron.schedule('0 10 20 12 *', async () => {
      await engagementNotificationService.sendSpecialEventNotification('christmas');
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });
    this.jobs.set('christmas', christmasJob);

    // Valentine's Day - February 12th at 10 AM
    const valentinesJob = cron.schedule('0 10 12 2 *', async () => {
      await engagementNotificationService.sendSpecialEventNotification('valentines');
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });
    this.jobs.set('valentines', valentinesJob);

    // Summer - June 21st at 10 AM
    const summerJob = cron.schedule('0 10 21 6 *', async () => {
      await engagementNotificationService.sendSpecialEventNotification('summer');
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });
    this.jobs.set('summer', summerJob);

    // Thanksgiving - Third Thursday of November (approximately 22nd)
    const thanksgivingJob = cron.schedule('0 10 22 11 *', async () => {
      await engagementNotificationService.sendSpecialEventNotification('thanksgiving');
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });
    this.jobs.set('thanksgiving', thanksgivingJob);

    // New Year - January 1st at 10 AM
    const newYearJob = cron.schedule('0 10 1 1 *', async () => {
      await engagementNotificationService.sendSpecialEventNotification('newyear');
    }, {
      scheduled: true,
      timezone: "America/New_York"
    });
    this.jobs.set('newyear', newYearJob);
  }

  // Send discovery prompts based on time of day
  async sendDiscoveryPrompts(timeOfDay) {
    try {
      // Get all active users who have discovery prompts enabled
      const usersSnapshot = await db.collection('users')
        .where('notificationPreferences.discoveryPrompts', '==', true)
        .get();

      const batchSize = 50;
      const users = [];
      usersSnapshot.forEach(doc => users.push({ id: doc.id, ...doc.data() }));

      // Process in batches to avoid overloading
      for (let i = 0; i < users.length; i += batchSize) {
        const batch = users.slice(i, i + batchSize);
        await Promise.all(batch.map(user => this.sendDiscoveryPromptToUser(user, timeOfDay)));
      }

      console.log(`✅ Sent ${timeOfDay} discovery prompts to ${users.length} users`);
    } catch (error) {
      console.error(`Error sending ${timeOfDay} discovery prompts:`, error);
    }
  }

  // Get the ids of a user's accepted connections. Connection docs use
  // userId/connectedUserId fields — NOT a participants array (that field is
  // on circleGroups); the old participants query silently matched nothing.
  async getAcceptedConnectionIds(userId) {
    const [asUser, asConnected] = await Promise.all([
      db.collection('connections')
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection('connections')
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    const ids = new Set();
    asUser.forEach(doc => ids.add(doc.data().connectedUserId));
    asConnected.forEach(doc => ids.add(doc.data().userId));
    return Array.from(ids);
  }

  // Winback: one push to users who lapsed 7-14 days ago (runs weekly, so each
  // lapse window gets at most one nudge). Respects the
  // notificationPreferences.reengagement toggle.
  async sendReengagementNotifications() {
    try {
      const now = new Date();
      const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      const fourteenDaysAgo = new Date(now.getTime() - 14 * 24 * 60 * 60 * 1000);

      const usersSnapshot = await db.collection('users').get();
      let sent = 0;
      let skipped = 0;

      for (const doc of usersSnapshot.docs) {
        const user = { id: doc.id, ...doc.data() };
        try {
          if (user.notificationPreferences?.reengagement === false) { skipped++; continue; }
          if (!user.lastLogin) { skipped++; continue; }

          const lastLogin = new Date(user.lastLogin);
          if (isNaN(lastLogin.getTime()) || lastLogin > sevenDaysAgo || lastLogin < fourteenDaysAgo) {
            skipped++;
            continue;
          }

          // Personalize with fresh network activity when there is any
          let body = 'Your favorite places are waiting — add a new spot you love!';
          const connectionIds = await this.getAcceptedConnectionIds(user.id);
          if (connectionIds.length > 0) {
            const placesSnapshot = await db.collection('places')
              .where('addedBy', 'in', connectionIds.slice(0, 10))
              .where('createdAt', '>=', sevenDaysAgo.toISOString())
              .limit(10)
              .get();
            if (placesSnapshot.size > 0) {
              const count = placesSnapshot.size;
              body = `Your friends added ${count} new place${count === 1 ? '' : 's'} this week — come see what's new!`;
            }
          }

          await notificationService.sendToUser(user.id, {
            type: 'reengagement',
            title: 'We miss you on Circles 👋',
            body: body,
            data: { type: 'reengagement' }
          });
          sent++;
        } catch (error) {
          console.error(`Reengagement failed for user ${user.id}:`, error.message);
        }
      }

      console.log(`✅ Reengagement notifications: ${sent} sent, ${skipped} skipped`);
      return { sent, skipped };
    } catch (error) {
      console.error('Error sending reengagement notifications:', error);
      throw error;
    }
  }

  // Send discovery prompt to individual user
  async sendDiscoveryPromptToUser(user, timeOfDay) {
    try {
      // Get recent places from user's network
      const connectionIds = await this.getAcceptedConnectionIds(user.id);

      if (connectionIds.length === 0) return;

      // Get recent places based on time of day
      let category;
      let title;
      let body;

      switch (timeOfDay) {
        case 'morning':
          category = 'coffee';
          title = '☕ Good morning!';
          body = 'Check out new coffee spots your network discovered';
          break;
        case 'lunch':
          category = 'restaurant';
          title = '🍽️ Hungry?';
          body = 'Your network added lunch spots nearby';
          break;
        default:
          return;
      }

      // Query recent places
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);

      const placesSnapshot = await db.collection('places')
        .where('addedBy', 'in', connectionIds.slice(0, 10)) // Firestore 'in' limit
        .where('category', '==', category)
        .where('createdAt', '>=', yesterday.toISOString())
        .limit(5)
        .get();

      if (placesSnapshot.empty) return;

      const placeCount = placesSnapshot.size;
      body = `Your network added ${placeCount} new ${category === 'coffee' ? 'coffee spots' : 'lunch spots'}`;

      await notificationService.sendToUser(user.id, {
        type: 'discovery_prompt',
        title,
        body,
        data: {
          promptType: timeOfDay,
          category,
          placeCount: placeCount.toString()
        }
      });

    } catch (error) {
      console.error(`Error sending discovery prompt to user ${user.id}:`, error);
    }
  }

  // Send weekend recommendations
  async sendWeekendRecommendations() {
    try {
      const usersSnapshot = await db.collection('users')
        .where('notificationPreferences.discoveryPrompts', '==', true)
        .get();

      const users = [];
      usersSnapshot.forEach(doc => users.push({ id: doc.id, ...doc.data() }));

      for (const user of users) {
        try {
          // Get trending places from network this week
          const weekAgo = new Date();
          weekAgo.setDate(weekAgo.getDate() - 7);

          // Get user's connections (userId/connectedUserId fields, both directions)
          const connectionIds = await this.getAcceptedConnectionIds(user.id);

          if (connectionIds.length === 0) continue;

          // Get trending places for weekend activities
          const placesSnapshot = await db.collection('places')
            .where('addedBy', 'in', connectionIds.slice(0, 10))
            .where('createdAt', '>=', weekAgo.toISOString())
            .orderBy('createdAt', 'desc')
            .limit(10)
            .get();

          if (placesSnapshot.empty) continue;

          const placeCount = placesSnapshot.size;

          await notificationService.sendToUser(user.id, {
            type: 'weekend_recommendations',
            title: '🎉 Weekend plans?',
            body: `Explore ${placeCount} new places from your network`,
            data: {
              promptType: 'weekend',
              placeCount: placeCount.toString()
            }
          });

        } catch (error) {
          console.error(`Error sending weekend recommendations to user ${user.id}:`, error);
        }
      }
    } catch (error) {
      console.error('Error sending weekend recommendations:', error);
    }
  }

  // Stop all scheduled jobs
  stop() {
    console.log('🛑 Stopping scheduled notifications...');
    this.jobs.forEach((job, name) => {
      job.stop();
      console.log(`  - Stopped ${name}`);
    });
    this.jobs.clear();
  }
}

// Create singleton instance
const scheduledNotifications = new ScheduledNotifications();

// Export instance with bound methods for external access
module.exports = {
  initialize: () => scheduledNotifications.initialize(),
  stop: () => scheduledNotifications.stop(),
  sendDiscoveryPrompts: (timeOfDay) => scheduledNotifications.sendDiscoveryPrompts(timeOfDay),
  sendWeekendRecommendations: () => scheduledNotifications.sendWeekendRecommendations()
};