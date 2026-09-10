// controllers/places/placeVenueMaintenanceController.js
// Venue upkeep: Google refresh, info flags, unresolved/photo-less imports, photo fallback, photo migration
// Split out of firebasePlaceController.js (handlers unchanged).
// backend/controllers/firebasePlaceController.js
const admin = require('firebase-admin');
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');
const { Client } = require('@googlemaps/google-maps-services-js');
const geofire = require('geofire-common');
const { isSameUser } = require('../../services/idService');
const { ensureGlobalPlaceLink } = require('../../services/globalPlaceResolver');
const { ensureCircleCoverImage } = require('../../services/circleCover');
const { indexSavedPlace } = require('../../services/circleLocationSummary');
const { GLOBAL_COLLECTIONS } = require('../../models/GlobalPlace');
const { googleMapsApiKey } = require('../../config/config');
const placeCache = require('../../services/placeCache');
const requestDeduplicator = require('../../services/requestDeduplicator');
const db = getFirestore();
const googleMapsClient = new Client({});
const { propagateVenueUpdates } = require('../../services/placeVenueSync.js');

// @desc    Refresh place data from Google Places API
// @route   POST /api/places/:id/refresh-google
// @access  Private (owner or circle member)
exports.refreshPlaceFromGoogle = async (req, res, next) => {
  try {
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Check permissions
    const isOwner = place.addedBy === req.user.uid;
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Associated circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    const isCircleMember = circle.owner === req.user.uid || 
                          (circle.sharedWith && circle.sharedWith.includes(req.user.uid));
    
    if (!isOwner && !isCircleMember) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to refresh this place'
      });
    }
    
    // Check if place was refreshed recently (within 30 days)
    if (place.lastRefreshedAt) {
      const lastRefresh = new Date(place.lastRefreshedAt);
      const thirtyDaysAgo = new Date();
      thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
      
      if (lastRefresh > thirtyDaysAgo) {
        const daysAgo = Math.floor((Date.now() - lastRefresh.getTime()) / (1000 * 60 * 60 * 24));
        console.log(`ℹ️ Place was refreshed ${daysAgo} days ago, skipping refresh to save API costs`);
        return res.status(200).json({
          success: true,
          message: `Place data is recent (updated ${daysAgo} days ago)`,
          place: place
        });
      }
    }
    
    // Check if Google Places API key is configured
    if (!googleMapsApiKey) {
      console.log('⚠️ Google Maps API key not configured, cannot refresh place details');
      return res.status(200).json({
        success: true,
        message: 'Place data is up to date',
        place: place
      });
    }
    
    let googlePlaceId = place.googlePlaceId;
    
    // If no googlePlaceId, try to find it using place name and location
    if (!googlePlaceId && place.location && place.name) {
      console.log('🔍 No Google Place ID found, searching by name and location...');
      
      try {
        // Search for the place using text search
        const searchResponse = await googleMapsClient.findPlaceFromText({
          params: {
            input: place.name,
            inputtype: 'textquery',
            fields: ['place_id', 'name', 'geometry'],
            locationbias: place.location ? `point:${place.location.coordinates[1]},${place.location.coordinates[0]}` : undefined,
            key: googleMapsApiKey
          }
        });
        
        if (searchResponse.data.candidates && searchResponse.data.candidates.length > 0) {
          // Find the best match based on distance
          let bestMatch = searchResponse.data.candidates[0];
          
          if (place.location && searchResponse.data.candidates.length > 1) {
            const placeCoords = place.location.coordinates;
            let minDistance = Infinity;
            
            for (const candidate of searchResponse.data.candidates) {
              if (candidate.geometry && candidate.geometry.location) {
                const distance = Math.sqrt(
                  Math.pow(candidate.geometry.location.lat - placeCoords[1], 2) +
                  Math.pow(candidate.geometry.location.lng - placeCoords[0], 2)
                );
                
                if (distance < minDistance) {
                  minDistance = distance;
                  bestMatch = candidate;
                }
              }
            }
          }
          
          googlePlaceId = bestMatch.place_id;
          console.log(`✅ Found matching Google Place: ${bestMatch.name} (ID: ${googlePlaceId})`);
          
          // Update the place with the found googlePlaceId
          await placeRef.update({ googlePlaceId });
        } else {
          console.log('⚠️ No matching Google Place found');
          return res.status(200).json({
            success: true,
            message: 'Could not find a matching Google Place for this location',
            place: place
          });
        }
      } catch (searchError) {
        console.error('❌ Error searching for Google Place:', searchError);
        return res.status(200).json({
          success: true,
          message: 'Could not search for Google Place details',
          place: place
        });
      }
    } else if (!googlePlaceId) {
      console.log('ℹ️ Cannot refresh: no Google Place ID and insufficient data to search');
      return res.status(200).json({
        success: true,
        message: 'This place does not have enough information to fetch Google details',
        place: place
      });
    }
    
    try {
      console.log('🔍 Refreshing place from Google Places API:', googlePlaceId);
      
      // Check cache first
      let googlePlace = placeCache.get('placeDetails', googlePlaceId);
      
      if (!googlePlace) {
        // Use deduplicator to prevent concurrent identical requests
        const requestKey = requestDeduplicator.generatePlaceKey(googlePlaceId);
        
        googlePlace = await requestDeduplicator.execute(requestKey, async () => {
          // Double-check cache in case another request just completed
          const cachedResult = placeCache.get('placeDetails', googlePlaceId);
          if (cachedResult) {
            return cachedResult;
          }
          
          // Fetch updated place details from Google
          const response = await googleMapsClient.placeDetails({
            params: {
              place_id: googlePlaceId,
              // rating/user_ratings_total already bill Atmosphere, so the
              // service-option booleans below ride the same SKU for free
              fields: ['name', 'rating', 'user_ratings_total', 'photos', 'formatted_address', 'formatted_phone_number', 'website', 'opening_hours',
                       'delivery', 'dine_in', 'reservable', 'takeout', 'curbside_pickup'],
              key: googleMapsApiKey
            }
          });
          
          const result = response.data.result;
          
          // Cache the response
          placeCache.set('placeDetails', googlePlaceId, result);
          
          console.log('✅ Fetched place details from Google API:', {
            name: result.name,
            rating: result.rating,
            photosCount: result.photos?.length || 0
          });
          
          return result;
        });
      } else {
        console.log('✅ Using cached place details:', {
          name: googlePlace.name,
          rating: googlePlace.rating,
          photosCount: googlePlace.photos?.length || 0
        });
      }
      
      // Prepare update data
      const updateData = {
        lastRefreshedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };
      
      // Update rating if available
      if (googlePlace.rating !== undefined) {
        updateData.rating = googlePlace.rating;
      }
      
      if (googlePlace.user_ratings_total !== undefined) {
        updateData.userRatingsTotal = googlePlace.user_ratings_total;
      }

      // Service-option booleans (partner-chip eligibility); undefined = Google
      // doesn't know, so leave the stored value alone
      if (googlePlace.delivery !== undefined) updateData.delivery = googlePlace.delivery;
      if (googlePlace.dine_in !== undefined) updateData.dineIn = googlePlace.dine_in;
      if (googlePlace.reservable !== undefined) updateData.reservable = googlePlace.reservable;
      if (googlePlace.takeout !== undefined) updateData.takeout = googlePlace.takeout;
      if (googlePlace.curbside_pickup !== undefined) updateData.curbsidePickup = googlePlace.curbside_pickup;
      
      // Update photos if available (always refresh to get latest photos)
      if (googlePlace.photos && googlePlace.photos.length > 0) {
        // Get photo URLs (limit to 3 photos to avoid excessive API calls)
        const googlePhotoUrls = [];
        const photosToFetch = Math.min(3, googlePlace.photos.length);
        
        for (let i = 0; i < photosToFetch; i++) {
          const photo = googlePlace.photos[i];
          const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${photo.photo_reference}&key=${googleMapsApiKey}`;
          googlePhotoUrls.push(photoUrl);
        }
        
        if (googlePhotoUrls.length > 0) {
          // Download images from Google and upload to Firebase Storage
          const { downloadAndUploadMultipleImages } = require('../../services/storage');
          console.log(`📸 Downloading ${googlePhotoUrls.length} photos from Google Places...`);
          
          try {
            const { uploadedUrls, errors } = await downloadAndUploadMultipleImages(googlePhotoUrls);
            
            if (uploadedUrls.length > 0) {
              updateData.photos = uploadedUrls;
              console.log(`✅ Successfully uploaded ${uploadedUrls.length} photos to Firebase Storage`);
            }
            
            if (errors.length > 0) {
              console.error(`⚠️ Failed to upload ${errors.length} photos:`, errors);
            }
          } catch (error) {
            console.error('❌ Error processing Google Places photos:', error);
            // Don't update photos if download failed
          }
        }
      }
      
      // Update the place in Firestore
      await placeRef.update(updateData);

      // Fresh Google data (rating, review counts) is venue-level: push it to
      // the canonical record so every saver benefits (photos stay per-copy)
      await propagateVenueUpdates(req.params.id, place.globalPlaceId, updateData);

      // Get the updated place
      const updatedDoc = await placeRef.get();
      const updatedPlace = serializeDoc(updatedDoc);

      console.log('✅ Place refreshed successfully');
      
      res.status(200).json({
        success: true,
        message: 'Place updated with latest information',
        place: updatedPlace
      });
      
    } catch (googleError) {
      console.error('❌ Google Places API error:', googleError);
      
      // Return the existing place even if refresh fails
      res.status(200).json({
        success: false,
        message: 'Could not refresh place data at this time',
        place: place
      });
    }
    
  } catch (error) {
    console.error('Error refreshing place from Google:', error);
    next(error);
  }
};

// @desc    Update place address and optionally coordinates
// @route   PUT /api/places/:id/update-address
// @access  Private (owner or circle member)
// @desc    Flag a place whose information looks wrong. Venue fields are
//          read-only for users (Google Places is the source of truth), so
//          this is the correction path: the report is stored and the admin
//          is emailed to review it.
// @route   POST /api/places/:id/flag
// @access  Private
exports.flagPlaceInfo = async (req, res) => {
  try {
    const message = String(req.body?.message || '').trim();
    if (!message) {
      return res.status(400).json({
        success: false,
        message: 'Please describe what looks wrong'
      });
    }

    // The id can be a save doc or a global place id — surface whatever we find
    let placeName = null;
    let placeAddress = null;
    let globalPlaceId = null;
    let googlePlaceId = null;
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(req.params.id).get();
    if (placeDoc.exists) {
      const place = placeDoc.data();
      placeName = place.name;
      placeAddress = place.address;
      globalPlaceId = place.globalPlaceId || null;
      googlePlaceId = place.googlePlaceId || null;
    } else {
      const globalDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(req.params.id).get();
      if (!globalDoc.exists) {
        return res.status(404).json({ success: false, message: 'Place not found' });
      }
      const place = globalDoc.data();
      placeName = place.name;
      placeAddress = place.address;
      globalPlaceId = globalDoc.id;
      googlePlaceId = place.googlePlaceId || null;
    }

    const report = {
      type: 'place_info',
      reporterId: req.user.uid,
      reporterEmail: req.user.email || null,
      reporterName: req.user.displayName || null,
      placeId: req.params.id,
      globalPlaceId,
      googlePlaceId,
      placeName,
      placeAddress,
      message,
      status: 'pending',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    const reportRef = await db.collection(COLLECTIONS.REPORTS).add(report);

    // Notify the admin; a mail failure must not fail the report
    try {
      const emailService = require('../../services/emailService');
      const adminEmail = process.env.ADMIN_EMAIL || 'wesley@favcircles.com';
      await emailService.sendEmail({
        to: adminEmail,
        subject: `🚩 Place info flagged: ${placeName || req.params.id}`,
        text: [
          `A user flagged incorrect place information.`,
          ``,
          `Place: ${placeName || 'unknown'}`,
          `Address: ${placeAddress || 'unknown'}`,
          `Place ID: ${req.params.id}`,
          `Global place ID: ${globalPlaceId || 'none'}`,
          `Google place ID: ${googlePlaceId || 'none'}`,
          ``,
          `Reported by: ${report.reporterName || 'unknown'} (${report.reporterEmail || req.user.uid})`,
          `What's wrong: ${message}`,
          ``,
          `Report ID: ${reportRef.id}`
        ].join('\n'),
        html: `
          <h2>🚩 Place info flagged</h2>
          <p><strong>Place:</strong> ${placeName || 'unknown'}<br>
          <strong>Address:</strong> ${placeAddress || 'unknown'}<br>
          <strong>Place ID:</strong> ${req.params.id}<br>
          <strong>Global place ID:</strong> ${globalPlaceId || 'none'}<br>
          <strong>Google place ID:</strong> ${googlePlaceId || 'none'}</p>
          <p><strong>Reported by:</strong> ${report.reporterName || 'unknown'} (${report.reporterEmail || req.user.uid})</p>
          <p><strong>What's wrong:</strong><br>${message}</p>
          <p><em>Report ID: ${reportRef.id}</em></p>
        `
      });
    } catch (emailError) {
      console.error('⚠️ Flag-place admin email failed:', emailError.message);
    }

    res.status(201).json({
      success: true,
      data: { reportId: reportRef.id }
    });
  } catch (error) {
    console.error('❌ flagPlaceInfo failed:', error);
    res.status(500).json({ success: false, message: 'Failed to submit report' });
  }
};

