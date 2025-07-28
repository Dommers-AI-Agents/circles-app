const cron = require('node-cron');
const { getFirestore } = require('../config/firebase');
const notificationService = require('./notificationService');
const dailySummaryService = require('./dailySummaryService');

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
    
    // Discovery prompts at strategic times
    this.scheduleDiscoveryPrompts();
    
    // Weekend recommendations
    this.scheduleWeekendRecommendations();
    
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

  // Send discovery prompt to individual user
  async sendDiscoveryPromptToUser(user, timeOfDay) {
    try {
      // Get recent places from user's network
      const connectionsSnapshot = await db.collection('connections')
        .where('participants', 'array-contains', user.id)
        .where('status', '==', 'accepted')
        .get();

      const connectionIds = [];
      connectionsSnapshot.forEach(doc => {
        const connection = doc.data();
        const otherUserId = connection.participants.find(id => id !== user.id);
        if (otherUserId) connectionIds.push(otherUserId);
      });

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

          // Get user's connections
          const connectionsSnapshot = await db.collection('connections')
            .where('participants', 'array-contains', user.id)
            .where('status', '==', 'accepted')
            .get();

          const connectionIds = [];
          connectionsSnapshot.forEach(doc => {
            const connection = doc.data();
            const otherUserId = connection.participants.find(id => id !== user.id);
            if (otherUserId) connectionIds.push(otherUserId);
          });

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