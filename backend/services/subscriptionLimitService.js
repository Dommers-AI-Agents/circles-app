const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { getTierForStatus, LIMIT_ERROR_MESSAGES } = require('../config/subscriptionLimits');

const db = getFirestore();

class SubscriptionLimitService {
  /**
   * Get user's subscription status from the database
   * @param {string} userId - The user's ID
   * @returns {Promise<Object>} User's subscription data
   */
  async getUserSubscriptionData(userId) {
    try {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      
      if (!userDoc.exists) {
        console.error(`User not found: ${userId}`);
        return {
          subscriptionStatus: 'none',
          subscriptionExpiryDate: null,
          trialEndDate: null
        };
      }
      
      const userData = userDoc.data();

      // Check if subscription is expired
      let status = userData.subscriptionStatus || 'none';
      const expiryDate = userData.subscriptionExpiryDate ? new Date(userData.subscriptionExpiryDate) : null;
      // Manually verified premium users (isPremium/manuallyVerified) stay active
      // until their expiry date regardless of receipt state
      const hasManualPremium = (userData.manuallyVerified === true || userData.isPremium === true) &&
        (!expiryDate || expiryDate > new Date());

      if (hasManualPremium) {
        status = 'active';
      } else if (expiryDate && expiryDate < new Date() && status !== 'none') {
        status = 'expired';
        // Update status in database
        await userDoc.ref.update({ subscriptionStatus: 'expired' });
      }
      
      // Check if trial is expired
      if (status === 'trial' && userData.trialEndDate) {
        const trialEndDate = new Date(userData.trialEndDate);
        if (trialEndDate < new Date()) {
          status = 'expired';
          // Update status in database
          await userDoc.ref.update({ subscriptionStatus: 'expired' });
        }
      }
      
      return {
        subscriptionStatus: status,
        subscriptionExpiryDate: userData.subscriptionExpiryDate,
        trialEndDate: userData.trialEndDate
      };
    } catch (error) {
      console.error('Error fetching user subscription data:', error);
      // Default to free tier on error
      return {
        subscriptionStatus: 'none',
        subscriptionExpiryDate: null,
        trialEndDate: null
      };
    }
  }

  /**
   * Check if user can create a new circle
   * @param {string} userId - The user's ID
   * @returns {Promise<Object>} Result with canCreate flag and error message if applicable
   */
  async canCreateCircle(userId) {
    try {
      // Get user's subscription status
      const subscriptionData = await this.getUserSubscriptionData(userId);
      const tier = getTierForStatus(subscriptionData.subscriptionStatus);
      
      // If unlimited, allow creation
      if (tier.MAX_CIRCLES === Infinity) {
        return { canCreate: true };
      }
      
      // Count user's existing circles
      const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', userId)
        .get();
      
      const circleCount = circlesSnapshot.size;
      
      console.log(`📊 Circle limit check for user ${userId}:`, {
        subscriptionStatus: subscriptionData.subscriptionStatus,
        currentCircles: circleCount,
        maxAllowed: tier.MAX_CIRCLES,
        canCreate: circleCount < tier.MAX_CIRCLES
      });
      
      if (circleCount >= tier.MAX_CIRCLES) {
        return {
          canCreate: false,
          error: LIMIT_ERROR_MESSAGES.CIRCLE_LIMIT,
          currentCount: circleCount,
          maxAllowed: tier.MAX_CIRCLES
        };
      }
      
      return { canCreate: true };
    } catch (error) {
      console.error('Error checking circle creation limit:', error);
      // Allow creation on error (fail open for better UX)
      return { canCreate: true };
    }
  }

  /**
   * Check if user can add a place to a circle
   * @param {string} userId - The user's ID
   * @param {string} circleId - The circle's ID
   * @returns {Promise<Object>} Result with canAdd flag and error message if applicable
   */
  async canAddPlace(userId, circleId) {
    try {
      // Get user's subscription status
      const subscriptionData = await this.getUserSubscriptionData(userId);
      const tier = getTierForStatus(subscriptionData.subscriptionStatus);
      
      // If unlimited, allow adding
      if (tier.MAX_PLACES_PER_CIRCLE === Infinity) {
        return { canAdd: true };
      }
      
      // Count places in this circle (excluding soft-deleted)
      const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('deletedAt', '==', null)
        .get();
      
      const placeCount = placesSnapshot.size;
      
      console.log(`📊 Place limit check for user ${userId}, circle ${circleId}:`, {
        subscriptionStatus: subscriptionData.subscriptionStatus,
        currentPlaces: placeCount,
        maxAllowed: tier.MAX_PLACES_PER_CIRCLE,
        canAdd: placeCount < tier.MAX_PLACES_PER_CIRCLE
      });
      
      if (placeCount >= tier.MAX_PLACES_PER_CIRCLE) {
        return {
          canAdd: false,
          error: LIMIT_ERROR_MESSAGES.PLACE_LIMIT,
          currentCount: placeCount,
          maxAllowed: tier.MAX_PLACES_PER_CIRCLE
        };
      }
      
      return { canAdd: true };
    } catch (error) {
      console.error('Error checking place addition limit:', error);
      // Allow addition on error (fail open for better UX)
      return { canAdd: true };
    }
  }

