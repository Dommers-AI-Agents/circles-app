// Events posted by stores on FavCircles: an announcement with an `event`
// ({ startsAt, endsAt, localDate, localTime, isFree }). Same loyalty gate as
// the rest of the Locals tab (listLiveVenues).
const geofire = require('geofire-common');
const { listLiveVenues } = require('../liveVenues');
const rewardService = require('../rewardService');

const RADIUS_KM = 40;
const WINDOW_MS = 14 * 86400000;

function storeEventsFrom(venues, lat, lng, now = new Date()) {
  const events = [];
  for (const venue of venues) {
    if (venue.isVirtual) continue;
    const loc = venue.location;
    if (!loc || !Number.isFinite(loc.lat) || !Number.isFinite(loc.lng)) continue;
    if (geofire.distanceBetween([lat, lng], [loc.lat, loc.lng]) > RADIUS_KM) continue;
    for (const announcement of rewardService.activeAnnouncements(venue)) {
      const event = announcement.event;
      if (!event || !event.startsAt || !event.localDate) continue;
      const start = new Date(event.startsAt).getTime();
      const end = event.endsAt ? new Date(event.endsAt).getTime() : start + 4 * 3600000;
      if (!Number.isFinite(start) || end < now.getTime() || start > now.getTime() + WINDOW_MS) continue;
      events.push({
        id: `store_${venue.venueId}_${announcement.announcementId}`,
        source: 'store',
        sourceName: venue.venueName,
        name: announcement.title,
        message: announcement.message || null,
        startLocalDate: event.localDate,
        startLocalTime: event.localTime || null,
        startUtc: event.startsAt,
        venueName: venue.placeName || venue.venueName,
        venueAddress: venue.placeAddress || null,
        city: null,
        lat: loc.lat,
        lng: loc.lng,
        category: null,
        imageUrl: null,
        // Always a link: the 2026-10-15 builds require one on every event
        url: venue.globalPlaceId
          ? `https://api.favcircles.com/place/${encodeURIComponent(venue.globalPlaceId)}`
          : 'https://api.favcircles.com/app/open',
        priceMin: event.isFree === true ? 0 : null,
        priceMax: null,
        currency: null,
        isFree: event.isFree === true ? true : (event.isFree === false ? false : null),
        venueId: venue.venueId,
        globalPlaceId: venue.globalPlaceId || null,
        googlePlaceId: venue.googlePlaceId || null
      });
    }
  }
  return events;
}

// The Locals feed is public and cached per location, so a store flagged
// isTestStore (a demo store) is left out for everyone here.
async function eventsNear(lat, lng, { now = new Date() } = {}) {
  return storeEventsFrom((await listLiveVenues()).filter((venue) => !venue.isTestStore), lat, lng, now);
}

module.exports = { eventsNear, storeEventsFrom };
