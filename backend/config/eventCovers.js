// Cover images for event circles, one per emoji the Events widget offers
// (Wes, 2026-10-17: "use the image they selected for the category, like the
// Bus, or Ring"). Google Noto emoji (Apache 2.0) on a gradient, hosted on
// favcircles.com (repo: website/favcircles.com/images/event-covers/).
const BASE = 'https://favcircles.com/images/event-covers';

// Codepoints without the variation selector, so "🏖️" and "🏖" both match
const COVERS = ['1f68c', '1f389', '1f37e', '1f382', '1f48d', '1f3d6', '26f3', '1f3c8', '1f3a4', '1f973'];
const DEFAULT = '1f389';

const codepoints = (emoji) => Array.from(String(emoji || ''))
  .map((ch) => ch.codePointAt(0))
  .filter((cp) => cp !== 0xfe0f && cp !== 0x200d)
  .map((cp) => cp.toString(16))
  .join('-');

/** The cover for an event's emoji; the party one for anything else. */
function eventCoverUrl(emoji) {
  const key = codepoints(emoji);
  return `${BASE}/event-${COVERS.includes(key) ? key : DEFAULT}.jpg`;
}

/** Whether a circle's cover is one of these (so an emoji change may swap it). */
const isEventCover = (url) => typeof url === 'string' && url.startsWith(`${BASE}/`);

module.exports = { eventCoverUrl, isEventCover };
