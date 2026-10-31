// backend/services/onboardingService.js
// Service to handle new user onboarding with default circles and sample places

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, createCircle, createPlace } = require('../models/FirestoreModels');
const { DEFAULT_CIRCLES, getRandomLocalPlace } = require('../data/popularPlaces');
const systemCircles = require('./systemCircles');

const db = getFirestore();

// Every new user automatically FOLLOWS these accounts (the most content-rich
// ones), so their network isn't empty on day one. Combined with all-public
// default circles, following is enough to see these users' places.
const { DEFAULT_FOLLOW_EMAILS } = require('./defaultAccounts');

// Retired 2026-10-09 (Wes): new users no longer get an automatic connection
// request — following Wes and Brittany is enough to start. Kept so
// sendDefaultConnectionRequests (now uncalled) still documents the old flow.
const DEFAULT_CONNECT_EMAILS = [
  'sgroiwes@gmail.com'       // Wes
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
      // allowed mid-transaction). Curated list only — the Google Nearby
      // Search that used to run first was the priciest SKU in the project
      // (~$32/1k) spent on a throwaway sample place.
      const userCity = (userData.location || '').split(',')[0].trim() || userLocation?.city || null;
      const resolvedSamplePlace = getRandomLocalPlace(userCity ? { city: userCity } : userLocation);
      if (resolvedSamplePlace) {
        console.log(`📍 Onboarding: Using curated sample place "${resolvedSamplePlace.name}"`);
      } else {
        console.log('📍 Onboarding: No location known — skipping sample place');
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
          // The ones features look up later carry their flag (createCircle
          // drops unknown keys, so it goes on after)
          if (circleTemplate.systemKind) Object.assign(circleData, systemCircles.flagFields(circleTemplate.systemKind));
          
          transaction.set(circleRef, circleData);
          circleRefs.push(circleRef);
          circleIds.push(circleRef.id);
          
          console.log(`📁 Created default circle: ${circleTemplate.name}`);
        }
        
        // Find the "Favorite Local Spots" circle to add sample place
        const favoriteLocalSpotsIndex = DEFAULT_CIRCLES.findIndex(
          circle => circle.systemKind === 'favoriteLocal'
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

      // No automatic connection request any more (Wes, 2026-10-09): new
      // users just follow Wes and Brittany, so they start with people on
      // their map without a request from a stranger to answer.

      // Personal touch: Wes sends one favorite place near them as a directed
      // suggestion. Only when signup told us where they are (an email
      // signup's zipcode); otherwise the first app open with a location fix
      // sends it (maybeSendWelcomeSuggestion).
      if (userData.lastKnownLocation) {
        await OnboardingService.sendWelcomeSuggestion(userId, userData, userData.lastKnownLocation);
      }

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
   * Deferred starter-place seeding. At signup nobody has granted location
   * yet, so the sample place usually can't resolve and users land in three
   * empty circles (all of the 2026-08-15 signups did). Called from app-open
   * once the app can share a location fix: if the default Favorite Local
   * Spots circle is still empty, resolve and seed the sample now. Bounded
   * attempts so users with no resolvable city don't retry forever.
   */
  static async seedSamplePlaceIfMissing(userId, coordinates = null) {
    try {
      const { FieldValue } = require('firebase-admin').firestore;

      // Single-equality query + memory filter (owner+isDefaultCircle would
      // need a composite index)
      const circles = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', userId).get();
      // Found by its flag (a renamed one still counts); a legacy unflagged
      // starter is matched by name and stamped
      const fav = await systemCircles.pickAndHeal(
        circles.docs.map(c => ({ id: c.id, ...c.data() })), 'favoriteLocal', { db });
      if (!fav || (fav.places || []).length > 0) return { seeded: false };

      const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
      const userDoc = await userRef.get();
      if (!userDoc.exists) return { seeded: false };
      const u = userDoc.data();
      if ((u.sampleSeedAttempts || 0) >= 5) return { seeded: false };
      await userRef.update({ sampleSeedAttempts: FieldValue.increment(1) });

      const userCity = (u.location || '').split(',')[0].trim() || null;
      // Curated list only — see the sample-place note in completeOnboarding
      const sample = getRandomLocalPlace(userCity ? { city: userCity } : null);
      if (!sample || !sample.coordinates) return { seeded: false };

      const placeRef = db.collection(COLLECTIONS.PLACES).doc();
      const placeData = createPlace({
        name: sample.name,
        description: sample.description,
        address: sample.address,
        location: { coordinates: sample.coordinates },
        category: sample.category || 'restaurant',
        website: sample.website || null,
        rating: sample.rating || null,
        googlePlaceId: sample.googlePlaceId || null,
        notes: 'Added during onboarding - feel free to edit or remove!'
      }, fav.id, userId);
      placeData.isSamplePlace = true;
      await placeRef.set(placeData);
      await db.collection(COLLECTIONS.CIRCLES).doc(fav.id).update({
        places: FieldValue.arrayUnion(placeRef.id),
        placesCount: FieldValue.increment(1),
        updatedAt: new Date().toISOString()
      });

      // Canonical venue link (fills cached category/city) — best-effort
      try {
        const { ensureGlobalPlaceLink } = require('./globalPlaceResolver');
        await ensureGlobalPlaceLink(await placeRef.get());
      } catch (e) { /* non-fatal */ }

      console.log(`🌱 Deferred sample place seeded for ${userId}: ${sample.name}`);
      return { seeded: true, name: sample.name };
    } catch (error) {
      console.error(`⚠️ Deferred sample seeding failed for ${userId}:`, error.message);
      return { seeded: false };
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

      // Wes AND Brittany follow every new user BACK (Wes's call, 2026-08-19):
      // both founder accounts follow new users; only Wes additionally sends a
      // connection request (see DEFAULT_CONNECT_EMAILS).
      const followBackDocs = targets;

      const batch = db.batch();
      const newUserUpdate = {
        following: FieldValue.arrayUnion(...targets.map(doc => doc.id)),
        followingCount: FieldValue.increment(targets.length),
        updatedAt: new Date().toISOString()
      };
      if (followBackDocs.length > 0) {
        // arrayUnion() with zero args throws — only add when Wes is in play
        newUserUpdate.followers = FieldValue.arrayUnion(...followBackDocs.map(doc => doc.id));
        newUserUpdate.followersCount = FieldValue.increment(followBackDocs.length);
      }
      batch.update(userRef, newUserUpdate);
      targets.forEach(doc => {
        const followsBack = followBackDocs.includes(doc);
        const update = {
          followers: FieldValue.arrayUnion(userId),
          followersCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        };
        if (followsBack) {
          update.following = FieldValue.arrayUnion(userId);
          update.followingCount = FieldValue.increment(1);
        }
        batch.update(doc.ref, update);
      });
      await batch.commit();
      console.log(`🤝 New user ${userId} auto-follows: ${targets.map(d => d.data().email).join(', ')}${followBackDocs.length ? ' (Wes follows back)' : ''}`);

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
          `Welcome to FavCircles! I'm ${senderFirstName} — let's connect so you can see my favorite places on your map.`
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
  /**
   * The welcome suggestion for accounts signup couldn't place (Apple, Google
   * and passkey signups ask no zipcode). Called on app open: with a location
   * fix it sends one nearby; without one it waits an hour for a fix (the
   * location prompt comes right after signup), then sends one near Charlotte,
   * the default location. Only for accounts under a week old, and only once.
   */
  static async maybeSendWelcomeSuggestion(userId, userData = {}, near = null) {
    if (userData.welcomeSuggestionAt) return;
    const created = Date.parse(userData.createdAt && userData.createdAt.toDate
      ? userData.createdAt.toDate().toISOString() : userData.createdAt);
    if (!Number.isFinite(created)) return;
    const age = Date.now() - created;
    if (age > 7 * 86400000) return;
    if (!near && age < 3600000) return;
    await OnboardingService.sendWelcomeSuggestion(userId, userData, near);
  }

  static async sendWelcomeSuggestion(userId, userData = {}, near = null) {
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

      // Accounts from before the welcomeSuggestionAt flag already have one
      const earlier = await db.collection(COLLECTIONS.SUGGESTIONS)
        .where('recipientId', '==', userId).get();
      if (earlier.docs.some(d => d.data().userId === wesId)) return;

      // Once per account: claim it before sending, so a signup and an app
      // open racing each other can't both send one
      const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
      const claimed = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(userRef);
        if (!fresh.exists || fresh.data().welcomeSuggestionAt) return false;
        tx.update(userRef, { welcomeSuggestionAt: new Date().toISOString() });
        return true;
      });
      if (!claimed) return;

      // Pick one of Wes's real favorites that anyone may see, near them when
      // he has one there: a place in a public circle, not a want-to-go save or a bare street address
      // (services/welcomePlacePick.js). None qualifies → no suggestion.
      const { pickWelcomePlace } = require('./welcomePlacePick');
      const [placesSnap, circlesSnap, sentSnap] = await Promise.all([
        db.collection(COLLECTIONS.PLACES).where('addedBy', '==', wesId).get(),
        db.collection(COLLECTIONS.CIRCLES).where('owner', '==', wesId).where('privacy', '==', 'public').get(),
        // His last 200 suggestions: how often each place went out as a welcome
        db.collection(COLLECTIONS.SUGGESTIONS).where('userId', '==', wesId)
          .orderBy('createdAt', 'desc').limit(200).select('placeId', 'message', 'welcome').get()
          .catch((error) => { console.warn('🎁 Welcome rotation counts unavailable:', error.message); return { docs: [] }; })
      ]);
      const place = pickWelcomePlace(
        placesSnap.docs.map(d => ({ id: d.id, ...d.data() })),
        new Set(circlesSnap.docs.map(d => d.id)),
        { near, sentCounts }
      );
      if (!place) return;

      // Build the directed suggestion (author = Wes, recipient = the new user)
      const suggestionData = createSuggestion({
        message: `Welcome to FavCircles! Here's one of my favorites to get you started — ${place.name}. ` +
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
      const sentCounts = new Map();
      for (const doc of sentSnap.docs) {
        const d = doc.data();
        if (d.welcome !== true && !String(d.message || '').startsWith('Welcome to FavCircles!')) continue;
        if (d.placeId) sentCounts.set(d.placeId, (sentCounts.get(d.placeId) || 0) + 1);
      }

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
      suggestionData.welcome = true; // counted by the rotation above
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
      // Found by its flag; a legacy unflagged starter by name, then stamped
      const wantToTryCircle = await systemCircles.pickAndHeal(
        circlesSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })), 'wantToTry', { db });
      
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