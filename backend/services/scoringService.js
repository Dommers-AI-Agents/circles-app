// backend/services/scoringService.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

class ScoringService {
  constructor() {
    // Scoring weights configuration
    this.weights = {
      // Message History (0-50 points) - Increased weight
      messages: {
        hasMessages: 20,
        recentMessage: 10,      // within 7 days
        veryRecentMessage: 20   // within 24 hours - DOUBLED
      },
      // User Engagement (0-15 points) - Further reduced to prevent view count dominance
      engagement: {
        views: [
          { min: 1, max: 5, points: 2 },
          { min: 6, max: 15, points: 5 },
          { min: 16, max: 30, points: 8 },
          { min: 31, max: Infinity, points: 15 }
        ]
      },
      // Content & Activity (0-35 points) - Increased to better reward active users
      content: {
        hasUnviewedActivity: 18,  // Increased from 15
        placesBonus: [
          { min: 5, max: 10, points: 3 },   // Increased from 2
          { min: 11, max: 25, points: 5 },  // Increased from 3
          { min: 26, max: Infinity, points: 7 }  // Increased from 5
        ],
        // Total activity bonus for highly active users (viewed + unviewed)
        totalActivityBonus: [
          { min: 3, max: 5, points: 4 },   // Increased from 3
          { min: 6, max: 10, points: 7 },  // Increased from 6
          { min: 11, max: 20, points: 10 }, // Increased from 8
          { min: 21, max: Infinity, points: 12 } // Increased from 10
        ]
      },
      // Recency Bonus (0-15 points) - Increased from 10
      recency: {
        within24Hours: 15,  // Increased from 10
        within3Days: 10,    // Increased from 7
        within7Days: 5
      }
    };
  }

