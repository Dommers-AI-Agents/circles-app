// backend/services/placeSaveService.js
//
// Saving a place: the one path behind Add Place (POST /api/places) and every
// other surface that puts a place in a circle (Dog spots in Can I Pet Dat Dog).
// Moved verbatim from placeController.createPlace (2026-10-23) so a widget's
// save gets the same duplicate checks (any of your circles), Google details,
// venue link, photos, FavCoins, activity and pushes as the app's own.
//
// savePlace(user, body) never answers HTTP itself. It resolves to
// { status, payload, afterResponse? }: send `payload` with `status`, then
// await `afterResponse` (activity and notifications run after the reply).
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, createPlace, validatePlace, serializeDoc } = require('../models/FirestoreModels');
const { Client } = require('@googlemaps/google-maps-services-js');
const geofire = require('geofire-common');
const { isSameUser } = require('./idService');
const { ensureGlobalPlaceLink } = require('./globalPlaceResolver');
const { ensureCircleCoverImage } = require('./circleCover');
const { indexSavedPlace } = require('./circleLocationSummary');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { googleMapsApiKey } = require('../config/config');
const notificationService = require('./notificationService');
const { trackPlaceAdded } = require('./activityService');
const placeCache = require('./placeCache');
const requestDeduplicator = require('./requestDeduplicator');
const subscriptionLimitService = require('./subscriptionLimitService');
const rewardService = require('./rewardService');
const piggyBankService = require('./piggyBankService');
const { VENUE_GOOGLE_FIELDS } = require('./placeReadService');
const { circleAudience, narrowedByPlace } = require('./activity/audience');
const homePromptService = require('./homePromptService');

const db = getFirestore();
const googleMapsClient = new Client({});

const reply = (status, payload, afterResponse) => ({ status, payload, afterResponse });

// A verified store owner (approved ownership claim → stickerVenues.ownerUserId)
// — or a manager the owner invited (managerUserIds) — edits their venue's
// Google-backed fields like a super-user does.
const isVerifiedVenueOwner = async (uid, placeId, googlePlaceId) => {
  try {
    const venue = await rewardService.findVenueByPlace(placeId || googlePlaceId, googlePlaceId);
    if (!venue) return false;
    if (venue.ownerUserId && isSameUser(venue.ownerUserId, uid)) return true;
    return (venue.managerUserIds || []).some((id) => isSameUser(id, uid));
  } catch (error) {
    console.error('⚠️ Venue-owner check failed:', error.message);
    return false;
  }
};

// Google-backed saves arrive with client-authored venue fields. Re-anchor them
// server-side so a tampered Add Place request can't seed or shadow the
// canonical venue record: the existing globalPlaces record wins; a first save
// (which will seed that record) is verified against Google Places directly.
// Mutates placeData. Category stays client-supplied on the Google path — the
// Google-types → app-category mapping lives client-side.
const { isAddressOnly, isStreetLineName } = require('./googleAddressGuard');

