// backend/controllers/checkInController.js
const { getFirestore, FieldValue, GeoPoint } = require('../config/firebase');
const { firstPhotoUrl, venuePhotoUrl, resolvePlacePhoto } = require('../services/placePhoto');
const { 
  COLLECTIONS, 
  createCheckIn, 
  createPlace,
  createCircle,
  validateCheckIn,
  createNotification,
  validateNotification,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { createActivity } = require('../services/activity/createActivity');
const { recordPrivateCheckIn } = require('../services/ownActivity/record');
const notificationService = require('../services/notificationService');
const { isCheckInVisibleTo } = require('../services/checkInVisibility');

const { buildViewerContext } = require('../services/viewerContext');
const { allowedAudiences, qualifyingAudiences, loadActivityPrivacyByActor } = require('../services/activityPrivacy');

/// The read rule for a list of check-ins: the check-in's own visibility, then
/// the owner's "who can see my activity" grid for check-ins. One context and
/// one grid read per request, shared by the active feed and the at-place list.
const visibleCheckIns = async (docs, userId) => {
  const ctx = { ...(await buildViewerContext(userId)), isInAnyGroup: isUserInAnyGroup };
  const settings = await loadActivityPrivacyByActor(docs.map(doc => doc.data().userId));
  const out = [];
  for (const doc of docs) {
    const data = doc.data();
    if (!(await isCheckInVisibleTo(data, userId, ctx))) continue;
    const qualifying = qualifyingAudiences(ctx, data.userId);
    // Marked "Everyone" by its owner: the grid is for check-ins made without a choice.
    if (qualifying !== null && data.audience !== 'public') {
      const allowed = allowedAudiences(settings.get(String(data.userId)), 'checkIns');
      if (!qualifying.some(audience => allowed[audience])) continue;
    }
    out.push(serializeDoc(doc));
  }
  return out;
};
const sseService = require('../services/sseService');
const { indexSavedPlace } = require('../services/circleLocationSummary');
const { ensureGlobalPlaceLink, findCanonicalByNameAndLocation } = require('../services/globalPlaceResolver');
const checkInStats = require('../services/checkInStatsService');
const { sanitizeCheckInRecipients, capPlaceText, gatedPlacesLookup } = require('../services/checkInGuards');

const db = getFirestore();

// Helper function to find or create user's check-in circle
async function findOrCreateCheckInCircle(userId) {
  try {
    // Look for existing check-in circle
    const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .where('isCheckInCircle', '==', true)
      .get();

    const flagged = circlesSnapshot.docs.find(doc => !doc.data().deletedAt);
    if (flagged) {
      return serializeDoc(flagged);
    }

    // Legacy check-in circles were created before createCircle persisted the
    // isCheckInCircle flag, so the query above can't see them — adopt an
    // existing "Check-in Places" circle by name instead of creating a duplicate
    const byNameSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .where('name', '==', 'Check-in Places')
      .get();

    const candidates = byNameSnapshot.docs.filter(doc => !doc.data().deletedAt);
    if (candidates.length > 0) {
      // Prefer the copy that already has places, then the oldest
      candidates.sort((a, b) => {
        const placesDiff = (b.data().places || []).length - (a.data().places || []).length;
        if (placesDiff !== 0) return placesDiff;
        return (a.data().createdAt || '').localeCompare(b.data().createdAt || '');
      });
      const keeper = candidates[0];
      await keeper.ref.update({ isCheckInCircle: true, updatedAt: new Date().toISOString() });
      const keeperDoc = await keeper.ref.get();
      console.log(`✅ Adopted legacy Check-in Places circle ${keeper.id} for user ${userId}`);
      return serializeDoc(keeperDoc);
    }

    // Create new check-in circle
    const checkInCircleData = {
      name: 'Check-in Places',
      description: 'Places I\'ve checked into',
      privacy: 'public', // Public by default for discovery
      isCheckInCircle: true,
      icon: '📍',
      color: '#4CAF50'
    };
    
    const circle = createCircle(checkInCircleData, userId);
    const circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circle);
    const circleDoc = await circleRef.get();
    
    console.log(`✅ Created Check-in Places circle for user ${userId}`);
    return serializeDoc(circleDoc);
  } catch (error) {
    console.error('Error finding/creating check-in circle:', error);
    throw error;
  }
}

