// Libraries on Springshare LibCal (Phoenix, Monmouth County, …): the public
// list endpoint the library's own calendar page reads.
const { fetchJson } = require('./cache');
const { SERVICE_PROGRAM, NOT_AN_OUTING, matchBranch, libraryEvent } = require('./libraryCommon');

const PAGE_SIZE = 100;
const MAX_PAGES = 4;
const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (compatible; FavCircles/1.0; +https://favcircles.com)',
  'X-Requested-With': 'XMLHttpRequest'
};

/** One list page → library events (programs we can place, in the window). */
function normalizeLibcal(payload, feed, { fromDay, toDay }) {
  const results = Array.isArray(payload?.results) ? payload.results : [];
  return results.map((raw) => {
    if (!raw || !raw.id || !raw.title || !raw.startdt) return null;
    if (String(raw.all_day) === 'True' || String(raw.online_event) === 'True') return null;
    if (SERVICE_PROGRAM.test(raw.title) || NOT_AN_OUTING.test(raw.title)) return null;
    const [date, time] = String(raw.startdt).split(' ');
    // Midnight starts are all-day items listed with a time
    if (!time || time === '00:00:00') return null;
    if (date < fromDay || date > toDay) return null;
    // The location names the branch (or a room in one); the title only when
    // there's no location ("Century" would match "21st Century Skills")
    const place = `${raw.location || ''} ${raw.campus || ''}`.trim();
    const branch = place ? matchBranch(place, feed.branches) : matchBranch(raw.title, feed.branches);
    if (!branch) return null;
    const cost = String(raw.registration_cost || '').trim();
    return libraryEvent({
      feed,
      id: raw.id,
      name: raw.title,
      description: raw.description,
      date,
      time: time || '00:00:00',
      branch,
      imageUrl: raw.featured_image || null,
      url: raw.url || `https://${feed.host}/event/${raw.id}`,
      isFree: !cost || /^(0|0\.00|\$0|free)$/i.test(cost)
    });
  }).filter(Boolean);
}

async function loadLibcal(feed, window) {
  const pageOf = (page) => fetchJson(`https://${feed.host}/ajax/calendar/list?${new URLSearchParams({
    c: String(feed.calendarId), date: '0000-00-00', perpage: String(PAGE_SIZE), page: String(page),
    audience: '', cats: '', camps: '', inc: '0'
  })}`, { headers: HEADERS, label: feed.name, timeoutMs: 6000 });
  const events = [];
  for (let page = 1; page <= MAX_PAGES; page += 1) {
    const payload = await pageOf(page);
    if (!payload) return page === 1 ? null : events;
    events.push(...normalizeLibcal(payload, feed, window));
    const results = payload.results || [];
    // Upcoming events come soonest first: stop once past the window
    const last = results[results.length - 1];
    if (results.length < PAGE_SIZE || (last && String(last.startdt).slice(0, 10) > window.toDay)) break;
  }
  return events;
}

module.exports = { loadLibcal, normalizeLibcal };
