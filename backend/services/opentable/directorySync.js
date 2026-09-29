// backend/services/opentable/directorySync.js
//
// Mirrors OpenTable's restaurant directory into Firestore
// (opentableRestaurants/{rid}) so the Reserve link can find a place's exact
// OpenTable page without calling OpenTable per tap. OpenTable refreshes the
// directory nightly and asks partners to sync at least daily.
//
// Only restaurants whose content changed are written (a hash of the fields
// we keep), so a typical daily run is a full read and a small write.
// Restaurants that drop out of the directory are marked inactive, never
// deleted, so a flaky run can't erase the table.
const crypto = require('crypto');
const { geohashForLocation } = require('geofire-common');
const { getFirestore } = require('../../config/firebase');
const client = require('./client');
const { nameKey } = require('./matcher');

const COLLECTION = 'opentableRestaurants';
const PAGE_SIZE = 1000;
const db = () => getFirestore();

const toHttps = (url) => (url ? String(url).replace(/^http:\/\//i, 'https://') : null);

/** Pure: the fields we keep for one directory item, or null if unusable. */
const toRecord = (item) => {
  const lat = parseFloat(item.latitude);
  const lng = parseFloat(item.longitude);
  if (!item.rid || !Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) return null;
  const sizes = (item.profile_photo && item.profile_photo.sizes) || {};
  const photo = (sizes['wide-large'] || sizes.large || sizes.medium || {}).url || null;
  const record = {
    rid: item.rid,
    name: item.name || '',
    nameKey: nameKey(item.name),
    address: [item.address, item.address2].filter(Boolean).join(', '),
    city: item.city || null,
    state: Array.isArray(item.state) ? item.state[0] : (item.state || null),
    country: item.country || null,
    postalCode: item.postal_code != null ? String(item.postal_code) : null,
    phone: item.phone_number || null,
    lat,
    lng,
    geohash: geohashForLocation([lat, lng]),
    profileUrl: toHttps(item.natural_profile_url || item.profile_url),
    reservationUrl: toHttps(item.natural_reservation_url || item.reservation_url),
    photo,
    category: item.category || null,
    priceQuartile: item.price_quartile || null
  };
  record.hash = crypto.createHash('sha1').update(JSON.stringify(record)).digest('hex');
  return record;
};

/**
 * Runs one sync. `maxPages` limits a trial run; a limited run never marks
 * anything inactive (it didn't see the whole directory).
 */
const run = async ({ country = 'US', maxPages = null, log = console.log } = {}) => {
  const started = Date.now();
  const existing = new Map();
  const snap = await db().collection(COLLECTION).select('hash', 'active').get();
  snap.forEach((d) => existing.set(d.id, d.data()));

  const writer = db().bulkWriter();
  const seen = new Set();
  const summary = { env: client.env(), country, pages: 0, received: 0, written: 0, unchanged: 0, skipped: 0, deactivated: 0, total: null };
  const syncedAt = new Date().toISOString();

  for (let offset = 0; ; offset += PAGE_SIZE) {
    if (maxPages && summary.pages >= maxPages) break;
    const page = await client.fetchDirectoryPage({ offset, limit: PAGE_SIZE, country });
    summary.pages++;
    summary.total = page.total_items;
    const items = page.items || [];
    for (const item of items) {
      summary.received++;
      const record = toRecord(item);
      if (!record) { summary.skipped++; continue; }
      const id = String(record.rid);
      seen.add(id);
      const prior = existing.get(id);
      if (prior && prior.hash === record.hash && prior.active !== false) { summary.unchanged++; continue; }
      writer.set(db().collection(COLLECTION).doc(id), { ...record, active: true, syncedAt }, { merge: true });
      summary.written++;
    }
    if (items.length < PAGE_SIZE || offset + PAGE_SIZE >= page.total_items) break;
  }

  // Only a complete run may retire restaurants it didn't see
  const complete = !maxPages && summary.received > 0 && summary.total && summary.received >= summary.total * 0.9;
  if (complete) {
    for (const [id, data] of existing) {
      if (!seen.has(id) && data.active !== false) {
        writer.set(db().collection(COLLECTION).doc(id), { active: false, inactiveSince: syncedAt }, { merge: true });
        summary.deactivated++;
      }
    }
  }
  await writer.close();
  summary.complete = Boolean(complete);
  summary.seconds = Math.round((Date.now() - started) / 1000);
  log(`🍽️ OpenTable directory sync (${summary.env}): ${JSON.stringify(summary)}`);
  return summary;
};

module.exports = { COLLECTION, toRecord, run };

if (require.main === module) {
  // node services/opentable/directorySync.js [--pages=N]
  require('../../config/firebase').initializeFirebase();
  const pagesArg = process.argv.find((a) => a.startsWith('--pages='));
  run({ maxPages: pagesArg ? parseInt(pagesArg.split('=')[1], 10) : null })
    .then(() => process.exit(0))
    .catch((e) => { console.error(e.message, e.details || ''); process.exit(1); });
}
