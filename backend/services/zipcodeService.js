// backend/services/zipcodeService.js
// Single source of truth for zipcode → { city, state, coordinates? }.
// Used at registration AND on every profile save that touches the zipcode,
// so a user's zipcode and displayed location can never disagree.
//
// Resolution order: local table (instant) → Places Find Place (the Geocoding
// API is not enabled on this GCP project) → coarse state-by-range fallback.

// Load zipcode database
let zipcodeDatabase = null;
try {
  zipcodeDatabase = require('../data/us-zipcodes-sample.json');
  console.log('✅ Loaded zipcode database with', Object.keys(zipcodeDatabase).length, 'entries');
} catch (error) {
  console.warn('⚠️ Could not load zipcode database, will use fallback');
}

async function geocodeZipcode(zipcode) {
  try {
    // First try local database for instant lookup
    if (zipcodeDatabase && zipcodeDatabase[zipcode]) {
      const data = zipcodeDatabase[zipcode];
      console.log(`📍 Found ${zipcode} in local database: ${data.city}, ${data.state}`);
      return {
        city: data.city,
        state: data.state
      };
    }

    // Fallback to Google Maps API if not in local database
    const apiKey = process.env.GOOGLE_MAPS_API_KEY || process.env.PLACES_API_KEY;
    if (!apiKey) {
      console.log('No Google Maps API key available for geocoding');
      // Return a generic fallback based on zipcode range
      return getGenericLocationByZipcode(zipcode);
    }

    // Use the Places API find-place endpoint (the Geocoding API is not enabled
    // on this Google Cloud project). formatted_address comes back as
    // "City, ST 12345" for US zipcodes.
    const response = await fetch(
      `https://maps.googleapis.com/maps/api/place/findplacefromtext/json?input=${zipcode}%20USA&inputtype=textquery&fields=geometry,formatted_address&key=${apiKey}`
    );

    const data = await response.json();

    if (data.status === 'OK' && data.candidates && data.candidates.length > 0) {
      const candidate = data.candidates[0];

      let city = null;
      let state = null;
      const match = (candidate.formatted_address || '').match(/^(.+?),\s*([A-Z]{2})\b/);
      if (match) {
        city = match[1];
        state = match[2];
      }

      return {
        city,
        state,
        coordinates: candidate.geometry ? {
          latitude: candidate.geometry.location.lat,
          longitude: candidate.geometry.location.lng,
          timestamp: new Date().toISOString()
        } : null
      };
    }

    // If Google API fails, use generic fallback
    return getGenericLocationByZipcode(zipcode);
  } catch (error) {
    console.error('Error geocoding zipcode:', error);
    // Return generic location as last resort
    return getGenericLocationByZipcode(zipcode);
  }
}