  /**
   * Check if user can export content
   * @param {string} userId - The user's ID
   * @returns {Promise<Object>} Result with canExport flag and error message if applicable
   */
  async canExport(userId) {
    try {
      const subscriptionData = await this.getUserSubscriptionData(userId);
      const tier = getTierForStatus(subscriptionData.subscriptionStatus);
      
      if (!tier.CAN_EXPORT) {
        return {
          canExport: false,
          error: LIMIT_ERROR_MESSAGES.EXPORT_LIMIT
        };
      }
      
      return { canExport: true };
    } catch (error) {
      console.error('Error checking export permission:', error);
      // Deny export on error (fail closed for premium features)
      return {
        canExport: false,
        error: 'Unable to verify subscription status'
      };
    }
  }

  /**
   * Check if user can import places from other platforms
   * @param {string} userId - The user's ID
   * @returns {Promise<Object>} Result with canImport flag and error message if applicable
   */
  async canImport(userId) {
    try {
      const subscriptionData = await this.getUserSubscriptionData(userId);
      const tier = getTierForStatus(subscriptionData.subscriptionStatus);

      if (!tier.CAN_IMPORT) {
        return {
          canImport: false,
          error: LIMIT_ERROR_MESSAGES.IMPORT_LIMIT
        };
      }

      return { canImport: true };
    } catch (error) {
      console.error('Error checking import permission:', error);
      // Deny import on error (fail closed for premium features)
      return {
        canImport: false,
        error: 'Unable to verify subscription status'
      };
    }
  }

  /**
   * Check if user can share without watermark
   * @param {string} userId - The user's ID
   * @returns {Promise<Object>} Result with canShare flag and error message if applicable
   */
  async canShareWithoutWatermark(userId) {
    try {
      const subscriptionData = await this.getUserSubscriptionData(userId);
      const tier = getTierForStatus(subscriptionData.subscriptionStatus);
      
      if (!tier.CAN_SHARE_WITHOUT_WATERMARK) {
        return {
          canShare: false,
          error: LIMIT_ERROR_MESSAGES.WATERMARK_LIMIT
        };
      }
      
      return { canShare: true };
    } catch (error) {
      console.error('Error checking watermark permission:', error);
      // Deny watermark-free sharing on error (fail closed for premium features)
      return {
        canShare: false,
        error: 'Unable to verify subscription status'
      };
    }
  }

  /**
   * Get user's current usage and limits
   * @param {string} userId - The user's ID
   * @returns {Promise<Object>} Usage statistics and limits
   */
  async getUserUsageStats(userId) {
    try {
      const subscriptionData = await this.getUserSubscriptionData(userId);
      const tier = getTierForStatus(subscriptionData.subscriptionStatus);
      
      // Count circles
      const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', userId)
        .get();
      
      // Count places per circle
      const circleStats = [];
      for (const circleDoc of circlesSnapshot.docs) {
        const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
          .where('circleId', '==', circleDoc.id)
          .where('deletedAt', '==', null)
          .get();
        
        circleStats.push({
          circleId: circleDoc.id,
          circleName: circleDoc.data().name,
          placeCount: placesSnapshot.size,
          maxPlaces: tier.MAX_PLACES_PER_CIRCLE
        });
      }
      
      return {
        subscriptionStatus: subscriptionData.subscriptionStatus,
        circles: {
          current: circlesSnapshot.size,
          max: tier.MAX_CIRCLES
        },
        circleDetails: circleStats,
        canExport: tier.CAN_EXPORT,
        canShareWithoutWatermark: tier.CAN_SHARE_WITHOUT_WATERMARK
      };
    } catch (error) {
      console.error('Error getting user usage stats:', error);
      throw error;
    }
  }
}

// Export singleton instance
module.exports = new SubscriptionLimitService();