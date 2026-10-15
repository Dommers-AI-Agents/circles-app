// Farmers markets from the USDA National Farmers Market Directory (public
// bulk download, no key). The whole directory (~7,000 markets) is copied
// into Firestore `farmersMarkets` with a geohash by syncUsdaMarkets() — the
// /api/tasks/farmers-markets-sync task, monthly — and read by geohash range.
// The directory has no days or hours, so these show as places, not events.
const geofire = require('geofire-common');
const { getFirestore } = require('../../config/firebase');

const COLLECTION = 'farmersMarkets';
const DOWNLOAD_URL = 'https://www.usdalocalfoodportal.com/api/download_by_directory/?directory=farmersmarket';
const RADIUS_M = 25 * 1609.344;
const MAX_MARKETS = 6;
// The portal refuses requests that don't look like its own page's
const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
  'X-Requested-With': 'XMLHttpRequest',
  Referer: 'https://www.usdalocalfoodportal.com/fe/datasharing/'
};

const clean = (value) => {
  const text = String(value ?? '').replace(/\s+/g, ' ').trim();
  return text && text !== 'null' ? text : null;
};

/** One directory row → a stored market; null without coordinates. */
function normalizeMarket(row) {
  const lat = parseFloat(row.location_y);
  const lng = parseFloat(row.location_x);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || !row.listing_id || !clean(row.listing_name)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180 || (lat === 0 && lng === 0)) return null;
  const fnap = String(row.FNAP || '');
  const methods = String(row.specialproductionmethods || '');
  return {
    id: String(row.listing_id),
    name: clean(row.listing_name),
    address: clean(row.location_address),
    directions: clean(row.location_desc),
    lat,
    lng,
    geohash: geofire.geohashForLocation([lat, lng]),
    acceptsSnap: /SNAP|EBT/i.test(fnap),
    organic: /Organic/i.test(methods),
    indoor: clean(row.location_indoor),
    updatedAt: clean(row.update_time)
  };
}

/** Download the directory and upsert every market. Returns counts. */
async function syncUsdaMarkets({ fetchImpl = fetch } = {}) {
  const res = await fetchImpl(DOWNLOAD_URL, { headers: HEADERS });
  if (!res.ok) throw new Error(`USDA download answered ${res.status}`);
  const rows = await res.json();
  if (!Array.isArray(rows) || rows.length < 1000) throw new Error(`USDA download looked wrong (${Array.isArray(rows) ? rows.length : typeof rows} rows)`);
  const markets = rows.map(normalizeMarket).filter(Boolean);
  const db = getFirestore();
  let written = 0;
  for (let i = 0; i < markets.length; i += 400) {
    const batch = db.batch();
    for (const market of markets.slice(i, i + 400)) {
      batch.set(db.collection(COLLECTION).doc(market.id), { ...market, syncedAt: new Date().toISOString() });
    }
    await batch.commit();
    written += Math.min(400, markets.length - i);
  }
  return { rows: rows.length, written };
}

/** The nearest markets within 25 miles, with the caller's distance. */
async function marketsNear(lat, lng) {
  const db = getFirestore();
  const bounds = geofire.geohashQueryBounds([lat, lng], RADIUS_M);
  const snapshots = await Promise.all(bounds.map(([start, end]) =>
    db.collection(COLLECTION).orderBy('geohash').startAt(start).endAt(end).limit(200).get()
  ));
  const seen = new Set();
  const markets = [];
  for (const snapshot of snapshots) {
    for (const doc of snapshot.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const m = doc.data();
      const meters = geofire.distanceBetween([lat, lng], [m.lat, m.lng]) * 1000;
      if (meters > RADIUS_M) continue;
      markets.push({
        id: m.id,
        name: m.name,
        address: m.address,
        directions: m.directions,
        lat: m.lat,
        lng: m.lng,
        distanceMeters: Math.round(meters),
        acceptsSnap: !!m.acceptsSnap,
        organic: !!m.organic
      });
    }
  }
  // The directory lists some markets twice (renamed, re-registered)
  const byName = new Map();
  for (const market of markets.sort((a, b) => a.distanceMeters - b.distanceMeters)) {
    const key = market.name.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (!byName.has(key)) byName.set(key, market);
  }
  return [...byName.values()].slice(0, MAX_MARKETS);
}

module.exports = { syncUsdaMarkets, marketsNear, normalizeMarket };