// Fallback function for generic location by zipcode range
function getGenericLocationByZipcode(zipcode) {
  const zip = parseInt(zipcode);

  // Basic US zipcode ranges by state
  if (zip >= 1001 && zip <= 2799) return { city: 'Massachusetts', state: 'MA' };
  if (zip >= 2800 && zip <= 2999) return { city: 'Rhode Island', state: 'RI' };
  if (zip >= 3000 && zip <= 3899) return { city: 'New Hampshire', state: 'NH' };
  if (zip >= 3900 && zip <= 4999) return { city: 'Maine', state: 'ME' };
  if (zip >= 5000 && zip <= 5999) return { city: 'Vermont', state: 'VT' };
  if (zip >= 6000 && zip <= 6999) return { city: 'Connecticut', state: 'CT' };
  if (zip >= 7000 && zip <= 8999) return { city: 'New Jersey', state: 'NJ' };
  if (zip >= 10000 && zip <= 14999) return { city: 'New York', state: 'NY' };
  if (zip >= 15000 && zip <= 19699) return { city: 'Pennsylvania', state: 'PA' };
  if (zip >= 19700 && zip <= 19999) return { city: 'Delaware', state: 'DE' };
  if (zip >= 20000 && zip <= 20599) return { city: 'Washington', state: 'DC' };
  if (zip >= 20600 && zip <= 21999) return { city: 'Maryland', state: 'MD' };
  if (zip >= 22000 && zip <= 24699) return { city: 'Virginia', state: 'VA' };
  if (zip >= 24700 && zip <= 26999) return { city: 'West Virginia', state: 'WV' };
  if (zip >= 27000 && zip <= 28999) return { city: 'North Carolina', state: 'NC' };
  if (zip >= 29000 && zip <= 29999) return { city: 'South Carolina', state: 'SC' };
  if (zip >= 30000 && zip <= 31999) return { city: 'Georgia', state: 'GA' };
  if (zip >= 32000 && zip <= 34999) return { city: 'Florida', state: 'FL' };
  if (zip >= 35000 && zip <= 36999) return { city: 'Alabama', state: 'AL' };
  if (zip >= 37000 && zip <= 38599) return { city: 'Tennessee', state: 'TN' };
  if (zip >= 38600 && zip <= 39999) return { city: 'Mississippi', state: 'MS' };
  if (zip >= 40000 && zip <= 42799) return { city: 'Kentucky', state: 'KY' };
  if (zip >= 43000 && zip <= 45999) return { city: 'Ohio', state: 'OH' };
  if (zip >= 46000 && zip <= 47999) return { city: 'Indiana', state: 'IN' };
  if (zip >= 48000 && zip <= 49999) return { city: 'Michigan', state: 'MI' };
  if (zip >= 50000 && zip <= 52999) return { city: 'Iowa', state: 'IA' };
  if (zip >= 53000 && zip <= 54999) return { city: 'Wisconsin', state: 'WI' };
  if (zip >= 55000 && zip <= 56799) return { city: 'Minnesota', state: 'MN' };
  if (zip >= 57000 && zip <= 57999) return { city: 'South Dakota', state: 'SD' };
  if (zip >= 58000 && zip <= 58999) return { city: 'North Dakota', state: 'ND' };
  if (zip >= 59000 && zip <= 59999) return { city: 'Montana', state: 'MT' };
  if (zip >= 60000 && zip <= 62999) return { city: 'Illinois', state: 'IL' };
  if (zip >= 63000 && zip <= 65999) return { city: 'Missouri', state: 'MO' };
  if (zip >= 66000 && zip <= 67999) return { city: 'Kansas', state: 'KS' };
  if (zip >= 68000 && zip <= 69999) return { city: 'Nebraska', state: 'NE' };
  if (zip >= 70000 && zip <= 71599) return { city: 'Louisiana', state: 'LA' };
  if (zip >= 71600 && zip <= 72999) return { city: 'Arkansas', state: 'AR' };
  if (zip >= 73000 && zip <= 74999) return { city: 'Oklahoma', state: 'OK' };
  if (zip >= 75000 && zip <= 79999) return { city: 'Texas', state: 'TX' };
  if (zip >= 80000 && zip <= 81999) return { city: 'Colorado', state: 'CO' };
  if (zip >= 82000 && zip <= 83199) return { city: 'Wyoming', state: 'WY' };
  if (zip >= 83200 && zip <= 83999) return { city: 'Idaho', state: 'ID' };
  if (zip >= 84000 && zip <= 84999) return { city: 'Utah', state: 'UT' };
  if (zip >= 85000 && zip <= 86599) return { city: 'Arizona', state: 'AZ' };
  if (zip >= 87000 && zip <= 88499) return { city: 'New Mexico', state: 'NM' };
  if (zip >= 88500 && zip <= 89999) return { city: 'Nevada', state: 'NV' };
  if (zip >= 90000 && zip <= 96199) return { city: 'California', state: 'CA' };
  if (zip >= 96700 && zip <= 96899) return { city: 'Hawaii', state: 'HI' };
  if (zip >= 97000 && zip <= 97999) return { city: 'Oregon', state: 'OR' };
  if (zip >= 98000 && zip <= 99499) return { city: 'Washington', state: 'WA' };
  if (zip >= 99500 && zip <= 99999) return { city: 'Alaska', state: 'AK' };

  // Default fallback
  return { city: 'United States', state: 'US' };
}

module.exports = { geocodeZipcode, getGenericLocationByZipcode };