// @desc    The caller's own places still awaiting on-device location
//          resolution (imported unmapped: needsResolution=true). Feeds the
//          iOS background resolution queue.
// @route   GET /api/places/unresolved
// @access  Private
exports.getUnresolvedPlaces = async (req, res) => {
  try {
    // Single-equality query + in-memory filter — no composite index needed,
    // and a user's own places are a small set
    const snapshot = await db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', req.user.uid)
      .get();
    const places = [];
    snapshot.forEach(doc => {
      const p = doc.data();
      if (p.deletedAt || !p.needsResolution) return;
      // Three failed passes = stop retrying (saved articles/products from
      // Takeout will never locate); they stay needsResolution for the
      // "couldn't be located" review UI, just out of the queue's feed.
      if ((p.resolutionAttempts || 0) >= 3) return;
      // website carries the original import source URL — the client decodes
      // the venue's true location from it (S2 feature id) so same-name
      // venues near the user can't win the Apple Maps lookup
      places.push({ id: doc.id, name: p.name, address: p.address || null, circleId: p.circleId, website: p.website || null });
    });
    res.json({ success: true, data: { places, count: places.length } });
  } catch (error) {
    console.error('❌ getUnresolvedPlaces failed:', error);
    res.status(500).json({ success: false, message: 'Failed to load unresolved places' });
  }
};

