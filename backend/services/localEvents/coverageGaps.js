// Where the Local tab shows no library programs. Each ~20 km cell is counted
// per day with why and who asked (no user ids: just the cell, counts and
// when). A weekly report names the busiest cells so the next library systems
// to add follow real users (Wes, 2026-10-15).
//
// Why (2026-11-23: the first reports listed Charlotte, Phoenix and Chicago,
// which have calendars, and called a lifetime count "last 30 days"):
//   none  — no library system's area covers the spot
//   far   — a system's area covers it, but no branch within 10 miles has a program
//   empty — a system covers it and its calendar came back with nothing
// Who: `tab` (someone opened Local there) or `letter` (the weekly letter was
// written for someone who lives there).
const geofire = require('geofire-common');
const firebase = require('../../config/firebase');
const { LIBRARY_REACH_M } = require('./libraryCommon');

const COLLECTION = 'localCoverageGaps';
const THROTTLE_MS = 6 * 60 * 60 * 1000;
const WINDOW_DAYS = 30;
const MAX_LISTED = 15;
const REASONS = ['none', 'far', 'empty'];
const SOURCES = ['tab', 'letter'];
const recent = new Map();

/**
 * Count a miss in this cell. Tab opens count once per cell and reason per
 * instance per 6 h (one person refreshing isn't six); every letter counts,
 * since each is one person who lives there.
 */
function recordGap(lat, lng, { reason = 'none', source = 'tab', now = Date.now() } = {}) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return;
  if (!REASONS.includes(reason) || !SOURCES.includes(source)) return;
  const cell = geofire.geohashForLocation([lat, lng], 4);
  const key = `${cell}|${source}|${reason}`;
  if (source === 'tab') {
    if (recent.has(key) && now - recent.get(key) < THROTTLE_MS) return;
    recent.set(key, now);
  }
  const [cLat, cLng] = [Math.round(lat * 10) / 10, Math.round(lng * 10) / 10];
  const day = new Date(now).toISOString().slice(0, 10);
  try {
    firebase.getFirestore().collection(COLLECTION).doc(cell).set({
      cell,
      lat: cLat,
      lng: cLng,
      days: { [day]: { [`${source}_${reason}`]: firebase.FieldValue.increment(1) } },
      lastSeenAt: new Date(now).toISOString()
    }, { merge: true }).catch((err) => console.warn('[localEvents] coverage gap write failed:', err.message));
  } catch (err) {
    console.warn('[localEvents] coverage gap write failed:', err.message);
  }
}

/** "Casa Grande, AZ (Pinal County)" from an OpenStreetMap address (pure). */
function formatPlace(address = {}) {
  const a = address;
  const town = a.city || a.town || a.village || a.municipality || a.hamlet || a.suburb || a.county;
  const country = String(a.country_code || '').toLowerCase() || null;
  if (country !== 'us' && country !== 'ca') {
    return { place: [town, a.state || a.province, a.country].filter(Boolean).join(', ') || null, country };
  }
  const region = String(a['ISO3166-2-lvl4'] || '').split('-')[1] || a.state || a.province;
  const base = [town, region].filter(Boolean).join(', ') || null;
  const county = a.county && a.county !== town ? ` (${a.county})` : '';
  return { place: base ? `${base}${county}` : null, country };
}

/** Name and country for a cell, once (OpenStreetMap; kept on the doc). */
async function placeName(lat, lng) {
  try {
    const res = await fetch(`https://nominatim.openstreetmap.org/reverse?${new URLSearchParams({
      lat: String(lat), lon: String(lng), format: 'json', zoom: '10', 'accept-language': 'en'
    })}`, { headers: { 'User-Agent': 'FavCircles/1.0 (wesley@favcircles.com)' } });
    if (!res.ok) return null;
    const named = formatPlace((await res.json()).address || {});
    return named.place ? named : null;
  } catch {
    return null;
  }
}

/** A cell's counts inside the window, by who asked and why (pure). */
function countsFor(row, { now = Date.now(), windowDays = WINDOW_DAYS } = {}) {
  const since = new Date(now - windowDays * 86400000).toISOString().slice(0, 10);
  const counts = { tab: 0, letter: 0, none: 0, far: 0, empty: 0, emptyDays: 0, total: 0 };
  for (const [day, byKey] of Object.entries(row.days || {})) {
    if (day < since) continue;
    let emptyToday = false;
    for (const [key, n] of Object.entries(byKey || {})) {
      const [source, reason] = key.split('_');
      if (!SOURCES.includes(source) || !REASONS.includes(reason) || !Number.isFinite(n)) continue;
      counts[source] += n;
      counts[reason] += n;
      counts.total += n;
      if (reason === 'empty') emptyToday = true;
    }
    if (emptyToday) counts.emptyDays += 1;
  }
  // Rows from before per-day counts: one running total, letters included
  counts.earlier = row.days ? 0 : (row.opens || 0);
  return counts;
}

/** A branch of one of these systems is within reach of the cell (pure). */
const branchInReach = (row, feeds) => feeds.some((feed) => (feed.branches || []).some((branch) =>
  geofire.distanceBetween([row.lat, row.lng], [branch.lat, branch.lng]) * 1000 <= LIBRARY_REACH_M));

/**
 * Sort the window's cells into the report's sections (pure, tested).
 * `feedsNear(lat, lng)` → the library systems covering a spot today, so a
 * cell stops being a gap the moment its system is added.
 */