// The Google lookup lives in services/googleEnrichment.js (shared with
// Add Place and Build my map); check-ins use it through the same name.
const { enrichPlaceWithGoogleData } = require('../services/googleEnrichment');
// Has this user already saved this VENUE? (services/ownSaveOfVenue — shared
// with Add Place's duplicate answer)
const { findExistingSaveOfVenue } = require('../services/ownSaveOfVenue');

// Shared with createPlace (share-extension saves use the same
// canonical-first-then-Google enrichment)
exports.enrichPlaceWithGoogleData = enrichPlaceWithGoogleData;

// Create a new check-in
exports.createCheckIn = async (req, res) => {
  try {
    const userId = req.user.uid;
    const checkInData = req.body;
    
    // Get user data for check-in
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    const userData = userDoc.data();

    // Recipients trimmed to what this person may reach (own conversations,
    // accepted connections, nobody blocked) and venue text capped BEFORE the
    // model derives isPrivate from them and they're stored (security audit
    // 2026-10-01 — see services/checkInGuards.js).
    capPlaceText(checkInData);
    if (checkInData.isPrivate !== true) {
      Object.assign(checkInData, await sanitizeCheckInRecipients(userId, userData, checkInData));
    }

    // Create check-in object
    const checkIn = createCheckIn(checkInData, userId, userData);

    // Convert coordinates to GeoPoint if provided
    if (checkInData.latitude && checkInData.longitude) {
      checkIn.location = new GeoPoint(checkInData.latitude, checkInData.longitude);
    }
    
    // Validate check-in data
    const errors = validateCheckIn(checkInData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        errors
      });
    }
    
    // Save to Firestore
    const checkInRef = await db.collection(COLLECTIONS.CHECK_INS).add(checkIn);
    const checkInDoc = await checkInRef.get();
    const checkInId = checkInRef.id;

    // Piggy bank: half a FavCoin per venue per day for showing up. Venue identity
    // falls back to name+address for check-ins at places without a saved doc.
    // Awaited for the coin-drop; credit() never throws.
    const piggyBank = await require('../services/piggyBankService').credit({
      userId,
      eventType: 'check_in',
      sourceRef: {
        checkInId,
        placeId: checkIn.placeId || `${checkIn.placeName}:${checkIn.placeAddress || ''}`
      }
    });
    
    // Send notifications to selected groups
    for (const groupId of checkIn.notifiedGroups) {
      // Create a special check-in message in the group
      const messageData = {
        type: 'check_in',
        content: `${userData.displayName} checked in at ${checkIn.placeName}`,
        metadata: {
          checkInId: checkInId,
          placeName: checkIn.placeName,
          placeAddress: checkIn.placeAddress,
          duration: checkIn.duration,
          message: checkIn.message,
          endTime: checkIn.endTime
        }
      };
      
      // Add message to conversation
      const messageRef = await db.collection(COLLECTIONS.MESSAGES).add({
        conversationId: groupId,
        senderId: userId,
        ...messageData,
        createdAt: new Date().toISOString()
      });
      
      // Update conversation's last message
      await db.collection(COLLECTIONS.CONVERSATIONS).doc(groupId).update({
        lastMessage: messageData.content,
        lastMessageTime: new Date().toISOString(),
        lastMessageSenderId: userId,
        lastMessageSenderName: null, // list endpoint resolves it; never leave a previous sender's name
        updatedAt: new Date().toISOString()
      });
    }
    
    // Send notifications to individual users
    console.log(`📍 Sending check-in notifications to ${checkIn.notifiedUsers.length} users`);
    for (const notifiedUserId of checkIn.notifiedUsers) {
      console.log(`📍 Sending check-in notification to user: ${notifiedUserId}`);
      try {
        // Save notification to Firestore
        const notificationData = createNotification({
          userId: notifiedUserId,
          type: 'check_in',
          title: 'Check-in Notification',
          body: `${userData.displayName} is at ${checkIn.placeName}${checkIn.message ? ': ' + checkIn.message : ''}`,
          data: {
            checkInId: checkInId,
            placeName: checkIn.placeName,
            fromUserId: userId,
            fromUserName: userData.displayName,
            fromUserPhoto: userData.profilePicture || null,
            message: checkIn.message || null
          }
        });

        const validationErrors = validateNotification(notificationData);
        if (validationErrors.length === 0) {
          const notificationRef = await db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
          
          // Send SSE event for real-time notification count update
          sseService.notifyUser(notifiedUserId, 'new_notification', {
            notificationId: notificationRef.id,
            type: 'check_in',
            title: notificationData.title,
            body: notificationData.body,
            data: notificationData.data
          });
        } else {
          console.error('❌ Validation errors for check-in notification:', validationErrors);
        }

        // Also send push notification
        const result = await notificationService.sendToUser(notifiedUserId, {
          type: 'check_in',
          title: 'Check-in Notification',
          body: `${userData.displayName} is at ${checkIn.placeName}${checkIn.message ? ': ' + checkIn.message : ''}`,
          data: {
            checkInId: checkInId,
            placeName: checkIn.placeName,
            userId: userId,
            // iOS routes check-in taps on placeId — without it the tap did nothing
            placeId: checkIn.placeId || null
          }
        });
        console.log(`📍 Check-in notification result for ${notifiedUserId}:`, result);
      } catch (error) {
        console.error(`📍 Failed to send check-in notification to ${notifiedUserId}:`, error);
      }
    }
    
    // Every check-in is remembered as a saved place — regardless of whether
    // it's broadcast to the feed. The feed toggle only gates the activity row
    // below (it used to gate this whole block, so a quiet check-in at a new
    // venue was never saved anywhere).
    let finalPlaceId = checkIn.placeId;
    let placePhoto = null;
    let circleIdForActivity = checkIn.circleId;
    let globalPlaceId = null;
    // Venue id carried over from another user's save, when that's what the
    // client referenced — lets the match skip the name lookup
    let checkInVenueHint = null;

    if (checkIn.placeId) {
      // Check if place exists in database (a trashed save doesn't count —
      // the picker can still hand us one, and the venue must be re-saved)
      try {
        const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(checkIn.placeId).get();
        if (placeDoc.exists && !placeDoc.data().deletedAt && placeDoc.data().addedBy === userId) {
          const placeData = placeDoc.data();
          placePhoto = firstPhotoUrl(placeData.photos);
          circleIdForActivity = placeData.circleId || circleIdForActivity;
          globalPlaceId = placeData.globalPlaceId || await ensureGlobalPlaceLink(placeDoc);
        } else {
          // Missing, trashed, or SOMEONE ELSE's save (Check In from a
          // connection's place page): clear it so the venue is matched
          // against this user's own saves or added to their check-in circle
          if (placeDoc.exists && !placeDoc.data().deletedAt) {
            checkInVenueHint = placeDoc.data().globalPlaceId || null;
            if (!checkIn.location && placeDoc.data().location && Array.isArray(placeDoc.data().location.coordinates)) {
              const [lng, lat] = placeDoc.data().location.coordinates;
              checkIn.location = new GeoPoint(lat, lng);
            }
          }
          finalPlaceId = null;
          circleIdForActivity = null;
        }
      } catch (error) {
        console.error('Error fetching existing place for activity:', error);
        finalPlaceId = null;
      }
    }

    // If no valid place ID, reuse an existing save of this VENUE or create one
    // in the check-in circle
    if (!finalPlaceId) {
      try {
        // Canonical venue first — if anyone on the platform has saved this
        // place, the globalPlaces record already carries the venue data and
        // Google isn't consulted at all. Google runs only for venues new to
        // the whole platform (the once-per-venue purchase).
        let canonicalDoc = null;
        let canonicalData = null;
        if (checkIn.location) {
          try {
            canonicalDoc = await findCanonicalByNameAndLocation(checkIn.placeName, {
              coordinates: [checkIn.location.longitude, checkIn.location.latitude]
            });
            if (canonicalDoc) {
              canonicalData = canonicalDoc.data();
              console.log(`✅ Check-in matched canonical venue ${canonicalDoc.id} — skipping Google enrichment`);
            }
          } catch (canonicalError) {
            console.error('⚠️ Canonical venue lookup failed, falling back to Google:', canonicalError.message);
          }
        }

        const existingSave = await findExistingSaveOfVenue({
          userId,
          globalPlaceId: (canonicalDoc ? canonicalDoc.id : null) || checkInVenueHint,
          placeName: checkIn.placeName,
          location: checkIn.location
        });

        if (existingSave) {
          // Use existing place
          finalPlaceId = existingSave.id;
          const existingPlace = existingSave.data();
          placePhoto = firstPhotoUrl(existingPlace.photos);
          circleIdForActivity = existingPlace.circleId || circleIdForActivity;
          globalPlaceId = existingPlace.globalPlaceId || (canonicalDoc ? canonicalDoc.id : null)
            || checkInVenueHint || await ensureGlobalPlaceLink(existingSave);
          console.log(`✅ Using existing place for check-in: ${checkIn.placeName} (ID: ${finalPlaceId})`);
        } else {
          // Get or create the user's check-in circle
          const checkInCircle = await findOrCreateCheckInCircle(userId);
          circleIdForActivity = checkInCircle.id;

          // Paid lookup only with a location, under the per-user daily cap,
          // and never twice for a remembered miss (security audit 2026-10-01)
          const googleData = canonicalData ? {} : await gatedPlacesLookup({
            userId,
            placeName: checkIn.placeName,
            location: checkIn.location,
            lookup: enrichPlaceWithGoogleData
          });

          // Create new place in check-in circle with enriched data. When a
          // canonical venue matched, only identity fields are stamped here —
          // rating/hours/etc. overlay from the venue record on every read.
          const placeData = {
            name: (canonicalData && canonicalData.name) || googleData.name || checkIn.placeName,
            address: (canonicalData && canonicalData.address) || googleData.address || checkIn.placeAddress,
            location: checkIn.location ? {
              coordinates: [checkIn.location.longitude, checkIn.location.latitude]
            } : null,
            // Arrives as 'other' unless the client sent one; the cascade
            // derives the real category from googleTypes when the venue
            // record is created, and ensureGlobalPlaceLink stamps it back.
            category: checkIn.placeCategory || (canonicalData && canonicalData.category) || 'other',
            googleTypes: googleData.googleTypes || (canonicalData && canonicalData.googleTypes) || [],
            photos: googleData.photos || [],
            googlePlaceId: (canonicalData && canonicalData.googlePlaceId) || googleData.googlePlaceId || null,
            rating: googleData.rating || null,
            priceLevel: googleData.priceLevel || null,
            website: googleData.website || null,
            phoneNumber: googleData.phoneNumber || null,
            openingHours: googleData.openingHours || null,
            delivery: googleData.delivery ?? null,
            dineIn: googleData.dineIn ?? null,
            reservable: googleData.reservable ?? null,
            takeout: googleData.takeout ?? null,
            curbsidePickup: googleData.curbsidePickup ?? null,
            addedViaCheckIn: true
          };

          // Create the place document in the check-in circle
          const place = createPlace(placeData, checkInCircle.id, userId);
          const placeRef = await db.collection(COLLECTIONS.PLACES).add(place);
          finalPlaceId = placeRef.id;

          // Link the save to its canonical venue record (best-effort)
          globalPlaceId = await ensureGlobalPlaceLink(await placeRef.get());

          // Keep the browse location tree fresh (best-effort)
          indexSavedPlace(checkInCircle.id, placeData);

          // Update the circle's places array
          await db.collection(COLLECTIONS.CIRCLES).doc(checkInCircle.id).update({
            places: FieldValue.arrayUnion(finalPlaceId),
            placesCount: FieldValue.increment(1),
            updatedAt: new Date().toISOString()
          });

          // Use the first photo for activity thumbnail; canonical venues
          // contribute theirs (never a raw googleapis URL — those bill per
          // render)
          placePhoto = firstPhotoUrl(placeData.photos) || venuePhotoUrl(canonicalData);

          console.log(`✅ Created enriched place in check-in circle: ${placeData.name} (ID: ${finalPlaceId})`);
        }
      } catch (error) {
        console.error('Error creating place from check-in:', error);
        // Continue without place ID if creation fails
      }
    }

    // Personal history: "checked in 7 times, last Sep 5". Keyed by venue so
    // every save/typed variant of the same place shares one bucket. Also
    // stamps the resolved ids on the check-in doc so the backfill and any
    // later reader can key it without re-resolving.
    let myCheckInStats = null;
    if (globalPlaceId) {
      const stats = await checkInStats.recordCheckIn({
        userId,
        globalPlaceId,
        checkInId,
        placeId: finalPlaceId,
        placeName: checkIn.placeName,
        at: checkIn.createdAt
      });
      myCheckInStats = checkInStats.toApi(stats);
    }
    // No photo of its own (a fresh check-in save, or one never given a
    // picture): the venue's cover or first photo, whatever shape it's stored in.
    if (!placePhoto && (finalPlaceId || globalPlaceId)) {
      placePhoto = await resolvePlacePhoto({ placeId: finalPlaceId, globalPlaceId });
    }

    const stamp = {};
    if (globalPlaceId && !checkIn.globalPlaceId) stamp.globalPlaceId = globalPlaceId;
    if (finalPlaceId && finalPlaceId !== checkIn.placeId) stamp.placeId = finalPlaceId;
    if (Object.keys(stamp).length > 0) {
      await checkInRef.update(stamp).catch((error) =>
        console.error('⚠️ Failed to stamp venue ids on check-in:', error.message));
      Object.assign(checkIn, stamp);
    }

    // A rating given on the check-in screen: latest wins, history kept, tied
    // to this check-in. finalPlaceId is always the user's own save here.
    let ratingApplied = null;
    const ratingInput = checkInData.rating;
    if (finalPlaceId && ratingInput !== undefined && ratingInput !== null && ratingInput !== '') {
      try {
        const { appendRating, sanitizeRating } = require('../utils/ratingHistory');
        const score = sanitizeRating(ratingInput);
        if (score !== null) {
          const saveRef = db.collection(COLLECTIONS.PLACES).doc(finalPlaceId);
          const saveDoc = await saveRef.get();
          if (saveDoc.exists && saveDoc.data().addedBy === userId) {
            const save = saveDoc.data();
            const now = new Date().toISOString();
            const history = appendRating(save.ratingHistory, { rating: score, at: now, checkInId }, (
              save.userRating === null || save.userRating === undefined ? null
                : { rating: save.userRating, at: save.userRatedAt || save.updatedAt || save.createdAt || null }
            ));
            const update = { userRating: score, userRatedAt: now, updatedAt: now };
            if (history) update.ratingHistory = history;
            await saveRef.update(update);
            ratingApplied = score;
          }
        }
      } catch (ratingError) {
        console.error('⚠️ Check-in rating not applied:', ratingError.message);
      }
    }

    // The note is also a comment on the place ONLY when the client says so
    // (postComment:true — older app builds never send it, and their messages
    // are "here till 8, come by" chatter, not venue commentary). "Just me"
    // (explicit isPrivate) never posts; the feed switch is a separate choice.
    let postedCommentId = null;
    const note = String(checkIn.message || '').trim();
    if (finalPlaceId && note && checkInData.isPrivate !== true && checkInData.postComment === true) {
      try {
        const saveDoc = await db.collection(COLLECTIONS.PLACES).doc(finalPlaceId).get();
        if (saveDoc.exists) {
          const { postPlaceComment } = require('../services/placeCommentService');
          // No place_commented feed row: the check-in row already carries the note
          const { comment } = await postPlaceComment({ placeDoc: saveDoc, userId, text: note, source: 'check_in', checkInId, trackActivity: false });
          postedCommentId = comment.id;
        }
      } catch (commentError) {
        console.error('⚠️ Check-in comment not posted:', commentError.message);
      }
    }

    // Add to activity feed if enabled; otherwise it still goes on the owner's
    // own Activity tab as a private row nobody else sees.
    if (!checkIn.showInActivityFeed) {
      recordPrivateCheckIn(userId, checkIn, { checkInId, placeId: finalPlaceId, placePhoto, rating: ratingApplied });
    }
    if (checkIn.showInActivityFeed) {
      await createActivity(
        'check_in',
        userId,
        'check_in',
        checkInId,
        checkIn.placeName,
        {
          placeAddress: checkIn.placeAddress,
          message: checkIn.message,
          endTime: checkIn.endTime,
          circleId: circleIdForActivity,
          circleName: null, // Could fetch circle name if needed
          placePhoto: placePhoto,
          placeId: finalPlaceId, // Use the guaranteed place ID
          globalPlaceId: globalPlaceId || null,
          latitude: checkIn.location ? checkIn.location.latitude : null,
          longitude: checkIn.location ? checkIn.location.longitude : null,
          placeCategory: checkIn.placeCategory || 'other',
          // Stamped so the feed can gate the row the same way it gates
          // moments. A check-in activity carries no circle to hang privacy
          // on, so without this an Inner Circle check-in posted to the feed
          // would reach every connection.
          checkInAudience: checkIn.audience || null,
          audienceListId: checkIn.audienceListId || null
        }
      );
    }
    
    // Send real-time updates
    sseService.notifyUser(userId, 'check_in_created', serializeDoc(checkInDoc));
    
    res.status(201).json({
      success: true,
      data: { ...serializeDoc(checkInDoc), placeId: checkIn.placeId, globalPlaceId: checkIn.globalPlaceId || null },
      myCheckInStats,
      ratingApplied,
      postedCommentId,
      piggyBank
    });
  } catch (error) {
    console.error('Error creating check-in:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create check-in',
      error: error.message
    });
  }
};

