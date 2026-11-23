// Libraries on LibraryMarket's LibraryCalendar (Bossier Parish, …): the
// site's own JSON feed, at <host>/events/feed/json?start=&end=.
const { fetchJson } = require('./cache');
const { SERVICE_PROGRAM, NOT_AN_OUTING, matchBranch, libraryEvent } = require('./libraryCommon');

const HEADERS = { 'User-Agent': 'Mozilla/5.0 (compatible; FavCircles/1.0; +https://favcircles.com)' };

/** The feed → library events (public programs at one branch we can place). */
function normalizeLibraryMarket(payload, feed, { fromDay, toDay }) {
  const rows = Array.isArray(payload) ? payload : [];
  return rows.map((raw) => {
    if (!raw || !raw.id || !raw.title || !raw.start_date) return null;
    if (raw.public === false || raw.published === false) return null;
    // Online programs, and ones away from a branch (no map point for them)
    if (raw.online_address || raw.offsite_address) return null;
    if (/\bcancel+ed\b/i.test(raw.title)) return null;
    if (SERVICE_PROGRAM.test(raw.title) || NOT_AN_OUTING.test(raw.title)) return null;
    const [date, time] = String(raw.start_date).split(' ');
    if (!time || time === '00:00:00') return null;
    if (date < fromDay || date > toDay) return null;
    // "Every branch" rows are closures and system-wide notices
    const names = raw.branch && typeof raw.branch === 'object' ? Object.values(raw.branch) : [];
    if (names.length !== 1) return null;
    const branch = matchBranch(names[0], feed.branches);
    if (!branch) return null;
    return libraryEvent({
      feed,
      id: raw.id,
      name: raw.title,
      description: raw.description,
      date,
      time,
      branch,
      imageUrl: raw.image || null,
      url: raw.url || `https://${feed.host}/events`,
      timeZone: raw.timezone || feed.timeZone
    });
  }).filter(Boolean);
}

async function loadLibraryMarket(feed, window) {
  const payload = await fetchJson(`https://${feed.host}/events/feed/json?${new URLSearchParams({
    start: window.fromDay, end: window.toDay
  })}`, { headers: HEADERS, label: feed.name, timeoutMs: 8000 });
  if (!Array.isArray(payload)) return null;
  return normalizeLibraryMarket(payload, feed, window);
}

module.exports = { loadLibraryMarket, normalizeLibraryMarket };
