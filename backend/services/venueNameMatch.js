// When two differently-worded names are the same venue.
//
// The resolver's name matcher needs EXACT normalized names within 150 m, so
// "Genesis/Atlantic Health Club" and "Genesis Health Clubs - The Atlantic
// Club Manasquan" — same door, pins 5 m apart, no Google id on either —
// became two venues, splitting Sal's photos and check-ins (2026-09-30).
//
// This is the looser, tightly-fenced rule for venues without a Google id:
//   - pins within SIMILAR_NAME_RADIUS_METERS (25 m — the same building)
//   - at least MIN_SHARED distinctive words in common, where a distinctive
//     word is what's left after dropping filler ("the", "and") and generic
//     venue words ("club", "health", "cafe"), with plurals folded
// "Pizza Hut" next to "Pizza Palace" shares only "pizza" (generic here too)
// and stays two venues. Two different Google ids are always two venues —
// callers check that before asking.
//
// Pure; the resolver and the audit script share it.

const SIMILAR_NAME_RADIUS_METERS = 25;
const MIN_SHARED = 2;

const STOPWORDS = new Set([
  'the', 'and', 'of', 'at', 'in', 'on', 'by', 'for', 'a', 'an', 'to', 'n', 'co', 'inc', 'llc'
]);

// Words that name a KIND of place, not a particular one.
const GENERIC = new Set([
  'club', 'health', 'fitness', 'gym', 'center', 'centre', 'cafe', 'coffee', 'bar', 'grill',
  'restaurant', 'kitchen', 'pizza', 'pizzeria', 'deli', 'market', 'shop', 'store', 'house',
  'bakery', 'pub', 'tavern', 'hotel', 'inn', 'spa', 'salon', 'studio', 'park', 'school',
  'church', 'bank', 'pharmacy', 'clinic', 'medical', 'dental', 'office', 'service', 'services',
  'supercenter', 'supermarket', 'express', 'plaza', 'mall', 'station', 'hall', 'room',
  'lounge', 'diner', 'eatery', 'bistro', 'brewery', 'winery', 'company', 'group', 'new',
  'nj', 'ny', 'usa', 'us'
]);

// "clubs" → "club", but never "genesis" → "genesi", "bus", "glass"
const singular = (word) => (word.length > 3 && /[^siu]s$/.test(word) ? word.slice(0, -1) : word);

/** The distinctive words of a venue name, as a Set. */
const distinctiveWords = (name) => new Set(
  String(name || '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean)
    .map(singular)
    .filter((w) => w.length >= 3 && !STOPWORDS.has(w) && !GENERIC.has(w))
);

const sharedWords = (a, b) => {
  const left = distinctiveWords(a);
  return [...distinctiveWords(b)].filter((w) => left.has(w));
};

/** Same venue by name alone (distance is the caller's other half). */
const namesLikelySameVenue = (a, b) => sharedWords(a, b).length >= MIN_SHARED;

/** Two Google ids that differ mean two venues, whatever the names say. */
const googleIdsConflict = (a, b) => !!(a && b && a !== b);

module.exports = {
  SIMILAR_NAME_RADIUS_METERS,
  MIN_SHARED,
  distinctiveWords,
  sharedWords,
  namesLikelySameVenue,
  googleIdsConflict
};
