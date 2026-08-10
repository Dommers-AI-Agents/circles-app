// The iOS add-place flow synthesizes a placeholder description for
// Apple-sourced venues ("A dining establishment in Tucson\nPhone: …") because
// Apple Maps offers no editorial text. Builds since 2026-07-31 swap in
// Google's editorial summary when one arrives, but older builds still send
// the template — and once stored it blocks scripts/backfill-editorial-summaries.js,
// which only fills EMPTY descriptions. This module recognizes the exact
// synthesized phrases (the fixed category strings from AddPlaceViewController /
// PlaceSearchViewController) so server-side writers can drop them.
//
// Contact lines ("Phone: …" / "Website: …") are deliberately preserved: for
// Apple-only venues the description is the only place that data lives, and the
// iOS place detail view recovers phone/website from description text.

const TEMPLATE_PHRASES = [
  'A dining establishment',
  'A coffee shop or casual dining spot',
  'A bar or nightlife venue',
  'Accommodation services',
  'Retail shopping location',
  'Vehicle fueling or charging station',
  'Parking facility',
  'Car rental services',
  'Laundry services',
  'Postal services',
  'Banking and financial services',
  'Pharmacy and medication services',
  'Healthcare services',
  'Emergency services',
  'Public transportation',
  'Educational institution',
  'Library and information services',
  'Movie theater entertainment',
  'Museum and cultural exhibits',
  'Outdoor recreation area',
  'Theater and performing arts venue',
  'Animal exhibits and attractions',
  'Amusement park and rides',
  'Sports and event venue',
  'Marina and boating services',
  'Mini golf recreation',
  'Historical landmark or attraction',
  'Local business or point of interest'
];

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// "<phrase>", optionally " in X" / " located in X", optionally ", near Y and Z".
// The locality is capped at 4 words (it comes from placemark.locality — a city
// name) so real prose that merely opens with a template phrase isn't swallowed.
const LOCALITY = "[\\w.'-]+(?:\\s+[\\w.'-]+){0,3}";
const TEMPLATE_LINE = new RegExp(
  `^(?:${TEMPLATE_PHRASES.map(escapeRegex).join('|')})` +
  `(?:\\s+(?:located\\s+)?in\\s+${LOCALITY})?(?:,\\s*near\\s+.+)?$`,
  'i'
);
// Standalone location filler when Apple had no POI category
const LOCATED_LINE = /^Located\s+(?:in|near)\s+.+$/i;
const CONTACT_LINE = /^(?:Phone|Website):\s*/i;

const isSynthesizedLine = (line) => TEMPLATE_LINE.test(line) || LOCATED_LINE.test(line);

// Description with synthesized placeholder prose removed; null if nothing
// remains. Text with no synthesized lines passes through completely untouched.
const sanitizeVenueDescription = (text) => {
  if (!text || typeof text !== 'string') return text || null;
  const lines = text.split('\n');
  const kept = lines.filter((line) => !isSynthesizedLine(line.trim()));
  if (kept.length === lines.length) return text;
  return kept.join('\n').trim() || null;
};

// True when the description contains prose a human (or Google) actually wrote —
// i.e. at least one line that is neither synthesized template nor a contact line.
const hasRealProse = (text) => {
  if (!text || typeof text !== 'string') return false;
  return text.split('\n').some((raw) => {
    const line = raw.trim();
    return line && !isSynthesizedLine(line) && !CONTACT_LINE.test(line);
  });
};

// The "Phone: …"/"Website: …" lines of a description, for callers replacing
// template text who need to carry the contact data forward.
const extractContactLines = (text) => {
  if (!text || typeof text !== 'string') return [];
  return text.split('\n').map((l) => l.trim()).filter((l) => CONTACT_LINE.test(l));
};

module.exports = { sanitizeVenueDescription, hasRealProse, extractContactLines, isSynthesizedLine };
