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

  // Tier 2: text inference over the NAME (and description) only. The address is
  // deliberately excluded — town/street names like "Asbury Park", "Spring Lake"
  // or "Ocean Beach" would otherwise trip the outdoor/geo keywords and mislabel
  // a venue by where it is rather than what it is.
  const fromText = categoryFromText(name, description);
  if (fromText !== 'other') {
    return { category: fromText, source: 'text', confidence: 0.6 };
  }

  return { category: 'other', source: 'other', confidence: 0 };
}

// A canonical venue that is still 'other' gets one more free, deterministic
// try from a NEW save's signals (its Apple POI category, Google types, name)
// merged over whatever the venue already knows. Returns the globalPlaces
// update payload, or null when nothing better can be said. Only 'other' /
// blank ever moves — a real category, chosen or derived, is never overridden.
//
// Why: a venue first saved before the cascade existed (or via a thin check-in
// / import) sits at 'other' forever unless the nightly LLM sweep is on; the
// next person to save it usually brings the signal that classifies it.
function categoryUpgradeForOther(venueData = {}, saveData = {}) {
  if ((venueData.category || 'other') !== 'other') return null;
  const stamp = (category, source, confidence) => ({
    category,
    categorySource: source,
    categoryConfidence: confidence,
    categoryBefore: 'other',
    categoryClassifiedAt: new Date().toISOString()
  });

  // A category the saver chose (validatePlace already enforced the enum)
  // beats any inference — and must not be clobbered by the venue's 'other'.
  if (AUTO_CATEGORIES.includes(saveData.category) && saveData.category !== 'other') {
    return stamp(saveData.category, 'client', 1);
  }

  // Name only, no description: the backend name rules are substring matches
  // and descriptions carry "Website: https://tomsbarbershop.com" lines.
  const googleData = venueData.googleData || {};
  const derived = deriveCategory({
    googlePrimaryType: saveData.googlePrimaryType || venueData.googlePrimaryType || googleData.primaryType,
    googleTypes: firstNonEmptyArray(saveData.googleTypes, venueData.googleTypes, googleData.types),
    applePoiCategory: saveData.applePoiCategory || venueData.applePoiCategory,
    name: saveData.name || venueData.name
  });
  if (derived.category === 'other') return null;
  return stamp(derived.category, derived.source, derived.confidence);
}

// ---- Google's richer signals (googlePlaceFields.googleSignals) --------------

// 'food' is Google's own "serves food" type: on a bar it means a kitchen
// (Frenchy's Sip and Shop: bar + food, dine-in)
const MEAL_TYPES = new Set(['restaurant', 'meal_takeaway', 'meal_delivery', 'food']);
const SHOP_TYPES = new Set(['store', 'liquor_store', 'clothing_store', 'home_goods_store', 'gift_shop', 'book_store', 'shopping_mall']);

/**
 * One word isn't enough for many places. Google types come in the order it
 * ranks them, so a wine bar that serves dinner reads 'bar' first. A place
 * Google also calls a restaurant, or one that serves meals, is a restaurant
 * whose second label says what else it is (Wes, 2026-10-29: Frenchy's Sip and
 * Shop, "more like a restaurant with a wine bar").
 * Returns { category, subcategory } (subcategory may be null).
 */
function refineCategory({ category, googleTypes = [], serves = {}, dineIn = null, name = '' } = {}) {
  const types = new Set(googleTypes || []);
  const s = serves || {};
  const nm = String(name || '');
  const hasBar = types.has('bar') || types.has('night_club');
  const servesMeals = s.breakfast === true || s.brunch === true || s.lunch === true || s.dinner === true;
  const mealPlace = [...MEAL_TYPES].some((t) => types.has(t)) || servesMeals;
  const shop = [...SHOP_TYPES].some((t) => types.has(t)) || /\b(shop|market|provisions|boutique|bottle shop)\b/i.test(nm);

  const barKind = () => {
    if (/wine|vino|enoteca|cellar/i.test(nm) || (s.wine === true && (s.beer !== true || /\bsip\b/i.test(nm)))) return 'Wine bar';
    if (/brew(ery|ing|pub)|taproom/i.test(nm)) return 'Brewery';
    if (types.has('night_club')) return 'Nightclub';
    return 'Bar';
  };
  const withShop = (label) => (shop ? `${label} & shop` : label);

  let cat = category;
  let sub = null;
  if (cat === 'bar' && (mealPlace || (dineIn === true && servesMeals))) {
    cat = 'restaurant';
    sub = withShop(barKind());
  } else if (cat === 'restaurant' && hasBar) {
    sub = withShop(barKind());
  } else if (cat === 'bar') {
    const kind = barKind();
    sub = kind === 'Bar' ? (shop ? 'Bar & shop' : null) : withShop(kind);
  } else if (cat === 'cafe' && types.has('bakery')) {
    sub = 'Bakery';
  }
  return { category: cat, subcategory: sub };
}

/**
 * The venue's category from Google's signals alone, or null when Google
 * doesn't say (no types, or none we map).
 */
// Types Google puts on almost anything: an amphitheatre that sells tickets is
// a 'store', a stadium with concessions is 'food'. They classify a venue that
// has nothing better, but never overrule a category we already have
// (Skyla Credit Union Amphitheatre came out 'retail', 2026-10-29).
const WEAK_GOOGLE_TYPES = new Set(['store', 'food', 'point_of_interest', 'establishment']);

function classifyFromGoogle({ googlePrimaryType, googleTypes, serves, dineIn, name } = {}) {
  const derived = deriveCategory({ googlePrimaryType, googleTypes });
  if (derived.source !== 'google') return null;
  const refined = refineCategory({ category: derived.category, googleTypes, serves, dineIn, name });
  const specific = (googleTypes || []).filter((t) => !WEAK_GOOGLE_TYPES.has(t));
  const strong = !!googlePrimaryType || categoryFromGoogleTypes(specific) !== 'other';
  return { ...refined, source: 'google', confidence: strong ? derived.confidence : 0.5, strong };
}

/**
 * What to write when Google's signals arrive for a venue: Google outranks the
 * phone's guess (Apple POI, a category the app sent, text rules, the LLM).
 * Only an owner's or admin's choice ('manual') stands. Null when nothing
 * changes.
 */
function googleReclassification(venueData = {}, signals = {}) {
  if ((venueData.categorySource || null) === 'manual') return null;
  const google = classifyFromGoogle({ ...signals, name: signals.name || venueData.name });
  if (!google) return null;
  // Only generic types: keep the category we have, but still take Google's
  // second label when it adds one for that same category
  if (!google.strong && (venueData.category || 'other') !== 'other') {
    if (google.category !== venueData.category) return null;
  }
  const sameCat = google.category === (venueData.category || 'other');
  const sameSub = (google.subcategory || null) === (venueData.subcategory || null);
  if (sameCat && sameSub && venueData.categorySource === 'google') return null;
  return {
    category: google.category,
    subcategory: google.subcategory || null,
    categorySource: 'google',
    categoryConfidence: google.confidence,
    categoryBefore: venueData.category || 'other',
    categoryClassifiedAt: new Date().toISOString()
  };
}

function firstNonEmptyArray(...candidates) {
  return candidates.find(c => Array.isArray(c) && c.length > 0) || undefined;
}

module.exports = {
  deriveCategory,
  refineCategory,
  classifyFromGoogle,
  googleReclassification,
  categoryUpgradeForOther,
  categoryFromApplePoi,
  APPLE_POI_TO_CATEGORY,
  ALL_CATEGORIES,
  AUTO_CATEGORIES
};