// @desc    Own IMPORTED places that still have no photo — the app fills in a
//          free on-device Apple Look Around snapshot for each (imports never
//          spend on Google photos). Two failed passes retire a row.
// @route   GET /api/places/needs-photo
// @access  Private
exports.getPlacesNeedingPhoto = async (req, res) => {
  try {
    const snapshot = await db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', req.user.uid)
      .get();
    const places = [];
    snapshot.forEach(doc => {
      const p = doc.data();
      if (p.deletedAt || !p.importSource) return;
      if (Array.isArray(p.photos) && p.photos.length > 0) return;
      if ((p.photoFallbackAttempts || 0) >= 2) return;
      const coords = p.location && p.location.coordinates;
      if (!Array.isArray(coords) || coords.length !== 2) return;
      places.push({ id: doc.id, name: p.name, lat: coords[1], lng: coords[0] });
    });
    // Newest imports first; the client caps each pass
    res.json({ success: true, data: { places: places.slice(0, 60), count: places.length } });
  } catch (error) {
    console.error('❌ getPlacesNeedingPhoto failed:', error);
    res.status(500).json({ success: false, message: 'Failed to load places needing a photo' });
  }
};

// @desc    Attach the on-device Look Around snapshot (already uploaded via
//          /upload/image) as the place's photo — only if it still has none.
//          { unavailable: true } records a strike instead (no coverage).
// @route   PUT /api/places/:id/photo-fallback
// @access  Private (owner)
exports.setPlacePhotoFallback = async (req, res) => {
  try {
    const ref = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const snap = await ref.get();
    if (!snap.exists || snap.data().deletedAt) {
      return res.status(404).json({ success: false, message: 'Place not found' });
    }
    const place = snap.data();
    if (!isSameUser(place.addedBy, req.user.uid)) {
      return res.status(403).json({ success: false, message: 'Not your place' });
    }
    const photoUrl = typeof req.body?.photoUrl === 'string' ? req.body.photoUrl.trim() : '';
    const { FieldValue } = admin.firestore;

    if (!photoUrl) {
      await ref.update({ photoFallbackAttempts: FieldValue.increment(1), updatedAt: new Date().toISOString() });
      return res.json({ success: true, data: { placeId: ref.id, applied: false } });
    }
    if (!/^https:\/\/(firebasestorage\.googleapis\.com|storage\.googleapis\.com)\//.test(photoUrl)) {
      return res.status(400).json({ success: false, message: 'Photo must be an uploaded FavCircles image' });
    }
    if (Array.isArray(place.photos) && place.photos.length > 0) {
      // The user (or another pass) got there first — never overwrite a real photo
      return res.json({ success: true, data: { placeId: ref.id, applied: false } });
    }
    await ref.update({
      photos: [photoUrl],
      photoSource: 'apple_look_around',
      photoFallbackAttempts: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });
    // The circle may have been cover-less until now (imports arrive photo-less)
    ensureCircleCoverImage(place.circleId, photoUrl);
    res.json({ success: true, data: { placeId: ref.id, applied: true } });
  } catch (error) {
    console.error('❌ setPlacePhotoFallback failed:', error);
    res.status(500).json({ success: false, message: 'Failed to set photo' });
  }
};

