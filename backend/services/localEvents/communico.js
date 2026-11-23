// Libraries on Communico (LA County Library, …): the JSON list the
// library's own events page reads, at <host>/eeventcaldata.
const { fetchJson } = require('./cache');
const { SERVICE_PROGRAM, NOT_AN_OUTING, libraryEvent } = require('./libraryCommon');

const HEADERS = { 'User-Agent': 'Mozilla/5.0 (compatible; FavCircles/1.0; +https://favcircles.com)' };
const DAY_MS = 86400000;

/** The list → library events (in-person programs at a branch we can place). */
function normalizeCommunico(payload, feed, { fromDay, toDay }) {
  const rows = Array.isArray(payload) ? payload : [];
  // An event's `location` is its branch's own name
  const branches = new Map((feed.branches || []).map((b) => [b.name.toLowerCase(), b]));
  return rows.map((raw) => {
    if (!raw || !raw.id || !raw.title || !raw.event_start) return null;
    if (raw.event_type !== 'INPERSON' || raw.venue_type === 'external' || String(raw.private_event) === '1') return null;
    // `changed` marks a cancelled or moved program
    if (raw.changed && String(raw.changed) !== '0') return null;
    // The subtitle names the series ("LEAP Support Group")
    if (SERVICE_PROGRAM.test(`${raw.title} ${raw.sub_title || ''}`) || NOT_AN_OUTING.test(raw.title)) return null;
    const [date, time] = String(raw.event_start).split(' ');
    // Midnight starts are all-day items listed with a time
    if (!time || time === '00:00:00') return null;
    if (date < fromDay || date > toDay) return null;
    const branch = branches.get(String(raw.location || '').trim().toLowerCase());
    if (!branch) return null;
    const cost = String(raw.registration_cost || '').trim();
    const event = libraryEvent({
      feed,
      id: raw.id,
      name: raw.title,
      description: raw.description,
      date,
      time,
      branch,
      imageUrl: raw.event_image && feed.imageBase ? `${feed.imageBase}${encodeURIComponent(raw.event_image)}` : null,
      url: raw.url || `https://${feed.host}/event/${raw.id}`,
      isFree: !cost || /^(0|0\.00)$/.test(cost)
    });
    // A weekly program is one outing: keep the nearest branch's
    return { ...event, seriesId: raw.recurring_id && raw.recurring_id !== '0' ? `cm_${raw.recurring_id}` : null };
  }).filter(Boolean);
}

async function loadCommunico(feed, window) {
  const days = Math.round((Date.parse(window.toDay) - Date.parse(window.fromDay)) / DAY_MS) + 1;
  const req = JSON.stringify({ private: false, date: window.fromDay, days, locations: [], ages: [], types: [] });
  const payload = await fetchJson(`https://${feed.host}/eeventcaldata?${new URLSearchParams({ event_type: '0', req })}`,
    { headers: HEADERS, label: feed.name, timeoutMs: 8000 });
  if (!Array.isArray(payload)) return null;
  return normalizeCommunico(payload, feed, window);
}

module.exports = { loadCommunico, normalizeCommunico };
