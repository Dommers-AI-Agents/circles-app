// backend/services/placeCategoryDerivation.js
//
// Single source of truth for deriving a place's category from whatever signals
// we have. Deterministic, free (no network), and testable. This is tiers 1–2 of
// the cascade described in the category-quality plan:
//
//   Tier 1 (deterministic): Google primaryType/types  or  Apple POI category
//   Tier 2 (text inference): keyword match over name/description/address
//   -> 'other' only when nothing matches (the tail the optional LLM tier handles)
//
// The category enum lives in models/FirestoreModels.js (validatePlace). Keep in
// sync if that list changes.

const {
  categoryFromGoogleTypes,
  categoryFromText
} = require('./importCategoryMapping');

// The full place-category enum (mirrors validatePlace in models/FirestoreModels).
const ALL_CATEGORIES = [
  'restaurant', 'cafe', 'bar', 'hotel', 'retail', 'service', 'attraction',
  'entertainment', 'healthcare', 'fitness', 'education', 'outdoor', 'transport',
  'finance', 'home', 'work', 'other'
];

// Categories that may be auto-assigned. 'home'/'work' are user-designated only
// (never inferred), so the deterministic tiers and the LLM tier never pick them.
const AUTO_CATEGORIES = ALL_CATEGORIES.filter(c => c !== 'home' && c !== 'work');

// Apple MapKit POI categories -> app category. Keyed on MKPointOfInterestCategory
// rawValues (e.g. "MKPOICategoryRestaurant"). Populated only when the client
// forwards mapItem.pointOfInterestCategory?.rawValue; harmless when absent.
const APPLE_POI_TO_CATEGORY = {
  MKPOICategoryRestaurant: 'restaurant',
  MKPOICategoryFoodMarket: 'retail',
  MKPOICategoryBakery: 'cafe',
  MKPOICategoryCafe: 'cafe',
  MKPOICategoryNightlife: 'bar',
  MKPOICategoryBrewery: 'bar',
  MKPOICategoryWinery: 'bar',
  MKPOICategoryHotel: 'hotel',
  MKPOICategoryStore: 'retail',
  MKPOICategoryFoodMarket2: 'retail',
  MKPOICategoryPharmacy: 'healthcare',
  MKPOICategoryHospital: 'healthcare',
  MKPOICategoryDoctor: 'healthcare',
  MKPOICategoryDentist: 'healthcare',
  MKPOICategoryVeterinary: 'healthcare',
  MKPOICategoryFitnessCenter: 'fitness',
  MKPOICategoryMuseum: 'attraction',
  MKPOICategoryLandmark: 'attraction',
  MKPOICategoryNationalMonument: 'attraction',
  MKPOICategoryAquarium: 'attraction',
  MKPOICategoryZoo: 'attraction',
  MKPOICategoryAmusementPark: 'entertainment',
  MKPOICategoryMovieTheater: 'entertainment',
  MKPOICategoryTheater: 'entertainment',
  MKPOICategoryStadium: 'entertainment',
  MKPOICategoryBowling: 'entertainment',
  MKPOICategoryCasino: 'entertainment',
  MKPOICategoryNightclub: 'bar',
  MKPOICategoryPark: 'outdoor',
  MKPOICategoryNationalPark: 'outdoor',
  MKPOICategoryBeach: 'outdoor',
  MKPOICategoryCampground: 'outdoor',
  MKPOICategoryMarina: 'outdoor',
  MKPOICategoryFishing: 'outdoor',
  MKPOICategoryKayaking: 'outdoor',
  MKPOICategoryHiking: 'outdoor',
  MKPOICategorySkiing: 'outdoor',
  MKPOICategoryGolf: 'outdoor',
  MKPOICategoryAirport: 'transport',
  MKPOICategoryPublicTransport: 'transport',
  MKPOICategoryParking: 'transport',
  MKPOICategoryGasStation: 'transport',
  MKPOICategoryEVCharger: 'transport',
  MKPOICategoryCarRental: 'transport',
  MKPOICategoryBank: 'finance',
  MKPOICategoryATM: 'finance',
  MKPOICategorySchool: 'education',
  MKPOICategoryUniversity: 'education',
  MKPOICategoryLibrary: 'education',
  MKPOICategoryLaundry: 'service',
  MKPOICategoryBeauty: 'service',
  MKPOICategoryAnimalService: 'service',
  MKPOICategoryAutoService: 'service',
  MKPOICategoryPostOffice: 'service',
  MKPOICategoryFireStation: 'service',
  MKPOICategoryPolice: 'service'
};

function categoryFromApplePoi(applePoiCategory) {
  if (!applePoiCategory) return 'other';
  return APPLE_POI_TO_CATEGORY[applePoiCategory] || 'other';
}

// Result: { category, source, confidence }
//   source: 'google' | 'apple' | 'text' | 'other'
//   confidence: rough 0–1 signal (deterministic hits are high; text is medium)
//
// Non-destructive callers should treat source 'other' as "leave/queue for the
// LLM tier" rather than a committed classification.
function deriveCategory(signals = {}) {
  const {
    googlePrimaryType,
    googleTypes,
    applePoiCategory,
    name,
    description,
    address
  } = signals;

  // Tier 1a: Google primary type (most authoritative when present)
  if (googlePrimaryType) {
    const fromPrimary = categoryFromGoogleTypes([googlePrimaryType]);
    if (fromPrimary !== 'other') {
      return { category: fromPrimary, source: 'google', confidence: 0.95 };
    }
  }

  // Tier 1b: Google types array (first recognized entry wins)
  if (Array.isArray(googleTypes) && googleTypes.length) {
    const fromTypes = categoryFromGoogleTypes(googleTypes);
    if (fromTypes !== 'other') {
      return { category: fromTypes, source: 'google', confidence: 0.9 };
    }
  }

  // Tier 1c: Apple POI category
  const fromApple = categoryFromApplePoi(applePoiCategory);
  if (fromApple !== 'other') {
    return { category: fromApple, source: 'apple', confidence: 0.9 };
  }

  // Tier 2: text inference over name/description/address
  const fromText = categoryFromText(name, description, address);
  if (fromText !== 'other') {
    return { category: fromText, source: 'text', confidence: 0.6 };
  }

  return { category: 'other', source: 'other', confidence: 0 };
}

module.exports = {
  deriveCategory,
  categoryFromApplePoi,
  APPLE_POI_TO_CATEGORY,
  ALL_CATEGORIES,
  AUTO_CATEGORIES
};
