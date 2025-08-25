const { getFirestore } = require('../config/firebase');
const engagementNotificationService = require('./engagementNotificationService');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

class MilestoneService {
  constructor() {
    this.db = db;
  }

  /**
   * Track when a user adds a new place and check for milestones
   */
  async onPlaceAdded(userId) {
    try {
      await engagementNotificationService.checkAndSendMilestone(userId, 'places');
      
      // Also check if user added multiple places recently (for friend activity alert)
      await this.checkRecentPlaceActivity(userId);
    } catch (error) {
      console.error('Error in onPlaceAdded:', error);
    }
  }

  /**
   * Track when a user makes a new connection and check for milestones
   */
  async onConnectionAccepted(userId) {
    try {
      await engagementNotificationService.checkAndSendMilestone(userId, 'connections');
    } catch (error) {
      console.error('Error in onConnectionAccepted:', error);
    }
  }

  /**
   * Track when a user adds a new moment and check for milestones
   */
  async onMomentAdded(userId) {
    try {
      await engagementNotificationService.checkAndSendMilestone(userId, 'moments');
    } catch (error) {
      console.error('Error in onMomentAdded:', error);
    }
  }

  /**
   * Check if user added multiple places in a short time
   * Triggers friend activity alert if 3+ places added in last hour
   */
  async checkRecentPlaceActivity(userId) {
    try {
      const oneHourAgo = new Date();
      oneHourAgo.setHours(oneHourAgo.getHours() - 1);
      
      const recentPlacesSnapshot = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', userId)
        .where('createdAt', '>=', oneHourAgo.toISOString())
        .get();
      
      if (recentPlacesSnapshot.size >= 3) {
        // Determine the most common category
        const categories = {};
        let mostCommonCategory = null;
        let maxCount = 0;
        
        recentPlacesSnapshot.forEach(doc => {
          const place = doc.data();
          const category = place.category || 'place';
          categories[category] = (categories[category] || 0) + 1;
          
          if (categories[category] > maxCount) {
            maxCount = categories[category];
            mostCommonCategory = category;
          }
        });
        
        // Send friend activity alert
        await engagementNotificationService.sendFriendActivityAlert(
          userId,
          recentPlacesSnapshot.size,
          mostCommonCategory
        );
      }
    } catch (error) {
      console.error('Error checking recent place activity:', error);
    }
  }

  /**
   * Check weekly network growth and send notifications
   * Should be called weekly (e.g., Sunday night)
   */
  async checkWeeklyNetworkGrowth() {
    try {
      console.log('📈 Checking weekly network growth...');
      
      const weekAgo = new Date();
      weekAgo.setDate(weekAgo.getDate() - 7);
      const weekAgoStr = weekAgo.toISOString();
      
      // Get all users
      const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
      
      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        
        try {
          // Count new connections this week
          const [asUser, asConnected] = await Promise.all([
            db.collection(COLLECTIONS.CONNECTIONS)
              .where('connectedUserId', '==', userId)
              .where('status', '==', 'accepted')
              .where('acceptedAt', '>=', weekAgoStr)
              .get(),
            db.collection(COLLECTIONS.CONNECTIONS)
              .where('userId', '==', userId)
              .where('status', '==', 'accepted')
              .where('acceptedAt', '>=', weekAgoStr)
              .get()
          ]);
          
          const newConnectionsCount = asUser.size + asConnected.size;
          
          // Send notification if 3+ new connections
          if (newConnectionsCount >= 3) {
            await engagementNotificationService.sendNetworkGrowthAlert(userId, newConnectionsCount);
          }
        } catch (error) {
          console.error(`Error checking network growth for ${userId}:`, error);
        }
      }
      
      console.log('✅ Weekly network growth check completed');
    } catch (error) {
      console.error('Error in checkWeeklyNetworkGrowth:', error);
    }
  }

  /**
   * Get user's achievement statistics
   */
  async getUserStats(userId) {
    try {
      const [placesCount, connectionsCount, momentsCount] = await Promise.all([
        engagementNotificationService.getUserPlacesCount(userId),
        engagementNotificationService.getUserConnectionsCount(userId),
        engagementNotificationService.getUserMomentsCount(userId)
      ]);
      
      // Get sent milestones
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      const user = userDoc.data();
      const sentMilestones = user?.sentMilestones || [];
      
      return {
        places: placesCount,
        connections: connectionsCount,
        moments: momentsCount,
        achievements: sentMilestones,
        nextMilestones: {
          places: this.getNextMilestone(placesCount, 'places'),
          connections: this.getNextMilestone(connectionsCount, 'connections'),
          moments: this.getNextMilestone(momentsCount, 'moments')
        }
      };
    } catch (error) {
      console.error('Error getting user stats:', error);
      return null;
    }
  }

  /**
   * Get the next milestone for a given count
   */
  getNextMilestone(currentCount, type) {
    const milestones = {
      places: [1, 10, 25, 50, 100, 250, 500],
      connections: [1, 5, 10, 25, 50, 100],
      moments: [1, 10, 25, 50]
    };
    
    const typeMilestones = milestones[type] || [];
    
    for (const milestone of typeMilestones) {
      if (currentCount < milestone) {
        return {
          value: milestone,
          remaining: milestone - currentCount
        };
      }
    }
    
    return null; // All milestones achieved
  }

  /**
   * Check if user is a top contributor (for leaderboard notifications)
   */
  async checkTopContributors() {
    try {
      console.log('🏆 Checking top contributors...');
      
      const monthAgo = new Date();
      monthAgo.setMonth(monthAgo.getMonth() - 1);
      const monthAgoStr = monthAgo.toISOString();
      
      // Get all places added in the last month
      const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
        .where('createdAt', '>=', monthAgoStr)
        .get();
      
      // Count by user
      const userCounts = {};
      placesSnapshot.forEach(doc => {
        const place = doc.data();
        const userId = place.addedBy;
        userCounts[userId] = (userCounts[userId] || 0) + 1;
      });
      
      // Get top 3 contributors
      const sortedUsers = Object.entries(userCounts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3);
      
      // Send notifications to top contributors
      for (let i = 0; i < sortedUsers.length; i++) {
        const [userId, count] = sortedUsers[i];
        const position = i + 1;
        
        let title, body;
        switch (position) {
          case 1:
            title = '🥇 Top contributor!';
            body = `You added the most places this month: ${count} places!`;
            break;
          case 2:
            title = '🥈 Second place!';
            body = `Great job! You added ${count} places this month.`;
            break;
          case 3:
            title = '🥉 Third place!';
            body = `Nice work! You added ${count} places this month.`;
            break;
        }
        
        const notification = {
          type: 'milestone',
          title,
          body,
          data: {
            type: 'milestone',
            milestoneType: 'top_contributor',
            position: position.toString(),
            placeCount: count.toString()
          }
        };
        
        await require('./notificationService').sendToUser(userId, notification);
      }
      
      console.log('✅ Top contributor notifications sent');
    } catch (error) {
      console.error('Error checking top contributors:', error);
    }
  }
}

// Create singleton instance
const milestoneService = new MilestoneService();

module.exports = milestoneService;