  /**
   * Calculate the weighted score for a connection
   * @param {Object} connection - The connection object with all stats
   * @param {string} currentUserId - The current user's ID
   * @returns {Object} - Score and breakdown
   */
  calculateConnectionScore(connection, currentUserId) {
    const scoreComponents = {
      messages: 0,
      engagement: 0,
      content: 0,
      recency: 0,
      total: 0
    };

    // 1. Message History Score (0-50 points)
    if (connection.lastMessageAt) {
      scoreComponents.messages += this.weights.messages.hasMessages;
      
      const messageAge = this.getAgeInDays(connection.lastMessageAt);
      if (messageAge <= 1) {
        scoreComponents.messages += this.weights.messages.veryRecentMessage;
      }
      if (messageAge <= 7) {
        scoreComponents.messages += this.weights.messages.recentMessage;
      }
    }

    // 2. User Engagement Score (0-20 points)
    const viewCount = connection.viewCount || 0;
    for (const tier of this.weights.engagement.views) {
      if (viewCount >= tier.min && viewCount <= tier.max) {
        scoreComponents.engagement = tier.points;
        break;
      }
    }

    // 3. Content & Activity Score (0-20 points)
    // Check for unviewed activity
    if (connection.hasRecentPlace || connection.hasNewActivity) {
      scoreComponents.content += this.weights.content.hasUnviewedActivity;
    }
    
    // Alternatively, check recentActivity array
    if (connection.recentActivity && connection.recentActivity.length > 0) {
      const hasUnviewed = connection.recentActivity.some(activity => {
        const viewedBy = activity.viewedBy || [];
        return !viewedBy.includes(currentUserId);
      });
      if (hasUnviewed && scoreComponents.content < this.weights.content.hasUnviewedActivity) {
        scoreComponents.content = this.weights.content.hasUnviewedActivity;
      }
    }

    // Places bonus
    const placesCount = connection.totalPlaces || 0;
    for (const tier of this.weights.content.placesBonus) {
      if (placesCount >= tier.min && placesCount <= tier.max) {
        scoreComponents.content += tier.points;
        break;
      }
    }

    // Total activity bonus for highly active users (NEW!)
    const totalActivityCount = connection.totalActivityCount || 0;
    for (const tier of this.weights.content.totalActivityBonus) {
      if (totalActivityCount >= tier.min && totalActivityCount <= tier.max) {
        scoreComponents.content += tier.points;
        break;
      }
    }

    // 4. Recency Bonus (0-15 points)
    const mostRecentActivity = this.getMostRecentActivityDate(connection);
    if (mostRecentActivity) {
      const ageInDays = this.getAgeInDays(mostRecentActivity);
      if (ageInDays <= 1) {
        scoreComponents.recency = this.weights.recency.within24Hours;
      } else if (ageInDays <= 3) {
        scoreComponents.recency = this.weights.recency.within3Days;
      } else if (ageInDays <= 7) {
        scoreComponents.recency = this.weights.recency.within7Days;
      }
    }

    // Calculate base total
    scoreComponents.total = 
      scoreComponents.messages + 
      scoreComponents.engagement + 
      scoreComponents.content + 
      scoreComponents.recency;

    // Enhanced multiplier system to prioritize meaningful interactions
    let multiplier = 1.0;
    
    // Check if has recent messages (within 7 days)
    const hasRecentMessages = connection.lastMessageAt && 
      this.getAgeInDays(connection.lastMessageAt) <= 7;
    
    // Check if has recent activity (within 7 days)
    const hasRecentActivity = mostRecentActivity && 
      this.getAgeInDays(mostRecentActivity) <= 7;
    
    // Check if has high content score (5+ points indicates active user)
    const hasHighContent = scoreComponents.content >= 5;
    
    // Apply 2.0x multiplier if user has BOTH recent messages and activity
    if (hasRecentMessages && hasRecentActivity) {
      multiplier = 2.0;  // Increased from 1.5
      console.log(`🚀 Applying 2.0x multiplier for user with recent messages AND activity`);
    }
    // Apply 1.6x multiplier for high-content users even without recent messages
    else if (hasHighContent && hasRecentActivity) {
      multiplier = 1.6;
      console.log(`📈 Applying 1.6x multiplier for high-content user with recent activity`);
    }
    // Apply 1.3x multiplier for users with just recent messages
    else if (hasRecentMessages) {
      multiplier = 1.3;
      console.log(`💬 Applying 1.3x multiplier for user with recent messages only`);
    }
    
    // Power user boost: Extra 1.2x multiplier for highly active users (20+ total activities AND 10+ places)
    const isPowerUser = totalActivityCount >= 20 && placesCount >= 10;
    if (isPowerUser) {
      multiplier *= 1.2;
      console.log(`⭐ Power user boost applied: ${displayName} has ${totalActivityCount} activities and ${placesCount} places`);
    }
    
    // Debug multiplier calculation for all users
    const displayName = connection.connectedUser?.displayName || 'Unknown';
    console.log(`📊 ${displayName}: hasRecentMessages=${hasRecentMessages} hasRecentActivity=${hasRecentActivity} hasHighContent=${hasHighContent} totalActivity=${totalActivityCount} multiplier=${multiplier}x`);
    
    // Special logging for Dan Wickner and Joseph Sgroi for comparison
    if (displayName.toLowerCase().includes('dan') || displayName.toLowerCase().includes('wickner') || 
        displayName.toLowerCase().includes('joseph') && displayName.toLowerCase().includes('sgroi')) {
      console.log(`🎯 ${displayName.toUpperCase()} SCORING BREAKDOWN:`);
      console.log(`   Has Recent Messages: ${hasRecentMessages} (${connection.lastMessageAt})`);
      console.log(`   Has Recent Activity: ${hasRecentActivity} (${mostRecentActivity})`);
      console.log(`   Has High Content: ${hasHighContent} (content score: ${scoreComponents.content})`);
      console.log(`   Total Activity Count: ${totalActivityCount}`);
      console.log(`   Unviewed Activity Count: ${connection.unviewedActivityCount || 0}`);
      console.log(`   Total Places: ${placesCount}`);
      console.log(`   Is Power User: ${isPowerUser} (${totalActivityCount} activities, ${placesCount} places)`);
      console.log(`   Multiplier Applied: ${multiplier}x`);
      console.log(`   Score Components: Messages=${scoreComponents.messages} Engagement=${scoreComponents.engagement} Content=${scoreComponents.content} Recency=${scoreComponents.recency}`);
      console.log(`   Base Score: ${scoreComponents.total}`);
      console.log(`   Final Score: ${Math.round(scoreComponents.total * multiplier)}`);
    }
    
    // Apply multiplier to final score
    let finalScore = Math.round(scoreComponents.total * multiplier);
    
    // Add tie-breaking decimal points based on content score for consistent ordering
    // This ensures users with higher content activity get slight advantage in ties
    const tieBreaker = scoreComponents.content / 1000; // Adds 0.001-0.035 decimal points
    finalScore += tieBreaker;

    return {
      score: finalScore,
      components: scoreComponents,
      multiplier: multiplier,
      tieBreaker: tieBreaker,
      calculatedAt: new Date()
    };
  }

