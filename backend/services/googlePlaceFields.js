// backend/services/googlePlaceFields.js — every Place Details field we can
// take from a call we already make, at no extra cost (Wes, 2026-10-29: "we
// should always use all of the free query data from Google").
//
// How the legacy Place Details price works: each call pays for the request,
// then once per data group it touches. Basic fields are free on every call;
// Contact (phone, website, hours) and Atmosphere (rating, price, dine-in,
// serves_*) are each charged once, however many of their fields we ask for.
// Every details call we make already asks for website (Contact) and rating
// (Atmosphere), so asking for the rest of those groups and every Basic field
// costs nothing more. Before this, each call site picked a few fields and
// dropped the rest: the save path paid for `types` and threw them away after
// an address check, so categories came from the phone's guess instead.
//
// Left out on purpose: `reviews` (bulky, and Google's terms require showing
// them with attribution, which we don't), `icon`/`adr_address` (no use).
// Never add a NEW call for any of this: only widen calls already made.

const BASIC = [
  'address_components', 'business_status', 'formatted_address', 'geometry', 'name',
  'photos', 'place_id', 'plus_code', 'types', 'url', 'utc_offset', 'vicinity',
  'wheelchair_accessible_entrance'
];
const CONTACT = ['formatted_phone_number', 'international_phone_number', 'opening_hours', 'website'];
const ATMOSPHERE = [
  'curbside_pickup', 'delivery', 'dine_in', 'editorial_summary', 'price_level', 'rating',
  'reservable', 'serves_beer', 'serves_breakfast', 'serves_brunch', 'serves_dinner',
  'serves_lunch', 'serves_vegetarian_food', 'serves_wine', 'takeout', 'user_ratings_total'
];

/** For a details call that already bills Contact + Atmosphere (all of ours do). */
const DETAILS_ALL = [...BASIC, ...CONTACT, ...ATMOSPHERE];

const bool = (v) => (v === true || v === false ? v : null);

/**
 * The signals we keep from a details result, beyond the contact/rating
 * fields each caller already stores. Null/[] where Google said nothing.
 */
function googleSignals(details = {}) {
  if (!details || typeof details !== 'object') return null;
  return {
    googleTypes: Array.isArray(details.types) ? details.types : [],
    serves: {
      breakfast: bool(details.serves_breakfast),
      brunch: bool(details.serves_brunch),
      lunch: bool(details.serves_lunch),
      dinner: bool(details.serves_dinner),
      beer: bool(details.serves_beer),
      wine: bool(details.serves_wine),
      vegetarian: bool(details.serves_vegetarian_food)
    },
    dineIn: bool(details.dine_in),
    businessStatus: details.business_status || null,
    wheelchairAccessibleEntrance: bool(details.wheelchair_accessible_entrance),
    mapsUrl: details.url || null,
    // Legacy Place Details names it `utc_offset` (minutes); `utc_offset_minutes`
    // is refused as a field name and fails the whole call (rev 00954, 2026-10-29)
    utcOffsetMinutes: Number.isFinite(details.utc_offset) ? details.utc_offset
      : (Number.isFinite(details.utc_offset_minutes) ? details.utc_offset_minutes : null)
  };
}

/** Firestore update keys for a globalPlaces doc from googleSignals(). */
function venueSignalUpdates(signals) {
  if (!signals) return {};
  const out = {};
  if (signals.googleTypes.length) out.googleTypes = signals.googleTypes;
  out['googleData.serves'] = signals.serves;
  if (signals.dineIn !== null) out['googleData.dineIn'] = signals.dineIn;
  if (signals.businessStatus) out['googleData.businessStatus'] = signals.businessStatus;
  if (signals.wheelchairAccessibleEntrance !== null) out['googleData.wheelchairAccessibleEntrance'] = signals.wheelchairAccessibleEntrance;
  if (signals.mapsUrl) out['googleData.mapsUrl'] = signals.mapsUrl;
  if (signals.utcOffsetMinutes !== null) out['googleData.utcOffsetMinutes'] = signals.utcOffsetMinutes;
  return out;
}

module.exports = { BASIC, CONTACT, ATMOSPHERE, DETAILS_ALL, googleSignals, venueSignalUpdates };