// @desc    Stamp an on-device Apple Maps resolution onto an unmapped import:
//          location + geohash, address when the save has none, canonical
//          venue link, and a venue-level duplicate check against the caller's
//          other saves (the import couldn't dedup coordinate-less rows — now
//          that this one has coordinates, report what it collides with; the
//          client offers a mass-delete review, nothing is deleted here).
// @route   PUT /api/places/:id/resolve
//          body: { latitude, longitude, address?, applePoiCategory? }
// @access  Private (place owner)
exports.resolveImportedPlace = async (req, res) => {
  try {
    const { latitude, longitude, address, applePoiCategory, notFound } = req.body || {};

    // Failure report from the on-device resolver: count the strike so the
    // unresolved feed can retire rows that fail three full passes. Owner
    // check happens below the fetch, same as the success path.
    if (notFound === true) {
      const failRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
      const failDoc = await failRef.get();
      if (!failDoc.exists || failDoc.data().deletedAt) {
        return res.status(404).json({ success: false, message: 'Place not found' });
      }
      if (failDoc.data().addedBy !== req.user.uid) {
        return res.status(403).json({ success: false, message: 'Not your place' });
      }
      const { FieldValue } = require('firebase-admin').firestore;
      await failRef.update({
        resolutionAttempts: FieldValue.increment(1),
        updatedAt: new Date().toISOString()
      });
      return res.json({ success: true, data: { placeId: req.params.id, recorded: true } });
    }

    if (typeof latitude !== 'number' || typeof longitude !== 'number' ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180 ||
        (latitude === 0 && longitude === 0)) {
      return res.status(400).json({ success: false, message: 'Valid coordinates are required' });
    }

    const placeRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const placeDoc = await placeRef.get();
    if (!placeDoc.exists || placeDoc.data().deletedAt) {
      return res.status(404).json({ success: false, message: 'Place not found' });
    }
    const place = placeDoc.data();
    if (place.addedBy !== req.user.uid) {
      return res.status(403).json({ success: false, message: 'Not your place' });
    }

    const { FieldValue } = require('firebase-admin').firestore;
    const updateData = {
      location: { type: 'Point', coordinates: [longitude, latitude] },
      // geofire expects [lat, lng]
      geohash: geofire.geohashForLocation([latitude, longitude]),
      needsResolution: FieldValue.delete(),
      resolutionAttempts: FieldValue.delete(),
      updatedAt: new Date().toISOString()
    };
    if (address && typeof address === 'string' && address.trim() &&
        (!place.address || place.address === 'Address pending')) {
      updateData.address = address.trim();
    }
    if (typeof applePoiCategory === 'string' && applePoiCategory) {
      updateData.applePoiCategory = applePoiCategory;
    }
    await placeRef.update(updateData);

    // Now that it has a location, link the canonical venue (fills the cached
    // category/city fields too). Best-effort.
    let globalPlaceId = place.globalPlaceId || null;
    try {
      const { ensureGlobalPlaceLink } = require('../../services/globalPlaceResolver');
      globalPlaceId = await ensureGlobalPlaceLink(await placeRef.get()) || globalPlaceId;
    } catch (linkError) {
      console.error(`⚠️ resolve: global link failed for ${req.params.id}:`, linkError.message);
    }

    // Keep the browse location tree fresh (best-effort)
    try {
      const { indexSavedPlace } = require('../../services/circleLocationSummary');
      indexSavedPlace(place.circleId, { ...place, ...updateData });
    } catch (e) { /* non-fatal */ }

    // Venue-level duplicate check against the caller's other live saves
    const normName = s => (s || '').toLowerCase().trim().replace(/[^\w\s]/g, '').replace(/\s+/g, ' ');
    const distanceMeters = (lat1, lng1, lat2, lng2) => {
      const R = 6371000;
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLng = (lng2 - lng1) * Math.PI / 180;
      const s = Math.sin(dLat / 2) ** 2 +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
      return 2 * R * Math.asin(Math.sqrt(s));
    };

    let duplicateOf = null;
    const othersSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', req.user.uid)
      .get();
    othersSnapshot.forEach(doc => {
      if (duplicateOf || doc.id === req.params.id) return;
      const other = doc.data();
      if (other.deletedAt || other.needsResolution) return;
      const sameVenue = (globalPlaceId && other.globalPlaceId === globalPlaceId);
      let sameByProximity = false;
      if (!sameVenue && normName(other.name) === normName(place.name)) {
        const c = other.location && other.location.coordinates;
        if (Array.isArray(c) && c.length === 2) {
          sameByProximity = distanceMeters(latitude, longitude, c[1], c[0]) < 250;
        }
      }
      if (sameVenue || sameByProximity) {
        duplicateOf = { placeId: doc.id, name: other.name, circleId: other.circleId };
      }
    });
    if (duplicateOf) {
      try {
        const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(duplicateOf.circleId).get();
        if (circleDoc.exists) duplicateOf.circleName = circleDoc.data().name || null;
      } catch (e) { /* display-only */ }
    }

    res.json({
      success: true,
      data: {
        placeId: req.params.id,
        globalPlaceId,
        address: updateData.address || place.address || null,
        duplicateOf
      }
    });
  } catch (error) {
    console.error('❌ resolveImportedPlace failed:', error);
    res.status(500).json({ success: false, message: 'Failed to resolve place' });
  }
};

