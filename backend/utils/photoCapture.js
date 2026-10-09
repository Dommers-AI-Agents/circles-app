// Where and when a photo was taken, as the app read it off the file's own
// GPS/EXIF (Wes, 2026-10-09). Optional on every upload that carries it
// (event album photos, photo moments); anything that doesn't parse is
// dropped rather than failing the upload. Pure.
const PHOTO_TAKEN_EARLIEST = Date.parse('2000-01-01T00:00:00Z');
const PHOTO_TAKEN_FUTURE_SLACK_MS = 24 * 60 * 60 * 1000;

/** `{ lat, lng, takenAt }` — each null when missing or not credible. */
const parsePhotoCapture = (p, now = Date.now()) => {
  const b = p || {};
  let lat = Number(b.lat);
  let lng = Number(b.lng);
  const hasSpot = b.lat != null && b.lng != null && Number.isFinite(lat) && Number.isFinite(lng)
    && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);
  if (!hasSpot) { lat = null; lng = null; }
  let takenAt = null;
  if (typeof b.takenAt === 'string' && b.takenAt) {
    const t = Date.parse(b.takenAt);
    if (Number.isFinite(t) && t >= PHOTO_TAKEN_EARLIEST && t <= now + PHOTO_TAKEN_FUTURE_SLACK_MS) takenAt = new Date(t).toISOString();
  }
  return { lat, lng, takenAt };
};

/** Metres between two points (haversine). */
const distanceMeters = (aLat, aLng, bLat, bLng) => {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
};

// A photo counts as taken at a place within this far (the app's radius
// for attaching photos to a place)
const PHOTO_PLACE_RADIUS_M = 150;

module.exports = { parsePhotoCapture, distanceMeters, PHOTO_PLACE_RADIUS_M };
