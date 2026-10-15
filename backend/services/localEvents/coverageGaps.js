// Where the Local tab has no library calendar yet. Each ~20 km cell where
// someone opened Local outside every library system's area is counted
// (no user ids: just the cell, a count and when). A weekly report names the
// busiest cells so the next library systems to add follow real users
// (Wes, 2026-10-15).
const geofire = require('geofire-common');
const firebase = require('../../config/firebase');

const COLLECTION = 'localCoverageGaps';
const THROTTLE_MS = 6 * 60 * 60 * 1000;
const recent = new Map();

/** Count an open in this cell (at most once per cell per instance per 6 h). */
function recordGap(lat, lng, now = Date.now()) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
  const cell = geofire.geohashForLocation([lat, lng], 4);
  if (recent.has(cell) && now - recent.get(cell) < THROTTLE_MS) return;
  recent.set(cell, now);
  const [cLat, cLng] = [Math.round(lat * 10) / 10, Math.round(lng * 10) / 10];
  try {
    firebase.getFirestore().collection(COLLECTION).doc(cell).set({
      cell,
      lat: cLat,
      lng: cLng,
      opens: firebase.FieldValue.increment(1),
      lastSeenAt: new Date(now).toISOString()
    }, { merge: true }).catch((err) => console.warn('[localEvents] coverage gap write failed:', err.message));
  } catch (err) {
    console.warn('[localEvents] coverage gap write failed:', err.message);
  }
}

/** "Coolidge, Arizona" for a cell, once (OpenStreetMap; kept on the doc). */
async function placeName(lat, lng) {
  try {
    const res = await fetch(`https://nominatim.openstreetmap.org/reverse?${new URLSearchParams({
      lat: String(lat), lon: String(lng), format: 'json', zoom: '10'
    })}`, { headers: { 'User-Agent': 'FavCircles/1.0 (wesley@favcircles.com)' } });
    if (!res.ok) return null;
    const a = (await res.json()).address || {};
    const town = a.city || a.town || a.village || a.county || a.suburb;
    return [town, a.state || a.province].filter(Boolean).join(', ') || null;
  } catch {
    return null;
  }
}

/** The busiest uncovered cells seen in the last 30 days, named. */
async function topGaps({ limit = 15, now = Date.now() } = {}) {
  const db = firebase.getFirestore();
  const since = new Date(now - 30 * 86400000).toISOString();
  const snap = await db.collection(COLLECTION).where('lastSeenAt', '>=', since).get();
  const rows = snap.docs.map((doc) => doc.data()).sort((a, b) => (b.opens || 0) - (a.opens || 0)).slice(0, limit);
  for (const row of rows) {
    if (!row.place) {
      row.place = await placeName(row.lat, row.lng);
      if (row.place) await db.collection(COLLECTION).doc(row.cell).set({ place: row.place }, { merge: true });
      await new Promise((resolve) => setTimeout(resolve, 1100)); // OpenStreetMap: 1 request/s
    }
  }
  return rows;
}

/** The weekly email body; null when there's nothing to report. */
function reportText(rows) {
  if (!rows.length) return null;
  const lines = rows.map((r, i) =>
    `${i + 1}. ${r.place || `${r.lat}, ${r.lng}`} — ${r.opens} open${r.opens === 1 ? '' : 's'} (near ${r.lat}, ${r.lng})`);
  return `People opened the Local tab here with no library calendar set up (last 30 days, busiest first):\n\n${lines.join('\n')}\n\nAdd a library system: backend/config/eventFeeds.js, or the lists in backend/tools/build-library-feeds.py.`;
}

module.exports = { recordGap, topGaps, reportText, _recent: recent };