// Get active check-ins visible to user
exports.getActiveCheckIns = async (req, res) => {
  try {
    const userId = req.user.uid;
    const now = new Date();
    
    // Get active check-ins from connections
    const checkInsQuery = await db.collection(COLLECTIONS.CHECK_INS)
      .where('active', '==', true)
      .where('endTime', '>', now.toISOString())
      .orderBy('endTime')
      .orderBy('createdAt', 'desc')
      .get();
    
    // Filter check-ins based on visibility (owner / notified / group /
    // connection-with-feed; private check-ins are owner-only) and the
    // owner's activity grid
    res.json({
      success: true,
      data: await visibleCheckIns(checkInsQuery.docs, userId)
    });
  } catch (error) {
    console.error('Error getting active check-ins:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get active check-ins',
      error: error.message
    });
  }
};

// The Check In screen's header: your numbers + who's out now
exports.getMySummary = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { summarize, friendsOut } = require('../services/checkInSummary');
    const now = new Date();
    // Who's out is a bonus: if it can't be read, your own numbers still show
    const outNow = async () => {
      try {
        const active = await db.collection(COLLECTIONS.CHECK_INS)
          .where('active', '==', true)
          .where('endTime', '>', now.toISOString())
          .orderBy('endTime')
          .orderBy('createdAt', 'desc')
          .get();
        return await visibleCheckIns(active.docs, userId);
      } catch (error) {
        console.error('Check-in summary: friends out unavailable:', error.message);
        return [];
      }
    };
    const [mine, visible] = await Promise.all([
      db.collection(COLLECTIONS.CHECK_INS).where('userId', '==', userId)
        .select('startTime', 'createdAt', 'placeId', 'globalPlaceId', 'placeName').get(),
      outNow()
    ]);
    res.json({
      success: true,
      data: {
        ...summarize(mine.docs.map((d) => d.data()), now.getTime()),
        friendsOut: friendsOut(visible, userId)
      }
    });
  } catch (error) {
    console.error('Error getting check-in summary:', error);
    res.status(500).json({ success: false, message: 'Failed to get check-in summary' });
  }
};

