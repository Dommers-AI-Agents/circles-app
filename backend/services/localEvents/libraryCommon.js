// What every library calendar adapter shares: text clean-up, the filter
// for help sessions, branch matching and local-time → UTC.

const stripHtml = (html) => String(html || '')
  .replace(/<[^>]+>/g, ' ')
  .replace(/&nbsp;/g, ' ')
  .replace(/&amp;/g, '&')
  .replace(/&#0?39;|&rsquo;|&lsquo;/g, "'")
  .replace(/&quot;|&ldquo;|&rdquo;/g, '"')
  .replace(/&ndash;|&mdash;/g, '-')
  .replace(/&lt;/g, '<')
  .replace(/&gt;/g, '>')
  .replace(/\s+/g, ' ')
  .trim();

// Help sessions are services, not outings: they stay on the library's own
// calendar
const SERVICE_PROGRAM = /\b(job|résumé|resume|tutor|tutoring|legal|assistance|application|support group|support for|ESL|learning english|citizenship|GED|tax help|medicaid|insurance|drop-in session|welcomeclt|tutores|apoyo|tecnolog[ií]a|career services|employment|arizona@ ?work|phxworks|information table|get connected|property tax|tax relief|tech help|tech mentor|computer and tech|one-to-one|ESOL|resource navigation|blood drive|legalworks|recovery support|civics for)\b/i;
// Exhibits and displays are up all day: nothing to show up for
const NOT_AN_OUTING = /^(on display|exhibit|display:)|\bstorywalk\b/i;

/** The branch an event is at, from words in its location (or title). */
function matchBranch(text, branches = []) {
  const haystack = String(text || '').toLowerCase();
  if (!haystack) return null;
  // Longest names first: "West Long Branch" before "Long Branch"
  const ordered = [...branches].sort((a, b) =>
    Math.max(...b.match.map((m) => m.length)) - Math.max(...a.match.map((m) => m.length)));
  return ordered.find((branch) => branch.match.some((word) => haystack.includes(word.toLowerCase()))) || null;
}

/** "2026-10-17" + "19:00:00" in `timeZone` → ISO UTC. */
function zonedToUtc(date, time, timeZone) {
  const [y, mo, d] = date.split('-').map(Number);
  const [h, mi] = String(time || '00:00').split(':').map(Number);
  const guess = Date.UTC(y, mo - 1, d, h, mi);
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
    timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit'
  }).formatToParts(new Date(guess)).map((p) => [p.type, p.value]));
  const asLocal = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute);
  return new Date(guess - (asLocal - guess)).toISOString();
}

/** "YYYY-MM-DD" for `date` in `timeZone`. */
const dayKey = (date, timeZone) =>
  new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);

/** The shared event shape for a library program. */
function libraryEvent({ feed, id, name, description, date, time, branch, imageUrl, url, isFree = true, timeZone }) {
  const clean = stripHtml(description);
  return {
    id: `lib_${feed.libraryId || feed.host}_${id}`,
    seriesId: null,
    source: 'library',
    sourceName: feed.name,
    name: stripHtml(name),
    message: clean ? clean.slice(0, 280) : null,
    startLocalDate: date,
    startLocalTime: time,
    startUtc: zonedToUtc(date, time, timeZone || feed.timeZone),
    venueName: branch?.name ? (/library/i.test(branch.name) ? branch.name : `${branch.name} Library`) : feed.name,
    venueAddress: null,
    city: null,
    lat: branch?.lat ?? null,
    lng: branch?.lng ?? null,
    category: 'Library',
    imageUrl: imageUrl || null,
    url,
    priceMin: null,
    priceMax: null,
    currency: null,
    isFree: isFree && !/ticketed/i.test(clean) ? true : null
  };
}

module.exports = { stripHtml, SERVICE_PROGRAM, NOT_AN_OUTING, matchBranch, zonedToUtc, dayKey, libraryEvent };