const anchorVenueFieldsToSource = async (placeData) => {
  const googlePlaceId = placeData.googlePlaceId;

  const applyLocation = (coordinates) => {
    if (Array.isArray(coordinates) && coordinates.length === 2 &&
        typeof coordinates[0] === 'number' && typeof coordinates[1] === 'number') {
      placeData.location = { type: 'Point', coordinates: [coordinates[0], coordinates[1]] };
      placeData.geohash = geofire.geohashForLocation([coordinates[1], coordinates[0]]);
    }
  };

  const canonicalHit = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
    .where('googlePlaceId', '==', googlePlaceId)
    .limit(1)
    .get();
  if (!canonicalHit.empty) {
    const canonical = canonicalHit.docs[0].data();
    // A venue named only by its street address isn't the business being
    // saved: keep the client's name and drop the address's Google id
    if (isStreetLineName(canonical.name, canonical.address) && placeData.name
        && !isStreetLineName(placeData.name, placeData.address || canonical.address)) {
      console.log(`🏠 ${googlePlaceId} is an address venue ("${canonical.name}"); keeping "${placeData.name}" unlinked`);
      placeData.googlePlaceId = null;
      return;
    }
    ['name', 'address', 'category', 'subcategory'].forEach((field) => {
      if (canonical[field] !== undefined && canonical[field] !== null && canonical[field] !== '') {
        // A canonical still at 'other' has nothing to anchor: keep the
        // client's real category (ensureGlobalPlaceLink then upgrades the
        // venue to it via categoryUpgradeForOther, source 'client')
        if (field === 'category' && canonical.category === 'other') return;
        placeData[field] = canonical[field];
      }
    });
    applyLocation(canonical.location?.coordinates);
    const googleData = canonical.googleData || {};
    VENUE_GOOGLE_FIELDS.forEach((field) => {
      if (googleData[field] !== undefined && googleData[field] !== null && googleData[field] !== '') {
        placeData[field] = googleData[field];
      }
    });
    console.log(`🔒 Venue fields anchored to canonical record for ${googlePlaceId}`);
    return;
  }

  if (!googleMapsApiKey) return;
  try {
    // Own cache namespace: refreshPlace caches a narrower field set under
    // 'placeDetails' and must not satisfy this lookup
    let details = placeCache.get('placeDetailsFull', googlePlaceId);
    if (!details) {
      details = await requestDeduplicator.execute(`placeDetailsFull_${googlePlaceId}`, async () => {
        const cached = placeCache.get('placeDetailsFull', googlePlaceId);
        if (cached) return cached;
        const response = await googleMapsClient.placeDetails({
          params: {
            place_id: googlePlaceId,
            // Every field the groups this call already pays for return
            // (services/googlePlaceFields): types, serves_*, status … at no
            // extra cost
            fields: require('./googlePlaceFields').DETAILS_ALL,
            key: googleMapsApiKey
          }
        });
        placeCache.set('placeDetailsFull', googlePlaceId, response.data.result);
        return response.data.result;
      });
    }
    if (!details) return;

    // Google matched an ADDRESS, not the business (2026-10-23: "Uptown Yolk
    // Cafe" saved as "116 W Catherine St"). Keep what the user picked and
    // don't link the venue to the address's id.
    if (isAddressOnly(details.types)) {
      console.log(`🏠 ${googlePlaceId} is an address ("${details.name}"), not "${placeData.name}"; not linking it`);
      placeData.googlePlaceId = null;
      return;
    }

    if (details.name) placeData.name = details.name;
    if (details.formatted_address) placeData.address = details.formatted_address;
    const loc = details.geometry?.location;
    if (loc) applyLocation([loc.lng, loc.lat]);
    placeData.website = details.website || null;
    placeData.phone = details.formatted_phone_number || null;
    placeData.rating = details.rating ?? null;
    placeData.userRatingsTotal = details.user_ratings_total ?? null;
    placeData.priceLevel = details.price_level ?? null;
    // ?? not || — false is a real answer ("does not deliver"), null = unknown
    placeData.delivery = details.delivery ?? null;
    placeData.dineIn = details.dine_in ?? null;
    placeData.reservable = details.reservable ?? null;
    placeData.takeout = details.takeout ?? null;
    placeData.curbsidePickup = details.curbside_pickup ?? null;
    // Types and the rest of the free signals: the venue's category comes
    // from these, not from the phone's guess (globalPlaceResolver)
    const signals = require('./googlePlaceFields').googleSignals(details);
    placeData.googleTypes = signals.googleTypes;
    placeData.googleSignals = signals;
    // Google's editorial summary replaces whatever the client synthesized —
    // old app builds still send placeholder text ("A dining establishment in …")
    if (details.editorial_summary?.overview) {
      placeData.description = details.editorial_summary.overview;
      placeData.descriptionSource = 'google_editorial';
    }
    console.log(`🔒 Venue fields verified against Google Places for new venue ${googlePlaceId}`);
  } catch (error) {
    // Availability over strictness: a Google outage shouldn't block saves
    console.warn(`⚠️ Could not verify venue fields with Google for ${googlePlaceId}: ${error.message}`);
  }
};

