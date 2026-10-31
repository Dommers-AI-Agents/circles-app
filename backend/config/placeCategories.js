// backend/config/placeCategories.js
//
// THE list of place categories (Wes, 2026-10-31: one source for every data
// point). It used to be written out in four files; validation, Google/Apple
// derivation, the LLM classifier and the details editor all read it from here.
// The iOS app's PlaceCategory enum must carry the same raw values.
//
// home and work are only ever chosen by the person, never inferred.
const PLACE_CATEGORY_IDS = Object.freeze([
  'restaurant', 'cafe', 'bar', 'hotel', 'retail', 'service', 'attraction',
  'entertainment', 'healthcare', 'fitness', 'education', 'outdoor', 'transport',
  'finance', 'home', 'work', 'other'
]);

const USER_ONLY_CATEGORIES = Object.freeze(['home', 'work']);
const AUTO_CATEGORY_IDS = Object.freeze(PLACE_CATEGORY_IDS.filter((c) => !USER_ONLY_CATEGORIES.includes(c)));

const isPlaceCategory = (c) => PLACE_CATEGORY_IDS.includes(c);

module.exports = { PLACE_CATEGORY_IDS, AUTO_CATEGORY_IDS, USER_ONLY_CATEGORIES, isPlaceCategory };
