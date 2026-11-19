// backend/services/activityFeedOverlay.js
//
// A feed row stores the circle's name (and, for circle rows, its cover) and
// the reacting people's names as they were when the row was written. The
// feed shows them as they are NOW (Wes, 2026-10-31: "stored in the db and
// pulled from one place"): these pure helpers lay the live circle and user
// records over the stored copies. A stored value stays only when the circle
// or account is gone. Response shape unchanged.
const { withCurrentUser } = require('./userLookup');
const { firstPhotoUrl, venuePhotoUrl } = require('./placePhoto');

const liveCircle = (circlesById, id) => {
  if (!id || !circlesById) return null;
  const c = circlesById.get(String(id));
  return c && !c.deletedAt ? c : null;
};

/**
 * The row with its circle's current name: circleName on any row about a
 * circle (its circleId, or the target of a circle row), and for circle rows
 * (targetType 'circle') also targetName and the cover, which every circle row
 * carries as metadata.placePhoto (services/activity/circles.js). Place rows
 * keep their own photo — their placePhoto is the place's, not the circle's.
 * Returns a NEW object; the row as stored when the circle is gone. Pure.
 * @param {object} activity  stored row
 * @param {Map<string, object>} circlesById  live circle docs (raw data)
 */
function withCurrentCircle(activity, circlesById) {
  if (!activity) return activity;
  const isCircleRow = activity.targetType === 'circle';
  const circle = liveCircle(circlesById, isCircleRow ? activity.targetId : activity.circleId);
  if (!circle) return activity;
  const out = { ...activity };
  if (circle.name) {
    out.circleName = circle.name;
    if (isCircleRow) out.targetName = circle.name;
  }
  if (isCircleRow && circle.coverImage) {
    out.metadata = { ...(activity.metadata || {}), placePhoto: circle.coverImage };
  }
  return out;
}

/**
 * Reaction summaries ({ emoji, count, users: [{ id, displayName, profilePicture }] })
 * with each person's current name and photo. Returns NEW arrays. Pure.
 * @param {Array} summaries
 * @param {Map} users  from userLookup.fetchUsersById
 */
function withCurrentReactors(summaries, users) {
  if (!Array.isArray(summaries) || !users || users.size === 0) return summaries;
  return summaries.map((s) => ({
    ...s,
    users: (s.users || []).map((u) => withCurrentUser(u, users, { id: 'id', name: 'displayName', photo: 'profilePicture' }))
  }));
}

const finite = (n) => typeof n === 'number' && Number.isFinite(n);

/** A venue record's pin: `location.coordinates` is [lng, lat] (GlobalPlace); older shapes are tolerated. */
function venueCoordinates(venue) {
  const loc = venue && venue.location;
  if (!loc) return null;
  let lat, lng;
  if (Array.isArray(loc.coordinates) && loc.coordinates.length >= 2) [lng, lat] = loc.coordinates;
  else if (finite(loc.latitude) && finite(loc.longitude)) ({ latitude: lat, longitude: lng } = loc);
  else if (finite(loc._latitude) && finite(loc._longitude)) { lat = loc._latitude; lng = loc._longitude; }
  if (!finite(lat) || !finite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180 || (lat === 0 && lng === 0)) return null;
  return { latitude: lat, longitude: lng };
}

/** The save or venue a place row is about, from the maps `venueFillFor` built. */
function venueOf(activity, { savesById, venuesById } = {}) {
  if (!activity || activity.targetType === 'circle') return { save: null, venue: null };
  const m = activity.metadata || {};
  const saveId = m.placeId || (activity.targetType === 'place' ? activity.targetId : null);
  const save = (saveId && savesById && savesById.get(String(saveId))) || null;
  const venueId = m.globalPlaceId || (save && save.globalPlaceId) || null;
  const venue = (venueId && venuesById && venuesById.get(String(venueId))) || null;
  return { save, venue };
}

/** True when the row is about a place and lacks a picture or a pin: the rows worth a venue read. */
function wantsVenueFill(activity) {
  if (!activity || activity.targetType === 'circle') return false;
  const m = activity.metadata || {};
  const aboutPlace = activity.targetType === 'place' || activity.targetType === 'global_place' || m.placeId || m.globalPlaceId;
  if (!aboutPlace) return false;
  return !m.placePhoto || !finite(m.latitude) || !finite(m.longitude) || !m.placeCategory;
}

/**
 * A place row with its picture and pin as the venue record has them NOW
 * (Wes, 2026-11-19: every activity gets a full card): the save's own photo,
 * else the venue's cover, fills a missing placePhoto; the venue's location
 * fills missing latitude/longitude; its category a missing placeCategory.
 * Stored values are never overwritten. Returns a NEW object only when
 * something was filled. Pure.
 */
function withCurrentVenue(activity, maps) {
  if (!wantsVenueFill(activity)) return activity;
  const { save, venue } = venueOf(activity, maps);
  if (!save && !venue) return activity;
  const m = activity.metadata || {};
  const fill = {};
  if (!m.placePhoto) {
    const photo = (save && firstPhotoUrl(save.photos)) || venuePhotoUrl(venue);
    if (photo) fill.placePhoto = photo;
  }
  if (!finite(m.latitude) || !finite(m.longitude)) {
    const pin = venueCoordinates(venue) || venueCoordinates(save);
    if (pin) { fill.latitude = pin.latitude; fill.longitude = pin.longitude; }
  }
  if (!m.placeCategory) {
    const category = (venue && venue.category) || (save && save.category) || null;
    if (category) fill.placeCategory = category;
  }
  if (Object.keys(fill).length === 0) return activity;
  return { ...activity, metadata: { ...m, ...fill } };
}

module.exports = { withCurrentCircle, withCurrentReactors, withCurrentVenue, wantsVenueFill, venueCoordinates };
