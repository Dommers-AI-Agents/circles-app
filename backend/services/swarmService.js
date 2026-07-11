// Swarm (Foursquare) import: OAuth code exchange + fetching the user's
// saved lists and check-ins via the v2 consumer API, normalized to the
// same payload shape the file-based importers produce.
//
// The v2 checkins/lists/users endpoints remain on Foursquare's free tier;
// requests authenticate with the oauth_token query param and require a
// version date (v=YYYYMMDD).

const axios = require('axios');
const { categoryFromFoursquareNames } = require('./importCategoryMapping');

const API_BASE = 'https://api.foursquare.com/v2';
const API_VERSION = '20250101';
const PAGE_SIZE = 250; // v2 maximum for checkins
const MAX_CHECKIN_PAGES = 20; // 5,000 check-ins is plenty of history
const MAX_UNIQUE_CHECKIN_VENUES = 500;

const clientId = () => process.env.FOURSQUARE_CLIENT_ID;
const clientSecret = () => process.env.FOURSQUARE_CLIENT_SECRET;
const redirectUri = () => process.env.FOURSQUARE_REDIRECT_URI;

const isConfigured = () => Boolean(clientId() && clientSecret() && redirectUri());

function authorizationUrl(state) {
  const params = new URLSearchParams({
    client_id: clientId(),
    response_type: 'code',
    redirect_uri: redirectUri(),
    state
  });
  return `https://foursquare.com/oauth2/authenticate?${params.toString()}`;
}

async function exchangeCodeForToken(code) {
  const params = new URLSearchParams({
    client_id: clientId(),
    client_secret: clientSecret(),
    grant_type: 'authorization_code',
    redirect_uri: redirectUri(),
    code
  });
  const response = await axios.get(`https://foursquare.com/oauth2/access_token?${params.toString()}`);
  if (!response.data || !response.data.access_token) {
    throw new Error('Foursquare token exchange returned no access token');
  }
  return response.data.access_token;
}

async function v2Get(path, accessToken, extraParams = {}) {
  const response = await axios.get(`${API_BASE}${path}`, {
    params: { oauth_token: accessToken, v: API_VERSION, ...extraParams }
  });
  return response.data.response;
}

/** Convert a Foursquare venue object to an import place candidate. */
function venueToPlace(venue, notes) {
  if (!venue || !venue.name) return null;
  const location = venue.location || {};
  const lat = typeof location.lat === 'number' ? location.lat : null;
  const lng = typeof location.lng === 'number' ? location.lng : null;
  const categoryNames = (venue.categories || []).map(c => c && c.name).filter(Boolean);

  return {
    name: venue.name,
    address: location.formattedAddress ? location.formattedAddress.join(', ')
      : [location.address, location.city, location.country].filter(Boolean).join(', ') || null,
    lat,
    lng,
    category: categoryFromFoursquareNames(categoryNames),
    notes: notes || null,
    tags: [],
    sourceExternalId: venue.id ? `fsq:${venue.id}` : null,
    sourceUrl: venue.id ? `https://foursquare.com/v/${venue.id}` : null
  };
}

/** The user's created lists (includes the built-in "Saved Places"). */
async function fetchLists(accessToken) {
  const listsResponse = await v2Get('/users/self/lists', accessToken, { group: 'created' });
  const groups = (listsResponse.lists && listsResponse.lists.groups) || [];
  const listSummaries = groups.flatMap(group => group.items || []);

  const lists = [];
  for (const summary of listSummaries) {
    if (!summary || !summary.id) continue;

    // Page through the list's items
    const places = [];
    let offset = 0;
    const total = summary.listItems ? summary.listItems.count : null;
    while (true) {
      const detail = await v2Get(`/lists/${summary.id}`, accessToken, {
        limit: 200,
        offset
      });
      const items = (detail.list && detail.list.listItems && detail.list.listItems.items) || [];
      for (const item of items) {
        const place = venueToPlace(item.venue, item.text);
        if (place) places.push(place);
      }
      offset += items.length;
      if (items.length === 0 || (total !== null && offset >= total)) break;
    }

    if (places.length > 0) {
      lists.push({ name: summary.name || 'Swarm List', places });
    }
  }
  return lists;
}

/** Check-in history collapsed to unique venues, most recent first. */
async function fetchCheckinVenues(accessToken) {
  const seenVenueIds = new Set();
  const places = [];
  let truncated = false;

  for (let page = 0; page < MAX_CHECKIN_PAGES; page++) {
    const checkinsResponse = await v2Get('/users/self/checkins', accessToken, {
      limit: PAGE_SIZE,
      offset: page * PAGE_SIZE,
      sort: 'newestfirst'
    });
    const items = (checkinsResponse.checkins && checkinsResponse.checkins.items) || [];
    for (const checkin of items) {
      const venue = checkin.venue;
      if (!venue || !venue.id || seenVenueIds.has(venue.id)) continue;
      seenVenueIds.add(venue.id);
      if (places.length >= MAX_UNIQUE_CHECKIN_VENUES) {
        truncated = true;
        break;
      }
      const place = venueToPlace(venue, null);
      if (place) places.push(place);
    }
    if (items.length < PAGE_SIZE || truncated) break;
  }

  return { places, truncated };
}

/**
 * Fetch everything importable from the user's Swarm account as the
 * normalized import payload: { source: 'swarm', lists: [...] }.
 */
async function fetchNormalizedPayload(accessToken, { includeCheckins = false } = {}) {
  const lists = await fetchLists(accessToken);
  let checkinsTruncated = false;

  if (includeCheckins) {
    const { places, truncated } = await fetchCheckinVenues(accessToken);
    checkinsTruncated = truncated;
    if (places.length > 0) {
      lists.push({ name: 'Swarm Check-ins', places });
    }
  }

  return { source: 'swarm', lists, checkinsTruncated };
}

module.exports = {
  isConfigured,
  authorizationUrl,
  exchangeCodeForToken,
  fetchNormalizedPayload
};