  /**
   * Get the most recent activity date from various sources
   */
  getMostRecentActivityDate(connection) {
    const dates = [];
    
    // Check message timestamp
    if (connection.lastMessageAt) {
      dates.push(new Date(connection.lastMessageAt));
    }
    
    // Check last viewed timestamp
    if (connection.lastViewedAt) {
      dates.push(new Date(connection.lastViewedAt));
    }
    
    // Check last interaction
    if (connection.lastInteractionAt) {
      dates.push(new Date(connection.lastInteractionAt));
    }
    
    // Check recent activities (places/circles added)
    if (connection.recentActivity && connection.recentActivity.length > 0) {
      connection.recentActivity.forEach(activity => {
        if (activity.createdAt) {
          dates.push(new Date(activity.createdAt));
        }
      });
    }
    
    // Return the most recent date
    if (dates.length === 0) return null;
    return new Date(Math.max(...dates.map(d => d.getTime())));
  }

  /**
   * Calculate age in days from a date
   */
  getAgeInDays(date) {
    if (!date) return Infinity;
    const dateObj = date instanceof Date ? date : new Date(date);
    const now = new Date();
    const diffTime = Math.abs(now - dateObj);
    const diffDays = diffTime / (1000 * 60 * 60 * 24);
    return diffDays;
  }

  /**
   * Update connection score in database
   */
  async updateConnectionScore(connectionId, currentUserId, connection) {
    try {
      const scoreData = this.calculateConnectionScore(connection, currentUserId);
      
      await db.collection(COLLECTIONS.CONNECTIONS).doc(connectionId).update({
        connectionScore: scoreData.score,
        scoreComponents: scoreData.components,
        scoreLastCalculated: scoreData.calculatedAt
      });
      
      console.log(`✅ Updated score for connection ${connectionId}: ${scoreData.score}`);
      return scoreData;
    } catch (error) {
      console.error(`❌ Error updating connection score: ${error}`);
      throw error;
    }
  }

  /**
   * Batch update scores for all connections of a user
   */
  async updateAllConnectionScores(userId) {
    try {
      console.log(`🔄 Updating all connection scores for user ${userId}`);
      
      // Get all connections for the user
      const connectionsQuery1 = db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted');
      
      const connectionsQuery2 = db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted');
      
      const [snapshot1, snapshot2] = await Promise.all([
        connectionsQuery1.get(),
        connectionsQuery2.get()
      ]);
      
      const allConnections = [...snapshot1.docs, ...snapshot2.docs];
      const uniqueConnections = allConnections.filter((doc, index, self) => 
        index === self.findIndex(d => d.id === doc.id)
      );
      
      console.log(`📊 Found ${uniqueConnections.length} connections to update`);
      
      // Update scores in parallel batches
      const batchSize = 10;
      for (let i = 0; i < uniqueConnections.length; i += batchSize) {
        const batch = uniqueConnections.slice(i, i + batchSize);
        await Promise.all(
          batch.map(async (doc) => {
            const connection = doc.data();
            // Note: This assumes connection object has all necessary data populated
            // In practice, you might need to fetch additional data here
            await this.updateConnectionScore(doc.id, userId, connection);
          })
        );
      }
      
      console.log(`✅ Updated scores for all ${uniqueConnections.length} connections`);
    } catch (error) {
      console.error(`❌ Error updating all connection scores: ${error}`);
      throw error;
    }
  }
}

module.exports = new ScoringService();