// Get user's own active check-ins
exports.getMyActiveCheckIns = async (req, res) => {
  try {
    const userId = req.user.uid;
    const now = new Date();
    
    const checkInsQuery = await db.collection(COLLECTIONS.CHECK_INS)
      .where('userId', '==', userId)
      .where('active', '==', true)
      .where('endTime', '>', now.toISOString())
      .orderBy('endTime')
      .orderBy('createdAt', 'desc')
      .get();
    
    const checkIns = serializeQuerySnapshot(checkInsQuery);
    
    res.json({
      success: true,
      data: checkIns
    });
  } catch (error) {
    console.error('Error getting my check-ins:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get check-ins',
      error: error.message
    });
  }
};

// Respond to a check-in (interested/going)
exports.respondToCheckIn = async (req, res) => {
  try {
    const userId = req.user.uid;
    const checkInId = req.params.checkInId;
    const { status } = req.body; // 'interested' or 'going'
    
    if (!['interested', 'going'].includes(status)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid status. Must be "interested" or "going"'
      });
    }
    
    const checkInRef = db.collection(COLLECTIONS.CHECK_INS).doc(checkInId);
    const checkInDoc = await checkInRef.get();
    
    if (!checkInDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Check-in not found'
      });
    }
    
    const checkIn = checkInDoc.data();
    
    // Verify check-in is still active
    if (!checkIn.active || new Date(checkIn.endTime) < new Date()) {
      return res.status(400).json({
        success: false,
        message: 'Check-in has ended'
      });
    }
    
    // Get user data
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userData = userDoc.data();
    
    // Update responses array
    const responses = checkIn.responses || [];
    const existingIndex = responses.findIndex(r => r.userId === userId);
    
    const responseData = {
      userId: userId,
      userName: userData.displayName || userData.firstName || 'User',
      userPhoto: userData.profilePicture || null,
      status: status,
      timestamp: new Date().toISOString()
    };
    
    if (existingIndex >= 0) {
      responses[existingIndex] = responseData;
    } else {
      responses.push(responseData);
    }
    
    await checkInRef.update({
      responses: responses,
      updatedAt: new Date().toISOString()
    });
    
    // Notify check-in owner
    if (checkIn.userId !== userId) {
      await notificationService.sendToUser(checkIn.userId, {
        type: 'check_in_response',
        title: 'Check-in Response',
        body: `${userData.displayName} is ${status === 'going' ? 'going to' : 'interested in'} ${checkIn.placeName}`,
        data: {
          checkInId: checkInId,
          responderId: userId,
          status: status,
          // iOS routes on placeId — the tap did nothing without it
          placeId: checkIn.placeId || null
        }
      });
    }
    
    // Send real-time updates
    sseService.notifyUser(checkIn.userId, 'check_in_response', responseData);
    
    const updatedDoc = await checkInRef.get();
    
    res.json({
      success: true,
      data: serializeDoc(updatedDoc)
    });
  } catch (error) {
    console.error('Error responding to check-in:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to respond to check-in',
      error: error.message
    });
  }
};

