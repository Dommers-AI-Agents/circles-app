// services/googleEnrichment.js
// Google Places enrichment for a save: canonical venue first (zero Google
// spend when anyone on the platform already saved this venue with Google
// data), a Google lookup only for venues new to the whole platform.
// Moved out of checkInController and createPlace (2026-10-17) so Add Place
// (share extension), check-ins and Build my map all use one process; Wes:
// "use the same process we have for manually adding a place".
const { Client } = require('@googlemaps/google-maps-services-js');
const { googleMapsApiKey } = require('../config/config');
const { buildSearchTokens } = require('../models/GlobalPlace');

const googleMapsClient = new Client({});

// Helper function to enrich place data with Google Places API
// options.skipPhotos: don't fetch/re-host the Google photo — pass it when the
// canonical venue already has photos, or every additional saver mints another
// Firebase Storage copy of the same image (billed Photo request + a
// byte-identical duplicate in the gallery).
async function enrichPlaceWithGoogleData(placeName, location, options = {}) {
  try {
    if (!googleMapsApiKey) {
      console.warn('Google Maps API key not configured, skipping enrichment');
      return {};
    }
    
    // Search for the place using name and location
    const searchQuery = placeName;
    const searchLocation = location ? `${location.latitude},${location.longitude}` : null;
    
    // First try to find the place
    const searchResponse = await googleMapsClient.findPlaceFromText({
      params: {
        input: searchQuery,
        inputtype: 'textquery',
        fields: ['place_id', 'name', 'formatted_address', 'photos', 'types', 'rating', 'price_level'],
        locationbias: searchLocation ? `circle:1000@${searchLocation}` : undefined,
        key: googleMapsApiKey
      }
    });
    
    if (!searchResponse.data.candidates || searchResponse.data.candidates.length === 0) {
      console.log(`No Google Places results found for: ${placeName}`);
      // A definite "no such place" (not an error): check-ins remember it so
      // the same name at the same spot doesn't bill again (checkInGuards).
      return { noMatch: true };
    }
    
    const candidate = searchResponse.data.candidates[0];
    const placeId = candidate.place_id;
    
    // Get detailed place information
    const detailsResponse = await googleMapsClient.placeDetails({
      params: {
        place_id: placeId,
        // Every field this call's groups already pay for (googlePlaceFields)
        fields: require('./googlePlaceFields').DETAILS_ALL,
        // Pin to English so weekday_text day names match the dayIndex map below
        language: 'en',
        key: googleMapsApiKey
      }
    });
    
    const placeDetails = detailsResponse.data.result;

    // Re-host the photo on Firebase Storage. Persisting raw
    // maps.googleapis.com URLs (the old behavior) billed a Places Photo
    // request on every render of the place, forever, and embedded the server
    // API key in client-readable documents — the create-place path rejects
    // exactly these URLs for the same reason.
    let photos = [];
    if (!options.skipPhotos && placeDetails.photos && placeDetails.photos.length > 0) {
      const photoUrl = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${placeDetails.photos[0].photo_reference}&key=${googleMapsApiKey}`;
      try {
        const { downloadAndUploadMultipleImages } = require('./storage');
        const { uploadedUrls } = await downloadAndUploadMultipleImages([photoUrl]);
        photos = uploadedUrls || [];
      } catch (photoError) {
        console.error('⚠️ Check-in photo re-host failed, continuing without photo:', photoError.message);
      }
    }

    // Forward Google's raw types and let the shared cascade
    // (services/placeCategoryDerivation) classify the venue. This replaced a
    // hand-rolled if-chain here that covered five categories and emitted
    // 'shopping' — not a value in the place-category enum ('retail' is), so
    // check-ins at stores were filed under Other and never matched the
    // Shopping filter chip.
    return {
      googlePlaceId: placeId,
      name: placeDetails.name || placeName,
      address: placeDetails.formatted_address || '',
      photos: photos,
      googleTypes: placeDetails.types || [],
      rating: placeDetails.rating || null,
      userRatingsTotal: placeDetails.user_ratings_total || null,
      priceLevel: placeDetails.price_level || null,
      website: placeDetails.website || null,
      phoneNumber: placeDetails.formatted_phone_number || null,
      description: placeDetails.editorial_summary?.overview || null,
      // ?? not || — false is a real answer ("does not deliver"), null = unknown
      delivery: placeDetails.delivery ?? null,
      dineIn: placeDetails.dine_in ?? null,
      reservable: placeDetails.reservable ?? null,
      takeout: placeDetails.takeout ?? null,
      curbsidePickup: placeDetails.curbside_pickup ?? null,
      // The rest of the free signals (types are above as googleTypes)
      googleSignals: require('./googlePlaceFields').googleSignals(placeDetails),
      // Convert Google's weekday_text strings to { day, hours } objects -
      // the iOS OpeningHour model requires an integer `day` and fails to
      // decode plain strings (which breaks any response containing the place)
      openingHours: placeDetails.opening_hours && placeDetails.opening_hours.weekday_text
        ? placeDetails.opening_hours.weekday_text.map((text, i) => {
            const dayIndex = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 };
            const dayName = text.split(':')[0].trim().toLowerCase();
            // weekday_text is Monday-first; iOS uses 0=Sunday, so the positional
            // fallback (unrecognized day name) is (i + 1) % 7
            return { day: dayIndex[dayName] != null ? dayIndex[dayName] : (i + 1) % 7, hours: text };
          })
        : null
    };
  } catch (error) {
    console.error('Error enriching place with Google data:', error);
    return {};
  }
}

/**
 * Fill a bare save (name + coordinates, no googlePlaceId) from its venue:
 * the canonical record's googlePlaceId when it already has one (no Google
 * call), otherwise Google's details and photo, upgrading a bare canonical in
 * place so every save of the venue sees them. Mutates `placeData`. Returns
 * true when it found the venue on Google. Never throws.
 */
async function enrichSaveFromGoogle(placeData) {
  try {
    const coords = placeData.location?.coordinates;
    let canonicalDoc = null;
    if (Array.isArray(coords) && coords.length === 2) {
      const { findCanonicalByNameAndLocation } = require('./globalPlaceResolver');
      canonicalDoc = await findCanonicalByNameAndLocation(placeData.name, { coordinates: coords });
    }
    const canonicalData = canonicalDoc ? canonicalDoc.data() : null;

    if (canonicalData && canonicalData.googlePlaceId) {
      // Genuinely enriched canonical: zero Google spend — the anchor
      // below overlays every venue field from it.
      placeData.googlePlaceId = canonicalData.googlePlaceId;
      console.log(`✅ Share save matched enriched canonical ${canonicalDoc.id} — skipping Google`);
    } else if (Array.isArray(coords) && coords.length === 2) {
      // No canonical, or a BARE one (seeded by an earlier bare save of
      // this venue — a bare match must not satisfy canonical-first, or
      // the venue stays bare forever).
      // (Same file. This was require('../checkInController') — a path that
      // doesn't exist from services/, so every enrichment failed bare.)
      const googleData = await enrichPlaceWithGoogleData(placeData.name, {
        latitude: coords[1],
        longitude: coords[0]
      }, {
        // A bare canonical can still carry photos (copied from the first
        // save) — re-hosting Google's photo again would add a
        // byte-identical duplicate under a new URL.
        skipPhotos: !!(canonicalData && require('./placePhotoService').hasVisiblePhotos(canonicalData.photos))
      });
      if (googleData.googlePlaceId) {
        placeData.googlePlaceId = googleData.googlePlaceId;
        if (googleData.name) placeData.name = googleData.name;
        if (googleData.address) placeData.address = googleData.address;
        if (googleData.photos && googleData.photos.length > 0) placeData.photos = googleData.photos;
        if (googleData.googleTypes && googleData.googleTypes.length > 0) placeData.googleTypes = googleData.googleTypes;
        if (googleData.googleSignals) placeData.googleSignals = googleData.googleSignals;
        placeData.rating = googleData.rating ?? placeData.rating;
        placeData.userRatingsTotal = googleData.userRatingsTotal ?? placeData.userRatingsTotal;
        placeData.priceLevel = googleData.priceLevel ?? placeData.priceLevel;
        placeData.website = googleData.website || placeData.website;
        placeData.phone = googleData.phoneNumber || placeData.phone;
        placeData.openingHours = googleData.openingHours || placeData.openingHours;
        placeData.delivery = googleData.delivery ?? placeData.delivery;
        placeData.dineIn = googleData.dineIn ?? placeData.dineIn;
        placeData.reservable = googleData.reservable ?? placeData.reservable;
        placeData.takeout = googleData.takeout ?? placeData.takeout;
        placeData.curbsidePickup = googleData.curbsidePickup ?? placeData.curbsidePickup;
        if (googleData.description) {
          placeData.description = googleData.description;
          placeData.descriptionSource = 'google_editorial';
        }
        console.log(`✅ Share save enriched from Google: ${googleData.googlePlaceId}`);

        // Upgrade the bare canonical IN PLACE. Without this,
        // ensureGlobalPlaceLink matches the save to the bare record,
        // strips the enriched fields off the save, and every read
        // overlays bare data — the enrichment would vanish.
        if (canonicalDoc) {
          const { createAttributedPhoto } = require('../models/GlobalPlace');
          const upgradedName = googleData.name || canonicalData.name;
          const canonicalUpdates = {
            googlePlaceId: googleData.googlePlaceId,
            name: upgradedName,
            nameLower: (upgradedName || '').toLowerCase(),
            searchTokens: buildSearchTokens(upgradedName),
            address: googleData.address || canonicalData.address,
            'googleData.rating': googleData.rating ?? null,
            'googleData.userRatingsTotal': googleData.userRatingsTotal ?? null,
            'googleData.priceLevel': googleData.priceLevel ?? null,
            'googleData.website': googleData.website || null,
            'googleData.phone': googleData.phoneNumber || null,
            'googleData.openingHours': googleData.openingHours || null,
            'googleData.delivery': googleData.delivery ?? null,
            'googleData.dineIn': googleData.dineIn ?? null,
            'googleData.reservable': googleData.reservable ?? null,
            'googleData.takeout': googleData.takeout ?? null,
            'googleData.curbsidePickup': googleData.curbsidePickup ?? null,
            updatedAt: new Date().toISOString()
          };
          if (googleData.description && !canonicalData.description) {
            canonicalUpdates.description = googleData.description;
            canonicalUpdates.descriptionSource = 'google_editorial';
          }
          if (googleData.photos && googleData.photos.length > 0 &&
              !require('./placePhotoService').hasVisiblePhotos(canonicalData.photos)) {
            canonicalUpdates.photos = googleData.photos.map(url => createAttributedPhoto({
              url,
              uploadedBy: null,
              uploadedByName: null,
              source: 'google_places'
            }));
          }
          await canonicalDoc.ref.update(canonicalUpdates);
          console.log(`⬆️ Upgraded bare canonical ${canonicalDoc.id} with Google enrichment`);
          // Types/serves_* kept, category from Google unless manually chosen
          await require('./venueGoogleSignals').applyGoogleDetails(canonicalDoc.id, null, {
            venue: { ...canonicalData, ...canonicalUpdates }, signals: googleData.googleSignals, name: upgradedName })
            .catch((e) => console.warn('⚠️ Google signals not applied:', e.message));
        }
      }
    }
    return !!placeData.googlePlaceId;
  } catch (enrichError) {
    console.warn('⚠️ Save enrichment failed (continuing bare):', enrichError.message);
    return false;
  }
}

/**
 * Which Find Place candidate is the save's venue. Google's first pick (its
 * ranking weighs prominence) when it's within `nearMeters` of the save; only
 * when it's farther does the nearest listing win. Pure.
 * coordinates: [lng, lat] of the save, or null.
 */
function pickGoogleCandidate(candidates, coordinates, nearMeters = 500) {
  if (!Array.isArray(candidates) || candidates.length === 0) return null;
  if (!Array.isArray(coordinates) || coordinates.length !== 2) return candidates[0];
  const [lng, lat] = coordinates;
  const meters = (c) => {
    const loc = c && c.geometry && c.geometry.location;
    if (!loc) return Infinity;
    const toRad = (d) => d * Math.PI / 180;
    const dLat = toRad(loc.lat - lat);
    const dLng = toRad(loc.lng - lng);
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat)) * Math.cos(toRad(loc.lat)) * Math.sin(dLng / 2) ** 2;
    return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  };
  if (meters(candidates[0]) <= nearMeters) return candidates[0];
  return candidates.reduce((best, c) => (meters(c) < meters(best) ? c : best), candidates[0]);
}

module.exports = { enrichPlaceWithGoogleData, enrichSaveFromGoogle, pickGoogleCandidate };
