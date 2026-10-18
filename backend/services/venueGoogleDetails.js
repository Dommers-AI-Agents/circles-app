// Fills a venue's shared contact details and hours from Google (Wes,
// 2026-10-18: "I don't want to have to refresh, I want the global place
// details to be accurate"). Google is the truth for a Google-matched venue;
// only EMPTY fields are filled, so a store owner's or admin's correction is
// never overwritten. One Place Details call (Basic + Contact, ~2¢), and
// `googleData.detailsCheckedAt` makes it once per venue — Google having
// nothing is an answer too, not a reason to ask again.
const admin = require('firebase-admin');
const { getFirestore } = require('../config/firebase');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');

const DETAILS_URL = 'https://maps.googleapis.com/maps/api/place/details/json';
const pad = (t) => `${String(t).slice(0, 2)}:${String(t).slice(2, 4)}`;

function clock12(hhmm) {
  const h = parseInt(String(hhmm).slice(0, 2), 10);
  const m = String(hhmm).slice(2, 4);
  return `${h % 12 === 0 ? 12 : h % 12}${m !== '00' ? `:${m}` : ''} ${h < 12 ? 'AM' : 'PM'}`;
}

/**
 * Google opening_hours.periods → the app's OpeningHour rows, one per day:
 * { day, open, close, isClosed } for one stretch, { day, hours } for a split
 * day ("11 AM–2 PM, 5–9 PM"), closed days marked closed. Null if none.
 */
function hoursFromGoogle(periods) {
  if (!Array.isArray(periods) || periods.length === 0) return null;
  if (periods.length === 1 && periods[0].open && !periods[0].close) {
    return [0, 1, 2, 3, 4, 5, 6].map((day) => ({ day, open: '00:00', close: '23:59', isClosed: false }));
  }
  const byDay = new Map();
  for (const p of periods) {
    if (!p.open || !Number.isInteger(p.open.day)) continue;
    if (!byDay.has(p.open.day)) byDay.set(p.open.day, []);
    byDay.get(p.open.day).push(p);
  }
  return [0, 1, 2, 3, 4, 5, 6].map((day) => {
    const spans = (byDay.get(day) || []).sort((a, b) => String(a.open.time).localeCompare(String(b.open.time)));
    if (spans.length === 0) return { day, open: null, close: null, isClosed: true };
    if (spans.length === 1) {
      return { day, open: pad(spans[0].open.time), close: spans[0].close ? pad(spans[0].close.time) : '23:59', isClosed: false };
    }
    return { day, hours: spans.map((s) => `${clock12(s.open.time)}–${s.close ? clock12(s.close.time) : 'late'}`).join(', ') };
  });
}

async function fetchDetails(googlePlaceId, key = process.env.GOOGLE_MAPS_API_KEY) {
  if (!key || !googlePlaceId) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(`${DETAILS_URL}?${new URLSearchParams({
      place_id: googlePlaceId, fields: 'formatted_phone_number,website,opening_hours,business_status', language: 'en', key
    })}`, { signal: controller.signal });
    if (!res.ok) return null;
    const body = await res.json();
    if (body.status === 'NOT_FOUND' || body.status === 'INVALID_REQUEST') return { gone: true };
    return body.result || null;
  } finally {
    clearTimeout(timer);
  }
}

/** Which of the venue's shared details are empty. */
function missingFields(venue) {
  const g = (venue && venue.googleData) || {};
  return {
    website: !g.website,
    phone: !g.phone,
    openingHours: !(Array.isArray(g.openingHours) && g.openingHours.length > 0)
  };
}

/**
 * Fill a Google-matched venue's empty website / phone / hours. Never throws;
 * returns what it filled. `force` re-asks even if checked before (the
 * one-time backfill passes nothing; tests pass a fake fetch).
 */
async function fillVenue(globalPlaceId, { force = false, fetcher = fetchDetails } = {}) {
  const db = getFirestore();
  const ref = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(String(globalPlaceId));
  try {
    const doc = await ref.get();
    if (!doc.exists) return { skipped: 'missing' };
    const venue = doc.data();
    if (venue.deletedAt || venue.mergedInto || !venue.googlePlaceId) return { skipped: 'not_google' };
    if (!force && venue.googleData && venue.googleData.detailsCheckedAt) return { skipped: 'checked' };
    const missing = missingFields(venue);
    if (!missing.website && !missing.phone && !missing.openingHours) return { skipped: 'complete' };

    const result = await fetcher(venue.googlePlaceId);
    if (!result) return { skipped: 'google_error' };   // try again another time
    const now = new Date().toISOString();
    const update = { 'googleData.detailsCheckedAt': now, updatedAt: now };
    const filled = [];
    if (!result.gone) {
      if (missing.website && result.website) { update['googleData.website'] = result.website; filled.push('website'); }
      if (missing.phone && result.formatted_phone_number) { update['googleData.phone'] = result.formatted_phone_number; filled.push('phone'); }
      const hours = missing.openingHours ? hoursFromGoogle(result.opening_hours && result.opening_hours.periods) : null;
      if (hours) { update['googleData.openingHours'] = hours; filled.push('openingHours'); }
    }
    await ref.update(update);
    return { filled };
  } catch (error) {
    console.error(`[venue-details] fill failed for ${globalPlaceId}: ${error.message}`);
    return { skipped: 'error' };
  }
}

/** Fire-and-forget form for save paths: a save never waits on Google. */
function fillVenueInBackground(globalPlaceId, venueData) {
  if (!globalPlaceId || !venueData || !venueData.googlePlaceId) return;
  if (venueData.googleData && venueData.googleData.detailsCheckedAt) return;
  const m = missingFields(venueData);
  if (!m.website && !m.phone && !m.openingHours) return;
  fillVenue(globalPlaceId).catch(() => {});
}

module.exports = { fillVenue, fillVenueInBackground, hoursFromGoogle, missingFields, fetchDetails };