// End check-in early
exports.endCheckIn = async (req, res) => {
  try {
    const userId = req.user.uid;
    const checkInId = req.params.checkInId;
    
    const checkInRef = db.collection(COLLECTIONS.CHECK_INS).doc(checkInId);
    const checkInDoc = await checkInRef.get();
    
    if (!checkInDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Check-in not found'
      });
    }
    
    const checkIn = checkInDoc.data();
    
    // Verify ownership
    if (checkIn.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized to end this check-in'
      });
    }
    
    // Update check-in
    await checkInRef.update({
      active: false,
      endTime: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    
    // Send real-time updates
    sseService.notifyUser(userId, 'check_in_ended', { checkInId: checkInId });
    
    res.json({
      success: true,
      message: 'Check-in ended successfully'
    });
  } catch (error) {
    console.error('Error ending check-in:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to end check-in',
      error: error.message
    });
  }
};

// Get check-ins at a specific place
exports.getCheckInsAtPlace = async (req, res) => {
  try {
    const placeId = req.params.placeId;
    const userId = req.user.uid;
    const now = new Date();
    
    const checkInsQuery = await db.collection(COLLECTIONS.CHECK_INS)
      .where('placeId', '==', placeId)
      .where('active', '==', true)
      .where('endTime', '>', now.toISOString())
      .orderBy('endTime')
      .orderBy('createdAt', 'desc')
      .get();
    
    // Same visibility rule as the active feed — this used to return every
    // check-in at the place to any signed-in user
    const checkIns = await visibleCheckIns(checkInsQuery.docs, userId);
    
    res.json({
      success: true,
      data: checkIns,
      count: checkIns.length
    });
  } catch (error) {
    console.error('Error getting check-ins at place:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get check-ins at place',
      error: error.message
    });
  }
};