function classifyGaps(rows, { feedsNear, now = Date.now() } = {}) {
  const sections = { none: [], far: [], empty: [], abroad: [] };
  for (const row of rows) {
    const counts = countsFor(row, { now });
    const covering = feedsNear(row.lat, row.lng);
    const item = { ...row, counts, feeds: covering.map((feed) => feed.name) };
    if (!covering.length) {
      if (counts.total + counts.earlier === 0) continue;
      const abroad = row.country && row.country !== 'us' && row.country !== 'ca';
      sections[abroad ? 'abroad' : 'none'].push(item);
      continue;
    }
    // Rows from before reasons were kept: a gap when every system here lists
    // its branches and none is in reach. (BiblioCommons systems don't list
    // them: those rows wait for the next count, which says why.)
    const earlierFar = counts.earlier > 0 && covering.every((feed) => Array.isArray(feed.branches))
      && !branchInReach(row, covering);
    // A local system added since (a branch now in reach) closes the gap
    if ((counts.far > 0 && !branchInReach(row, covering)) || earlierFar) sections.far.push(item);
    // One empty answer is a timeout; the same cell on two days is a calendar to look at
    if (counts.emptyDays >= 2) sections.empty.push(item);
  }
  const busiest = (a, b) => (b.counts.tab - a.counts.tab) || (b.counts.total - a.counts.total) || (b.counts.earlier - a.counts.earlier);
  for (const list of Object.values(sections)) list.sort(busiest);
  return sections;
}

/** The window's cells, sorted into sections and named. */
async function topGaps({ now = Date.now(), feedsNear } = {}) {
  const db = firebase.getFirestore();
  const near = feedsNear || require('./library').feedsNear;
  const since = new Date(now - WINDOW_DAYS * 86400000).toISOString();
  const snap = await db.collection(COLLECTION).where('lastSeenAt', '>=', since).get();
  const sections = classifyGaps(snap.docs.map((doc) => doc.data()), { feedsNear: near, now });
  const shown = [...new Set(Object.values(sections).flatMap((list) => list.slice(0, MAX_LISTED)))];
  for (const row of shown) {
    // `country` came with the 2026-11-23 names: older rows are named again
    if (row.place && row.country) continue;
    const named = await placeName(row.lat, row.lng);
    if (named) {
      Object.assign(row, named);
      await db.collection(COLLECTION).doc(row.cell).set(named, { merge: true });
    }
    await new Promise((resolve) => setTimeout(resolve, 1100)); // OpenStreetMap: 1 request/s
  }
  // A row just learned to be abroad belongs in that section
  const stay = (row) => !row.country || row.country === 'us' || row.country === 'ca';
  sections.abroad.push(...sections.none.filter((row) => !stay(row)));
  sections.none = sections.none.filter(stay);
  return sections;
}

const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;
const nameOf = (row) => row.place || `near ${row.lat}, ${row.lng}`;

function countText({ counts }) {
  const parts = [];
  if (counts.tab) parts.push(plural(counts.tab, 'open'));
  if (counts.letter) parts.push(plural(counts.letter, 'letter'));
  if (!parts.length && counts.earlier) parts.push(`${counts.earlier} earlier`);
  return parts.join(', ');
}

function listed(rows, line) {
  const lines = rows.slice(0, MAX_LISTED).map((row, i) => `${i + 1}. ${line(row)}`);
  if (rows.length > MAX_LISTED) lines.push(`…and ${rows.length - MAX_LISTED} more`);
  return lines.join('\n');
}

/** The weekly email's subject and body; null when there's nothing to say. */
function buildReport(sections) {
  const { none = [], far = [], empty = [], abroad = [] } = sections || {};
  if (!none.length && !far.length && !empty.length) return null;
  const blocks = [];
  if (none.length) {
    blocks.push(`NO LIBRARY SYSTEM SET UP (${none.length})\n${listed(none, (row) => `${nameOf(row)}: ${countText(row)}`)}`);
  }
  if (far.length) {
    blocks.push(`NO BRANCH WITHIN 10 MILES (${far.length})\nThe nearest system's branches are too far; add the local library.\n${listed(far, (row) =>
      `${nameOf(row)}: ${row.counts.far ? plural(row.counts.far, 'time') : `${row.counts.earlier} earlier`}\n   nearest: ${row.feeds.join(', ')}`)}`);
  }
  if (empty.length) {
    blocks.push(`CALENDAR CAME BACK EMPTY ON 2+ DAYS (${empty.length})\n${listed(empty, (row) =>
      `${nameOf(row)}: ${plural(row.counts.emptyDays, 'day')}\n   check ${row.feeds.join(', ')}`)}`);
  }
  if (abroad.length) {
    blocks.push(`OUTSIDE THE US AND CANADA (${abroad.length})\n${listed(abroad, (row) => `${nameOf(row)}: ${countText(row)}`)}`);
  }
  const gaps = none.length + far.length;
  const title = gaps
    ? `Local tab: ${plural(gaps, 'place')} with no library programs in reach`
    : 'Local tab: library calendars to check';
  const body = [
    `Where the Local tab had no library programs in the last ${WINDOW_DAYS} days, busiest first.`,
    'open = Local was opened there (one per 6 hours). letter = a weekly letter written for someone who lives there. earlier = counted before 2026-11-23, when the two were mixed.',
    ...blocks,
    'Add a library system: backend/config/eventFeeds.js, or the lists in backend/tools/build-library-feeds.py.'
  ].join('\n\n');
  return { title, body, places: gaps };
}

module.exports = { recordGap, topGaps, classifyGaps, countsFor, formatPlace, buildReport, _recent: recent };