/** Saves `body` (the POST /api/places body) as `user`'s place. */
async function savePlace(user, body) {
    const { circleId } = body;

    if (!circleId) {
      return reply(400, {
        success: false,
        message: 'Circle ID is required'
      });
    }

    // Verify circle exists and user has permission
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return reply(404, {
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    // Check if user can add places (owner or shared with)
    const isOwner = circle.owner === user.uid;
    const isSharedWith = circle.sharedWith.includes(user.uid);
    
    if (!isOwner && !isSharedWith) {
      return reply(403, {
        success: false,
        message: 'Not authorized to add places to this circle'
      });
    }

    // Check subscription limits for the circle owner (not the current user if they're just shared with)
    const limitCheck = await subscriptionLimitService.canAddPlace(circle.owner, circleId);
    if (!limitCheck.canAdd) {
      return reply(403, {
        success: false,
        message: limitCheck.error,
        upgradeRequired: true,
        currentCount: limitCheck.currentCount,
        maxAllowed: limitCheck.maxAllowed
      });
    }

    // Validate place data
    const validationErrors = validatePlace(body);
    if (validationErrors.length > 0) {
      return reply(400, {
        success: false,
        message: 'Validation error',
        errors: validationErrors
      });
    }

    // Check for duplicates before creating (excluding soft-deleted places)
    // Skip duplicate check if force flag is set (user selected "Add Anyway")
    const { googlePlaceId, name, address, force } = body;

    // The same save sent twice (the phone kept it on a weak signal and
    // resent it, but the first attempt had got through): one place, never
    // two. Checked before `force`, which a resend carries too.
    const clientSaveId = typeof body.clientSaveId === 'string' ? body.clientSaveId.slice(0, 64) : null;
    if (clientSaveId) {
      const again = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', user.uid)
        .where('clientSaveId', '==', clientSaveId)
        .limit(1)
        .get();
      if (!again.empty) {
        return reply(400, {
          success: false,
          code: 'DUPLICATE_PLACE',
          existingPlaceId: again.docs[0].id,
          existingPlaceName: again.docs[0].data().name || name || null,
          existingCircleId: again.docs[0].data().circleId || null,
          existingCircleName: null,
          message: 'Already saved'
        });
      }
    }
    
    if (!force) {
      if (googlePlaceId) {
        const existingPlace = await db.collection(COLLECTIONS.PLACES)
          .where('circleId', '==', circleId)
          .where('googlePlaceId', '==', googlePlaceId)
          .where('deletedAt', '==', null)
          .get();
          
        if (!existingPlace.empty) {
          return reply(400, {
            success: false,
            code: 'DUPLICATE_PLACE',
            existingPlaceId: existingPlace.docs[0].id,
            message: 'This place already exists in the selected circle'
          });
        }
      } else if (name && address) {
        // For custom places without googlePlaceId
        const existingPlace = await db.collection(COLLECTIONS.PLACES)
          .where('circleId', '==', circleId)
          .where('name', '==', name)
          .where('address', '==', address)
          .where('deletedAt', '==', null)
          .get();

        if (!existingPlace.empty) {
          return reply(400, {
            success: false,
            code: 'DUPLICATE_PLACE',
            existingPlaceId: existingPlace.docs[0].id,
            message: 'This place already exists in the selected circle'
          });
        }
      }
      // The same venue in ANY of the user's circles: one lookup here instead
      // of the app downloading every circle's places before saving (the
      // weak-signal hang, Wes 2026-10-04). The app offers View / Add Anyway.
      const { findOwnSaveForNewPlace } = require('./ownSaveOfVenue');
      const existing = await findOwnSaveForNewPlace({
        userId: user.uid, googlePlaceId, name, location: body.location
      });
      if (existing) {
        const existingData = existing.data();
        const existingCircle = existingData.circleId
          ? await db.collection(COLLECTIONS.CIRCLES).doc(existingData.circleId).get()
          : null;
        return reply(400, {
          success: false,
          code: 'DUPLICATE_PLACE',
          existingPlaceId: existing.id,
          existingPlaceName: existingData.name || name || null,
          existingCircleId: existingData.circleId || null,
          existingCircleName: existingCircle && existingCircle.exists ? (existingCircle.data().name || null) : null,
          message: existingCircle && existingCircle.exists
            ? `You already have ${existingData.name || 'this place'} in ${existingCircle.data().name}`
            : 'You already saved this place'
        });
      }
    } else {
      console.log('⚠️ Duplicate check bypassed with force flag for place:', { name, address, googlePlaceId });
    }

    // Create place data
    const placeData = createPlace(body, circleId, user.uid);
    if (clientSaveId) placeData.clientSaveId = clientSaveId;

    // Which of the photos are the saver's OWN. `photos` is a mixed bag by the
    // time it arrives — the phone folds Google's stock photo and an Apple Look
    // Around still in with anything the user picked, and once they are all
    // plain URLs in one array nothing downstream can tell them apart. The app
    // names its own uploads separately, and only the add-place screen does, so
    // this is the one trustworthy signal. Recorded on the save for the home
    // daily card to read later.
    const ownPhotoUrls = Array.isArray(body.ownPhotoUrls)
      ? body.ownPhotoUrls.filter(url => typeof url === 'string' && url.length > 0)
      : [];
    const hasOwnPhotos = ownPhotoUrls.length > 0;
    if (hasOwnPhotos) {
      placeData.hasOwnPhotos = true;
      placeData.ownPhotoUrl = ownPhotoUrls[0];
    }

    // Share-extension saves arrive bare (name/address/coords) with
    // enrichFromGoogle set — the extension can't run the Places SDK. Mirror
    // the check-in pattern exactly: canonical venue first (zero Google spend
    // when anyone on the platform already saved this venue), Google
    // enrichment only for venues new to the whole platform. Failure leaves a
    // bare-but-valid save — availability over completeness.
    if (body.enrichFromGoogle === true && !placeData.googlePlaceId) {
      await require('./googleEnrichment').enrichSaveFromGoogle(placeData);
    }

    // Second duplicate gate, post-enrichment: a share-extension save arrives
    // without googlePlaceId, so the name+address check above misses the same
    // venue saved earlier under a differently-formatted address. Now that
    // enrichment resolved the venue identity, re-check the circle by it.
    if (!force && !googlePlaceId && placeData.googlePlaceId) {
      const dupSnap = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('googlePlaceId', '==', placeData.googlePlaceId)
        .where('deletedAt', '==', null)
        .get();
      if (!dupSnap.empty) {
        return reply(400, {
          success: false,
          code: 'DUPLICATE_PLACE',
          existingPlaceId: dupSnap.docs[0].id,
          message: 'This place already exists in the selected circle'
        });
      }
    }

    // Google-backed saves: venue fields are locked to their source at creation
    // too, mirroring the updatePlace lock. Super-users and the venue's
    // verified owner keep their submitted values.
    if (placeData.googlePlaceId) {
      const exempt = user.isSuperUser === true
        || await isVerifiedVenueOwner(user.uid, null, placeData.googlePlaceId);
      if (!exempt) {
        await anchorVenueFieldsToSource(placeData);
      }
    }

    // Validate photos - reject Google Places API URLs
    if (placeData.photos && placeData.photos.length > 0) {
      const invalidPhotos = placeData.photos.filter(photo => 
        photo.includes('maps.googleapis.com') || 
        photo.includes('photoreference=')
      );
      
      if (invalidPhotos.length > 0) {
        console.error('❌ Rejected place creation with Google Places API URLs:', invalidPhotos);
        return reply(400, {
          success: false,
          message: 'Invalid photo URLs detected. Photos must be uploaded to Firebase Storage, not Google Places API URLs.',
          invalidUrls: invalidPhotos
        });
      }
    }
    
    // If location is missing but address is provided, try to geocode it
    if (!placeData.location && placeData.address && googleMapsApiKey) {
      console.log('🗺️ Place missing location, attempting to geocode address:', placeData.address);
      try {
        // Check cache first
        let geocodeResult = placeCache.get('geocoding', placeData.address);
        
        if (!geocodeResult) {
          // Use deduplicator to prevent concurrent identical geocoding requests
          const requestKey = requestDeduplicator.generateGeocodeKey(placeData.address);
          
          geocodeResult = await requestDeduplicator.execute(requestKey, async () => {
            // Double-check cache in case another request just completed
            const cachedResult = placeCache.get('geocoding', placeData.address);
            if (cachedResult) {
              return cachedResult;
            }
            
            const geocodeResponse = await googleMapsClient.geocode({
              params: {
                address: placeData.address,
                key: googleMapsApiKey
              }
            });
            
            if (geocodeResponse.data.results && geocodeResponse.data.results.length > 0) {
              const result = geocodeResponse.data.results[0];
              // Cache the geocoding result with 1-year TTL (addresses rarely change)
              placeCache.set('geocoding', placeData.address, result, 365 * 24 * 60 * 60 * 1000);
              return result;
            }
            
            return null;
          });
        }
        
        if (geocodeResult) {
          const { lat, lng } = geocodeResult.geometry.location;
          
          // Validate coordinates
          if (typeof lng === 'number' && typeof lat === 'number' &&
              lng >= -180 && lng <= 180 &&
              lat >= -90 && lat <= 90 &&
              !(lng === -180 && lat === -180)) {
            placeData.location = {
              type: 'Point',
              coordinates: [lng, lat]
            };
            console.log('✅ Successfully geocoded address to:', { lat, lng });
          } else {
            console.warn('⚠️ Invalid coordinates from geocoding:', { lat, lng });
          }
        } else {
          console.warn('⚠️ No geocoding results for address:', placeData.address);
        }
      } catch (error) {
        console.warn('⚠️ Geocoding failed:', error.message);
        // Continue without location - not a fatal error
      }
    }
    
    // Log place creation for debugging
    console.log('🆕 Creating new place:', {
      name: placeData.name,
      circleId: circleId,
      addedBy: user.uid,
      hasLocation: !!placeData.location,
      notes: {
        notes: placeData.notes ? `${placeData.notes.substring(0, 50)}...` : 'empty',
        publicNotes: placeData.publicNotes ? `${placeData.publicNotes.substring(0, 50)}...` : 'empty',
        privateNotes: placeData.privateNotes ? `${placeData.privateNotes.substring(0, 50)}...` : 'empty'
      },
      category: placeData.category,
      googlePlaceId: placeData.googlePlaceId || 'none'
    });
    
    // Add to Firestore
    const placeRef = await db.collection(COLLECTIONS.PLACES).add(placeData);

    // Get the created place with ID
    const createdPlace = await placeRef.get();
    const place = serializeDoc(createdPlace);

    // Link the save to its canonical venue record (resolve-or-create)
    const globalPlaceId = await ensureGlobalPlaceLink(createdPlace);
    if (globalPlaceId) {
      place.globalPlaceId = globalPlaceId;
      // The link stamps the venue's category onto the save (derived from the
      // name/POI signals when the client sent 'other') — return what the map
      // pin will actually show rather than the pre-link doc.
      try {
        const linkedCategory = (await placeRef.get()).get('category');
        if (linkedCategory) place.category = linkedCategory;
      } catch (e) { /* response falls back to the pre-link category */ }
      // One photo library per place: this save's photos join it (own
      // uploads attributed, stock photos only fill an empty library)
      await require('./placePhotoService').adoptSavePhotos({
        globalPlaceId,
        user: user,
        photos: placeData.photos || [],
        ownUrls: ownPhotoUrls,
        isPrivate: require('./placePhotoService').effectivelyPrivate(placeData.privacy, circle && circle.privacy)
      });
      // Saved without a photo (the app no longer waits on Look Around or
      // Google before saving): if the place still has none anywhere, the
      // app's background pass adds a free Look Around snapshot later.
      if (!(placeData.photos || []).length) {
        try {
          const venue = await db.collection('globalPlaces').doc(globalPlaceId).get();
          if (!venue.exists || !require('./placePhotoService').hasVisiblePhotos(venue.data().photos)) {
            await placeRef.update({ needsPhoto: true });
          }
        } catch (e) { /* best-effort: the place is saved either way */ }
      }
    }

    // Keep the browse location tree fresh: bump this circle's summary and drop
    // the adder's cached tree (best-effort; rebuild job corrects any drift).
    indexSavedPlace(circleId, placeData);
    placeCache.clear('browseTree', user.uid);

    // Update circle's places array and increment count (only add if place.id is defined)
    const currentPlaces = circle.places || [];
    if (place.id) {
      await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update({
        places: [place.id, ...currentPlaces], // Add new place at the beginning
        placesCount: (circle.placesCount || 0) + 1, // Increment places count
        updatedAt: new Date().toISOString()
      });
      // Default cover: a circle with no cover takes its first place photo
      if (!circle.coverImage && Array.isArray(place.photos) && place.photos.length > 0) {
        ensureCircleCoverImage(circleId, place.photos[0]);
      }
    }

    // Gamification: the user's live place count rides along so the client can
    // trigger milestone celebrations (5, 10, 20, ... places)
    let totalPlaces = null;
    try {
      const countSnap = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', user.uid)
        .where('deletedAt', '==', null)
        .count()
        .get();
      totalPlaces = countSnap.data().count;
    } catch (countError) {
      console.error('⚠️ Milestone place count failed (non-fatal):', countError.message);
    }

    // Piggy bank: FavCoins for the add. AWAITED (uniquely among the hooks —
    // one count query + one transaction, cheap) so the deposit animation can
    // ride the create response. credit() never throws; a credit failure just
    // yields { credited: false } and the add still succeeds.
    //
    // venueKey backs up globalPlaceId in the dedup key: if venue linking
    // failed, the canonical google:/manual: identity still blocks re-adding
    // the same venue from ever paying twice.
    let piggyVenueKey = null;
    try {
      const { generatePlaceKey } = require('../models/GlobalPlace');
      piggyVenueKey = generatePlaceKey(place);
    } catch (keyError) { /* malformed name/address — placeId last resort */ }

    // Funnel: first place they added themselves (fire-and-forget)
    require('./funnelService').stampFunnelMilestone(user.uid, 'firstPlaceAt');

    const piggyBank = await piggyBankService.credit({
      userId: user.uid,
      eventType: 'add_place',
      sourceRef: {
        placeId: placeRef.id,
        globalPlaceId: globalPlaceId || null,
        venueKey: piggyVenueKey,
        circleId
      }
    });

    // Welcome gift: 25 FavCoins the first time a user ever adds a place
    // (promised by the App Clip's generic signup). The onboarding SAMPLE
    // place counts toward totalPlaces, which used to make the gate
    // (totalPlaces === 1) unreachable for anyone who got a seeded sample —
    // their real first add arrived as place #2 and the gift never fired.
    // Exclude sample places from the gate count; the first_place:{uid}
    // dedup key keeps the looser gate once-ever. Awaited and merged into
    // the response so the client animates the full 25+3 drop together.
    let welcomeGift = null;
    if (totalPlaces !== null && totalPlaces <= 2) {
      try {
        // deletedAt filter keeps this consistent with the totalPlaces count
        // (a deleted sample must not subtract from live places)
        const sampleSnap = await db.collection(COLLECTIONS.PLACES)
          .where('addedBy', '==', user.uid)
          .where('isSamplePlace', '==', true)
          .where('deletedAt', '==', null)
          .count()
          .get();
        const realPlaces = totalPlaces - sampleSnap.data().count;
        if (realPlaces === 1) {
          welcomeGift = await piggyBankService.credit({
            userId: user.uid,
            eventType: 'first_place_added',
            sourceRef: { placeId: placeRef.id }
          });
        }
      } catch (giftError) {
        console.error('⚠️ Welcome gift check failed (non-fatal):', giftError.message);
      }
    }

    // Weekly engagement bonus: first qualifying place action of the ISO week.
    // Awaited (one doc-ID create attempt; duplicates bail instantly) so it can
    // ride the same deposit animation as the add itself.
    const weeklyBonus = await piggyBankService.credit({
      userId: user.uid,
      eventType: 'weekly_goal',
      sourceRef: { placeId: placeRef.id }
    });

    // One combined deposit for the animation: add_place + welcome gift + weekly
    // bonus. eventType prefers the rarest credited part so the client's label
    // matches the biggest reason for the drop.
    const creditedParts = [piggyBank, welcomeGift, weeklyBonus].filter(p => p && p.credited);
    const combinedPiggyBank = creditedParts.length
      ? {
          credited: true,
          coins: creditedParts.reduce((sum, p) => sum + p.coins, 0),
          eventType: (welcomeGift && welcomeGift.credited) ? 'first_place_added'
            : (piggyBank && piggyBank.credited) ? 'add_place'
            : 'weekly_goal'
        }
      : piggyBank;

    // Postcard: the app offers "send a postcard from here?" after a save, but
    // only when the user attached a photo of their OWN. A POI save comes back
    // carrying Google's stock photos, and nobody mails a postcard of a stock
    // photo — `body.photos` is what the phone uploaded, so it is the only
    // honest signal. Checking eligibility only in that case also keeps the
    // ordinary save at exactly the cost it had. The fortnightly cooldown is
    // shared with the home daily card, so the two never both ask.
    let postcardNudge = null;
    if (hasOwnPhotos) {
      try {
        postcardNudge = { eligible: await homePromptService.postcardNudgeEligible(user.uid) };
      } catch (nudgeError) {
        console.error('⚠️ Postcard nudge check failed (non-fatal):', nudgeError.message);
      }
    }

    // Add commentsCount to the response (new places have 0 comments)
    const created = {
      success: true,
      totalPlaces,
      postcardNudge,
      piggyBank: combinedPiggyBank,
      place: {
        ...place,
        commentsCount: 0
      }
    };

    // The caller answers first; this runs after (activity, credits, pushes)
    return reply(201, created, async () => {

      // Track activity for network connections — but a Private place is
      // owner-only, so it must not broadcast a "added a place" activity
      if (place.privacy !== 'private') {
        await trackPlaceAdded(placeRef.id, circleId, place.name, circle.name, user.uid);
      }

      // If this add came from a shared place link, credit the sharer. (Store
      // points retired here 2026-08-10 — share conversions aren't tied to a
      // shop, so under per-store loyalty the sharer earns FavCoins only.)
      if (body.refUserId) {
        // Piggy bank: place_adopted — the quality-aligned flagship earn. The
        // SHARER gets the coins; fire-and-forget.
        piggyBankService.credit({
          userId: body.refUserId,
          eventType: 'place_adopted',
          sourceRef: {
            globalPlaceId: place.globalPlaceId || null,
            googlePlaceId: place.googlePlaceId || null,
            adderUserId: user.uid,
            adderPlaceId: placeRef.id
          }
        }).catch(() => {});
      }

      // Send notifications to interested users
      try {
        // Get users who should be notified
        const notifyUserIds = new Set();
      
        // Who this circle's contents may be announced to. Same resolver the
        // activity fan-out uses, narrowed by the place's own tier — a push is a
        // point-in-time event that can't be taken back, so it is decided here
        // rather than left to a read gate.
        const audience = await narrowedByPlace(
          await circleAudience(circle, circle.owner, { category: 'savedPlaces' }),
          place,
          user.uid
        );

        if (audience.emits) {
          // People the circle was shared with directly
          circle.sharedWith.forEach(userId => {
            if (userId !== user.uid && audience.allows(userId)) {
              notifyUserIds.add(userId);
            }
          });

          // Add circle owner if not the one adding
          if (circle.owner !== user.uid) {
            notifyUserIds.add(circle.owner);
          }

          // Everyone else the tier admits
          const userDoc = await db.collection(COLLECTIONS.USERS).doc(user.uid).get();
          if (userDoc.exists) {
            const connections = userDoc.data().friends || [];
            connections.forEach(userId => {
              if (audience.allows(userId)) notifyUserIds.add(userId);
            });
          }
        }
      
        if (notifyUserIds.size > 0) {
          await notificationService.notifyNewPlace(
            place,
            circle,
            Array.from(notifyUserIds)
          );
        }
      } catch (notifError) {
        console.error('Error sending place notifications:', notifError);
        // Don't fail the request if notifications fail
      }
    });
}

module.exports = { savePlace, isVerifiedVenueOwner, anchorVenueFieldsToSource };
