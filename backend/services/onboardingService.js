// backend/services/onboardingService.js
// Service to handle new user onboarding with default circles and sample places

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, createCircle, createPlace } = require('../models/FirestoreModels');
const { DEFAULT_CIRCLES, getRandomLocalPlace } = require('../data/popularPlaces');
const PlaceDiscoveryService = require('./placeDiscoveryService');

const db = getFirestore();

// Every new user automatically FOLLOWS these accounts (the most content-rich
// ones), so their network isn't empty on day one. Combined with all-public
// default circles, following is enough to see these users' places.
const DEFAULT_FOLLOW_EMAILS = [
  'sgroiwes@gmail.com',      // Wes
  'brittanyvans@gmail.com'   // Brittany
];

// New users also receive a pending CONNECTION request from these accounts
// (a two-way relationship they can accept). Following is passive/one-way and
// needs no acceptance; a connection request is the active social nudge — kept
// to the two founder accounts so a brand-new user isn't greeted with a pile.
const DEFAULT_CONNECT_EMAILS = [
  'sgroiwes@gmail.com',      // Wes
  'brittanyvans@gmail.com'   // Brittany
];

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
        // Return success but indicate already completed
        return {
          success: true,
          circlesCreated: 0,
          message: 'Onboarding already completed'
        };
      }
      
      // Resolve the sample place BEFORE the transaction (network calls are not
      // allowed mid-transaction). Prefer a real place near the user's zipcode
      // so the sample is something they recognize; fall back to curated lists.
      const userCity = (userData.location || '').split(',')[0].trim() || userLocation?.city || null;
      let resolvedSamplePlace = await PlaceDiscoveryService.findNearbyPlace({
        zipcode: userData.zipcode || userLocation?.zipcode,
        coordinates: userData.lastKnownLocation || userLocation?.coordinates,
        city: userCity
      });
      if (!resolvedSamplePlace) {
        resolvedSamplePlace = getRandomLocalPlace(userCity ? { city: userCity } : userLocation);
        if (resolvedSamplePlace) {
          console.log(`📍 Onboarding: Using curated fallback place "${resolvedSamplePlace.name}"`);
        } else {
          console.log('📍 Onboarding: No location known — skipping sample place');
        }
      }

      // Create default circles and sample place in a transaction
      console.log(`🔄 Starting transaction for user ${userId}`);
      const result = await db.runTransaction(async (transaction) => {
        console.log(`📝 Inside transaction for user ${userId}`);
        const circleRefs = [];
        const circleIds = [];
        let samplePlaceData = null; // Define at transaction scope
        
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
        
        if (favoriteLocalSpotsIndex !== -1 && resolvedSamplePlace && resolvedSamplePlace.coordinates) {
          const favoriteCircleId = circleIds[favoriteLocalSpotsIndex];

          // Use the place resolved before the transaction (nearby search or
          // curated fallback). Without a resolved place we skip seeding rather
          // than plant a place from the wrong city.
          samplePlaceData = resolvedSamplePlace;

          // Create sample place
          const placeRef = db.collection(COLLECTIONS.PLACES).doc();
          const placeData = createPlace({
            name: samplePlaceData.name,
            description: samplePlaceData.description,
            address: samplePlaceData.address,
            location: {
              coordinates: samplePlaceData.coordinates
            },
            category: samplePlaceData.category || "restaurant",
            website: samplePlaceData.website || null,
            rating: samplePlaceData.rating || null,
            googlePlaceId: samplePlaceData.googlePlaceId || null,
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
      if (result.samplePlace) {
        console.log(`📍 Added sample place: ${result.samplePlace.name}`);
      }
      
      // Auto-follow the default accounts (best-effort — a failure here must
      // not fail onboarding)
      await OnboardingService.followDefaultUsers(userId, userData);

      // And greet them with a pending connection request from each default
      // account (best-effort as well)
      await OnboardingService.sendDefaultConnectionRequests(userId, userData);

      // Personal touch: Wes sends one favorite place as a directed suggestion,
      // so their "For You" inbox has a real, human first item (best-effort)
      await OnboardingService.sendWelcomeSuggestion(userId, userData);

      // Send SSE notification about onboarding completion
      const sseService = require('./sseService');
      sseService.notifyUser(userId, 'onboarding_completed', {
        circlesCreated: result.circleIds.length,
        samplePlace: result.samplePlace || null
      });
      
      return {
        success: true,
        circlesCreated: result.circleIds.length,
        samplePlace: result.samplePlace ? result.samplePlace.name : "No sample place added"
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
   * Make a new user follow the default accounts (Wes, Brittany). Idempotent:
   * already-followed targets are skipped, so retried onboarding can't double
   * the counts. The targets get the standard new-follower notification —
   * which doubles as a "someone new joined" signal for them.
   */
  static async followDefaultUsers(userId, userData = {}) {
    try {
      const { FieldValue } = require('firebase-admin/firestore');
      const snap = await db.collection(COLLECTIONS.USERS)
        .where('email', 'in', DEFAULT_FOLLOW_EMAILS)
        .get();

      const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
      const userDoc = await userRef.get();
      const alreadyFollowing = (userDoc.exists && userDoc.data().following) || [];

      const targets = snap.docs.filter(doc =>
        doc.id !== userId &&
        doc.data().email !== userData.email &&
        !alreadyFollowing.includes(doc.id)
      );
      if (targets.length === 0) return;

      const batch = db.batch();
      batch.update(userRef, {
        following: FieldValue.arrayUnion(...targets.map(doc => doc.id)),
        followingCount: FieldValue.increment(targets.length),
        updatedAt: new Date().toISOString()
      });
      targets.forEach(doc => {
        batch.update(doc.ref, {
          followers: FieldValue.arrayUnion(userId),
          followersCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        });
      });
      await batch.commit();
      console.log(`🤝 New user ${userId} auto-follows: ${targets.map(d => d.data().email).join(', ')}`);

      const notificationService = require('./notificationService');
      const newUserName = userData.displayName || userData.email || 'A new user';
      await Promise.all(targets.map(doc =>
        notificationService.sendFollowerNotification(doc.id, userId, newUserName)
          .catch(err => console.error('🔔 Auto-follow notification failed:', err.message))
      ));
    } catch (error) {
      // Best-effort: log and continue — onboarding already succeeded
      console.error(`⚠️ Auto-follow of default users failed for ${userId}:`, error.message);
    }
  }

  /**
   * Send the new user a pending connection request from each DEFAULT_CONNECT
   * account (Wes only). They already auto-follow Wes + Brittany, so their feed
   * isn't empty; this adds one active two-way relationship to accept. The
   * request lands immediately at signup. Idempotent: a connection existing in
   * either direction (any status) is left alone.
   */
  static async sendDefaultConnectionRequests(userId, userData = {}) {
    try {
      const { createConnection } = require('../models/FirestoreModels');
      const notificationService = require('./notificationService');
      const sseService = require('./sseService');

      const snap = await db.collection(COLLECTIONS.USERS)
        .where('email', 'in', DEFAULT_CONNECT_EMAILS)
        .get();
      const senders = snap.docs.filter(doc =>
        doc.id !== userId && doc.data().email !== userData.email
      );

      for (const senderDoc of senders) {
        const senderId = senderDoc.id;
        const [outgoing, incoming] = await Promise.all([
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', senderId)
            .where('connectedUserId', '==', userId)
            .limit(1).get(),
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', userId)
            .where('connectedUserId', '==', senderId)
            .limit(1).get()
        ]);
        if (!outgoing.empty || !incoming.empty) continue;

        const senderFirstName = (senderDoc.data().displayName || 'Circles').split(' ')[0];
        const connectionData = createConnection(
          senderId,
          userId,
          `Welcome to Circles! I'm ${senderFirstName} — let's connect so you can see my favorite places on your map.`
        );
        const ref = await db.collection(COLLECTIONS.CONNECTIONS).add(connectionData);

        await notificationService.notifyConnectionRequest(senderId, userId, ref.id)
          .catch(err => console.error('🔔 Welcome connection notification failed:', err.message));
        sseService.notifyUser(userId, 'connection_request', {
          connectionId: ref.id,
          from: { id: senderId, displayName: senderDoc.data().displayName || null },
          message: connectionData.message
        });
        console.log(`🤝 Welcome connection request sent to ${userId} from ${senderDoc.data().email}`);
      }
    } catch (error) {
      // Best-effort: log and continue — onboarding already succeeded
      console.error(`⚠️ Welcome connection requests failed for ${userId}:`, error.message);
    }
  }

  /**
   * Wes sends the new user ONE directed suggestion (a real favorite place), so
   * their "For You" inbox has a personal first item at signup instead of being
   * empty. Reuses the directed-suggestion model + notification. Best-effort.
   */
  static async sendWelcomeSuggestion(userId, userData = {}) {
    try {
      const { createSuggestion } = require('../models/FirestoreModels');
      const notificationService = require('./notificationService');
      const WELCOME_SENDER_EMAIL = 'sgroiwes@gmail.com'; // Wes

      // Resolve the sender (Wes); never suggest to himself
      const wesSnap = await db.collection(COLLECTIONS.USERS)
        .where('email', '==', WELCOME_SENDER_EMAIL).limit(1).get();
      if (wesSnap.empty) return;
      const wesId = wesSnap.docs[0].id;
      if (wesId === userId || wesSnap.docs[0].data().email === userData.email) return;

      // Pick one of Wes's saved places to recommend. Filter deletedAt/private in
      // memory (no composite index needed), then prefer a place with a photo and
      // the most likes so the first impression is a strong one.
      const placesSnap = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', wesId).get();
      const candidates = placesSnap.docs
        .map(d => ({ id: d.id, ...d.data() }))
        .filter(p => !p.deletedAt && p.privacy !== 'private' && p.name);
      if (candidates.length === 0) return;

      candidates.sort((a, b) => {
        const score = p => ((p.photos && p.photos.length) ? 100 : 0) + (p.likesCount || 0);
        return score(b) - score(a);
      });
      const place = candidates[0];

      // Build the directed suggestion (author = Wes, recipient = the new user)
      const suggestionData = createSuggestion({
        message: `Welcome to Circles! Here's one of my favorites to get you started — ${place.name}. ` +
                 `Tap to check it out, then save your own favorite places so your friends can find them too.`,
        placeId: place.id,
        // _id mirrored alongside id — the iOS Place decoder keys on _id, and a
        // missing one fails the WHOLE suggestions list decode client-side
        placeDetails: { _id: place.id, ...place },
        recipientId: userId,
        recipientName: userData.displayName || null
      }, wesId);

      const ref = await db.collection(COLLECTIONS.SUGGESTIONS).add(suggestionData);
      const suggestion = { _id: ref.id, id: ref.id, ...suggestionData };

      await notificationService.notifyDirectedSuggestion(suggestion, userId)
        .catch(err => console.error('🎁 Welcome suggestion notification failed:', err.message));

      console.log(`🎁 Welcome suggestion sent to ${userId} from Wes: "${place.name}"`);
    } catch (error) {
      // Best-effort: log and continue — onboarding already succeeded
      console.error(`⚠️ Welcome suggestion failed for ${userId}:`, error.message);
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
          name: "Playa Bowls",
          category: "cafe",
          description: "Acai bowls and smoothies - the original location",
          address: "806 Main St, Belmar, NJ 07719",
          coordinates: [-74.0256, 40.1802]
        },
        {
          name: "Federico's Pizza & Restaurant",
          category: "restaurant",
          description: "Family-owned Jersey Shore pizza spot",
          address: "700 Main St, Belmar, NJ 07719",
          coordinates: [-74.0254, 40.1817]
        }
      ];
      
      const batch = db.batch();
      const newPlaceIds = [];
      
      for (const placeData of additionalPlaces) {
        const placeRef = db.collection(COLLECTIONS.PLACES).doc();
        const fullPlaceData = createPlace({
          ...placeData,
          location: { coordinates: placeData.coordinates },
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