// Accepted connections of a user (both directions), plus the user
async function acceptedConnectionIds(userId) {
  const [connections1, connections2] = await Promise.all([
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted')
      .get(),
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted')
      .get()
  ]);
  const connectionIds = new Set([userId]); // Include self
  connections1.docs.forEach(doc => connectionIds.add(doc.data().connectedUserId));
  connections2.docs.forEach(doc => connectionIds.add(doc.data().userId));
  return connectionIds;
}

// Helper function to check if user is in any of the notified groups
async function isUserInAnyGroup(userId, groupIds) {
  if (!groupIds || groupIds.length === 0) return false;
  
  for (const groupId of groupIds) {
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(groupId).get();
    if (conversationDoc.exists) {
      const conversation = conversationDoc.data();
      if (conversation.participants && conversation.participants.includes(userId)) {
        return true;
      }
    }
  }
  
  return false;
}

// Clean up expired check-ins (to be called by a cron job)
exports.cleanupExpiredCheckIns = async (req, res) => {
  try {
    const now = new Date();
    
    const expiredQuery = await db.collection(COLLECTIONS.CHECK_INS)
      .where('active', '==', true)
      .where('endTime', '<=', now.toISOString())
      .get();
    
    const batch = db.batch();
    let count = 0;
    
    expiredQuery.docs.forEach(doc => {
      batch.update(doc.ref, {
        active: false,
        updatedAt: now.toISOString()
      });
      count++;
    });
    
    if (count > 0) {
      await batch.commit();
    }
    
    res.json({
      success: true,
      message: `Cleaned up ${count} expired check-ins`
    });
  } catch (error) {
    console.error('Error cleaning up check-ins:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to cleanup check-ins',
      error: error.message
    });
  }
};