// @desc    Migrate Google API photo URLs to Firebase Storage
// @route   POST /api/places/migrate-photos
// @access  Private (admin only)
exports.migrateGooglePhotosToFirebase = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { placeId, dryRun = false } = req.body;
    
    console.log('🔄 Starting photo migration:', { userId, placeId, dryRun });
    
    // Import storage service
    const { downloadAndUploadMultipleImages } = require('../../services/storage');
    
    // Query for places with Google API URLs
    let query = db.collection(COLLECTIONS.PLACES);
    
    if (placeId) {
      // Migrate specific place
      query = query.where(admin.firestore.FieldPath.documentId(), '==', placeId);
    }
    
    const placesSnapshot = await query.get();
    
    const placesToMigrate = [];
    const migrationResults = [];
    
    // Find places with Google API URLs
    placesSnapshot.forEach(doc => {
      const place = serializeDoc(doc);
      
      if (place.photos && place.photos.length > 0) {
        const googleUrls = place.photos.filter(photo => 
          photo.includes('maps.googleapis.com') || 
          photo.includes('photoreference=')
        );
        
        if (googleUrls.length > 0) {
          placesToMigrate.push({
            id: doc.id,
            name: place.name,
            photos: place.photos,
            googleUrls: googleUrls
          });
        }
      }
    });
    
    console.log(`📊 Found ${placesToMigrate.length} places with Google API URLs`);
    
    if (dryRun) {
      return res.status(200).json({
        success: true,
        message: 'Dry run complete',
        placesToMigrate: placesToMigrate.map(p => ({
          id: p.id,
          name: p.name,
          googleUrlCount: p.googleUrls.length
        }))
      });
    }
    
    // Process each place
    for (const place of placesToMigrate) {
      try {
        console.log(`Processing place: ${place.name} (${place.id})`);
        
        // Download and upload Google photos
        const { uploadedUrls, errors } = await downloadAndUploadMultipleImages(place.googleUrls);
        
        if (uploadedUrls.length > 0) {
          // Filter out Google Places API URLs and add Firebase URLs
          const nonGoogleUrls = place.photos.filter(photo => 
            !photo.includes('maps.googleapis.com') && 
            !photo.includes('photoreference=')
          );
          
          const newPhotos = [...nonGoogleUrls, ...uploadedUrls];
          
          // Update the place in Firestore
          await db.collection(COLLECTIONS.PLACES).doc(place.id).update({
            photos: newPhotos,
            updatedAt: new Date().toISOString()
          });
          
          migrationResults.push({
            placeId: place.id,
            placeName: place.name,
            status: 'success',
            migratedCount: uploadedUrls.length,
            failedCount: errors.length
          });
          
          console.log(`✅ Migrated ${uploadedUrls.length} photos for ${place.name}`);
        } else {
          migrationResults.push({
            placeId: place.id,
            placeName: place.name,
            status: 'failed',
            error: 'No photos could be migrated',
            errors: errors
          });
          
          console.error(`❌ Failed to migrate photos for ${place.name}`);
        }
      } catch (error) {
        console.error(`Error migrating place ${place.id}:`, error);
        migrationResults.push({
          placeId: place.id,
          placeName: place.name,
          status: 'error',
          error: error.message
        });
      }
    }
    
    const successCount = migrationResults.filter(r => r.status === 'success').length;
    const failedCount = migrationResults.filter(r => r.status !== 'success').length;
    
    res.status(200).json({
      success: true,
      message: `Migration complete: ${successCount} succeeded, ${failedCount} failed`,
      results: migrationResults
    });
    
  } catch (error) {
    console.error('Error in photo migration:', error);
    next(error);
  }
};
