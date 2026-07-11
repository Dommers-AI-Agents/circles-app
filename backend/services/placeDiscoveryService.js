// backend/services/placeDiscoveryService.js
// Service to discover local places for user onboarding

const { Client } = require('@googlemaps/google-maps-services-js');
const { getRandomLocalPlace } = require('../data/popularPlaces');

const googleMapsClient = new Client({});

const googleApiKey = () => process.env.GOOGLE_MAPS_API_KEY || process.env.PLACES_API_KEY;

// Map a Google Places types array to the app's PlaceCategory values
const CATEGORY_BY_GOOGLE_TYPE = {
  cafe: 'cafe',
  bakery: 'cafe',
  restaurant: 'restaurant',
  meal_takeaway: 'restaurant',
  bar: 'bar',
  supermarket: 'retail',
  grocery_or_supermarket: 'retail',
  department_store: 'retail',
  park: 'outdoor',
  tourist_attraction: 'attraction'
};

function categoryFromTypes(types = []) {
  for (const type of types) {
    if (CATEGORY_BY_GOOGLE_TYPE[type]) return CATEGORY_BY_GOOGLE_TYPE[type];
  }
  return 'restaurant';
}

class PlaceDiscoveryService {

  /**
   * Find a real, recognizable place near the user for onboarding.
   * Resolution order for the search location: explicit coordinates →
   * geocoded zipcode. Returns null when neither resolves or the API is
   * unavailable - callers fall back to the curated list.
   *
   * @param {Object} opts
   * @param {string} [opts.zipcode]      US zipcode from registration
   * @param {Object} [opts.coordinates]  { latitude, longitude }
   * @param {string} [opts.city]         Used only for the description text
   */
  static async findNearbyPlace({ zipcode, coordinates, city } = {}) {
    const key = googleApiKey();
    if (!key) {
      console.log('🔍 PlaceDiscovery: No Google Maps API key, skipping nearby search');
      return null;
    }

    try {
      // Resolve a search center. Zipcode resolution goes through the Places
      // API's find-place endpoint (not the Geocoding API, which is not enabled
      // on this Google Cloud project).
      let location = null;
      if (coordinates && typeof coordinates.latitude === 'number' && typeof coordinates.longitude === 'number') {
        location = { lat: coordinates.latitude, lng: coordinates.longitude };
      } else if (zipcode) {
        const geo = await googleMapsClient.findPlaceFromText({
          params: {
            input: `${zipcode} USA`,
            inputtype: 'textquery',
            fields: ['geometry'],
            key
          }
        });
        const candidate = geo.data.candidates && geo.data.candidates[0];
        if (candidate && candidate.geometry) {
          location = candidate.geometry.location;
        }
      }

      if (!location) {
        console.log('🔍 PlaceDiscovery: Could not resolve a search location');
        return null;
      }

      // Prefer cafes (widely recognizable), fall back to restaurants
      for (const type of ['cafe', 'restaurant']) {
        const response = await googleMapsClient.placesNearby({
          params: { location, radius: 8000, type, language: 'en', key }
        });

        const candidates = (response.data.results || [])
          .filter(p => p.business_status === 'OPERATIONAL' && p.name && p.geometry)
          // Most-reviewed first: review volume is the best proxy for
          // "a place the new user will recognize"
          .sort((a, b) => (b.user_ratings_total || 0) - (a.user_ratings_total || 0));

        const place = candidates[0];
        if (!place) continue;

        console.log(`📍 PlaceDiscovery: Found "${place.name}" (${place.user_ratings_total || 0} reviews) near ${zipcode || 'coordinates'}`);
        return {
          name: place.name,
          category: categoryFromTypes(place.types),
          description: `Popular local spot${city ? ` in ${city}` : ' in your area'}`,
          address: place.vicinity || place.formatted_address || (city || 'Local area'),
          coordinates: [place.geometry.location.lng, place.geometry.location.lat],
          rating: place.rating || null,
          googlePlaceId: place.place_id || null
        };
      }

      console.log('🔍 PlaceDiscovery: No operational places found nearby');
      return null;

    } catch (error) {
      console.error('❌ PlaceDiscovery: Nearby search failed:', error.message);
      return null;
    }
  }

  /**
   * Curated-list fallback used when nearby search isn't possible.
   */
  static async findLocalPlace(userLocation = null) {
    try {
      const place = getRandomLocalPlace(userLocation);
      return { success: true, place };
    } catch (error) {
      console.error('❌ Error finding local place:', error);
      return {
        success: false,
        place: getRandomLocalPlace(null),
        error: error.message
      };
    }
  }
}

module.exports = PlaceDiscoveryService;
