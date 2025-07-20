// backend/services/onboardingService.js
// Service to handle new user onboarding with default circles and sample places

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, createCircle, createPlace } = require('../models/FirestoreModels');
const { DEFAULT_CIRCLES, getRandomLocalPlace } = require('../data/popularPlaces');

const db = getFirestore();

class OnboardingService {
  
  /**
   * Complete onboarding for a new user
   * Creates default circles and adds a sample place
   */
  static async completeUserOnboarding(userId, userLocation = null) {
    try {
      console.log(`🎯 Starting onboarding for user: ${userId}`);
      
      // Check if user already completed onboarding
      const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
      const userDoc = await userRef.get();
      
      if (!userDoc.exists) {
        throw new Error('User not found');
      }
      
      const userData = userDoc.data();
      if (userData.onboardingCompleted) {
        console.log(`⚠️ User ${userId} already completed onboarding`);
        return;
      }
      
      // Create default circles and sample place in a transaction
      const result = await db.runTransaction(async (transaction) => {
        const circleRefs = [];
        const circleIds = [];
        
        // Create the three default circles
        for (const circleTemplate of DEFAULT_CIRCLES) {
          const circleRef = db.collection(COLLECTIONS.CIRCLES).doc();
          const circleData = createCircle(circleTemplate, userId);
          
          // Mark as default circle for potential future features
          circleData.isDefaultCircle = true;
          
          transaction.set(circleRef, circleData);
          circleRefs.push(circleRef);
          circleIds.push(circleRef.id);
          
          console.log(`📁 Created default circle: ${circleTemplate.name}`);
        }
        
        // Find the "Favorite Local Spots" circle to add sample place
        const favoriteLocalSpotsIndex = DEFAULT_CIRCLES.findIndex(
          circle => circle.name === "Favorite Local Spots"
        );
        
        if (favoriteLocalSpotsIndex !== -1) {
          const favoriteCircleId = circleIds[favoriteLocalSpotsIndex];
          
          // Get a random local place
          const samplePlaceData = getRandomLocalPlace(userLocation);
          
          // Create sample place
          const placeRef = db.collection(COLLECTIONS.PLACES).doc();
          const placeData = createPlace({
            name: samplePlaceData.name,
            description: samplePlaceData.description,
            address: samplePlaceData.address || "Local area",
            location: {
              coordinates: samplePlaceData.coordinates || [0, 0]
            },
            category: samplePlaceData.category || "restaurant",
            website: samplePlaceData.website || null,
            notes: "Added during onboarding - feel free to edit or remove!"
          }, favoriteCircleId, userId);
          
          // Mark as sample place
          placeData.isSamplePlace = true;
          
          transaction.set(placeRef, placeData);
          
          // Update the circle to include this place
          const favoriteCircleRef = circleRefs[favoriteLocalSpotsIndex];
          transaction.update(favoriteCircleRef, {
            places: [placeRef.id],
            placesCount: 1
          });
          
          console.log(`📍 Added sample place: ${samplePlaceData.name} to Favorite Local Spots`);
        }
        
        // Update user with onboarding completion and circle order
        transaction.update(userRef, {
          onboardingCompleted: true,
          hasCompletedTutorial: false, // New users need to complete tutorial
          circleOrder: circleIds,
          updatedAt: new Date().toISOString()
        });
        
        return { circleIds, samplePlace: samplePlaceData };
      });
      
      console.log(`✅ Onboarding completed for user ${userId}`);
      console.log(`📁 Created ${result.circleIds.length} default circles`);
      console.log(`📍 Added sample place: ${result.samplePlace.name}`);
      
      // Send SSE notification about onboarding completion
      const sseService = require('./sseService');
      sseService.notifyUser(userId, 'onboarding_completed', {
        circlesCreated: result.circleIds.length,
        samplePlace: result.samplePlace
      });
      
      return {
        success: true,
        circlesCreated: result.circleIds.length,
        samplePlace: result.samplePlace
      };
      
    } catch (error) {
      console.error(`❌ Onboarding failed for user ${userId}:`, error);
      
      // Don't throw error - onboarding failure shouldn't break registration
      // Just log the error and continue
      return {
        success: false,
        error: error.message
      };
    }
  }
  
  /**
   * Create additional sample content for user (can be called later)
   */
  static async addMoreSampleContent(userId) {
    try {
      console.log(`🎯 Adding more sample content for user: ${userId}`);
      
      const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
      const userDoc = await userRef.get();
      
      if (!userDoc.exists) {
        throw new Error('User not found');
      }
      
      // Get user's circles
      const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', userId)
        .get();
      
      if (circlesSnapshot.empty) {
        throw new Error('No circles found for user');
      }
      
      // Find "Want to Try" circle
      let wantToTryCircle = null;
      circlesSnapshot.docs.forEach(doc => {
        const circle = doc.data();
        if (circle.name === "Want to Try") {
          wantToTryCircle = { id: doc.id, ...circle };
        }
      });
      
      if (!wantToTryCircle) {
        console.log('⚠️ Want to Try circle not found');
        return;
      }
      
      // Add a few more sample places to "Want to Try"
      const additionalPlaces = [
        {
          name: "Local Coffee Shop",
          category: "cafe",
          description: "Cozy neighborhood coffee spot",
          address: "Your area"
        },
        {
          name: "New Restaurant",
          category: "restaurant", 
          description: "Trending spot everyone's talking about",
          address: "Your area"
        }
      ];
      
      const batch = db.batch();
      const newPlaceIds = [];
      
      for (const placeData of additionalPlaces) {
        const placeRef = db.collection(COLLECTIONS.PLACES).doc();
        const fullPlaceData = createPlace({
          ...placeData,
          location: { coordinates: [0, 0] },
          notes: "Sample place - edit or remove as needed"
        }, wantToTryCircle.id, userId);
        
        fullPlaceData.isSamplePlace = true;
        batch.set(placeRef, fullPlaceData);
        newPlaceIds.push(placeRef.id);
      }
      
      // Update circle with new places
      const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(wantToTryCircle.id);
      const updatedPlaces = [...(wantToTryCircle.places || []), ...newPlaceIds];
      batch.update(circleRef, {
        places: updatedPlaces,
        placesCount: updatedPlaces.length
      });
      
      await batch.commit();
      
      console.log(`✅ Added ${additionalPlaces.length} more sample places`);
      
    } catch (error) {
      console.error(`❌ Failed to add more sample content:`, error);
    }
  }
  
  /**
   * Check if user needs onboarding
   */
  static async needsOnboarding(userId) {
    try {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (!userDoc.exists) return false;
      
      const userData = userDoc.data();
      return !userData.onboardingCompleted;
    } catch (error) {
      console.error('Error checking onboarding status:', error);
      return false;
    }
  }
  
  /**
   * Get onboarding statistics for analytics
   */
  static async getOnboardingStats() {
    try {
      const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
      
      let totalUsers = 0;
      let onboardedUsers = 0;
      
      usersSnapshot.docs.forEach(doc => {
        totalUsers++;
        const userData = doc.data();
        if (userData.onboardingCompleted) {
          onboardedUsers++;
        }
      });
      
      return {
        totalUsers,
        onboardedUsers,
        onboardingRate: totalUsers > 0 ? (onboardedUsers / totalUsers * 100).toFixed(1) : 0
      };
    } catch (error) {
      console.error('Error getting onboarding stats:', error);
      return { totalUsers: 0, onboardedUsers: 0, onboardingRate: 0 };
    }
  }
}

module.exports = OnboardingService;