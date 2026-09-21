// backend/services/quotesService.js
//
// Quotes delivered at the times the user picked — one a day or several — in
// the categories they picked, to their phone and, if they asked, their inbox.
//
// Delivery follows dailySummaryService: an hourly Cloud Scheduler tick, each
// user gated on their OWN local clock, and a per-day document id so a retried
// run cannot send twice.
//
//   quotes/{id}                  the catalog (text, author, categories[])
//   quoteSends/{userId_YYYY-MM-DD_HHmm}  proof that slot's quote went out
//
// Preferences live on the user doc under `quotePrefs`, next to the other
// notification settings, because that is what the scheduler has to scan.
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { localClock, localDateKey } = require('../utils/localClock');
const { nowIso } = require('../utils/ids');
const { escapeHtml } = require('../utils/text');
const notificationService = require('./notificationService');
const emailService = require('./emailService');

class QuoteError extends ServiceError {}

// The categories a user can choose between. Kept here rather than derived from
// the catalog so the picker is stable even when the catalog is thin.
const CATEGORIES = [
  { id: 'motivation', label: 'Motivation', blurb: 'Get after the day' },
  { id: 'calm', label: 'Calm', blurb: 'Slow down, breathe' },
  { id: 'gratitude', label: 'Gratitude', blurb: 'Notice what is good' },
  { id: 'humor', label: 'Humor', blurb: 'Not everything is serious' },
  { id: 'resilience', label: 'Resilience', blurb: 'Keep going' },
  { id: 'wisdom', label: 'Wisdom', blurb: 'Older and wiser than us' },
  { id: 'love', label: 'Love & friendship', blurb: 'The people around you' },
  { id: 'adventure', label: 'Adventure', blurb: 'Go somewhere' }
];
const CATEGORY_IDS = new Set(CATEGORIES.map((c) => c.id));

const DEFAULT_PREFS = {
  enabled: false,
  categories: ['motivation'],
  // `times` is the list; `time` mirrors its first entry for clients that
  // predate multiple slots.
  times: ['08:00'],
  time: '08:00',
  email: false
};
const MAX_TIMES = 6;
/** The tick runs hourly; a user's slot is "now" inside this window. */
const RUN_WINDOW_MINUTES = 60;
/** Don't repeat a quote until this many have gone by. */
const RECENT_MEMORY = 60;
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
const BATCH_SIZE = 25;


/** A stored pref may predate `times`; derive it from `time` then. */
function normalizeTimes(prefs) {
  const list = Array.isArray(prefs.times) && prefs.times.length ? prefs.times : [prefs.time || DEFAULT_PREFS.time];
  return [...new Set(list.map((t) => String(t)))].filter((t) => TIME_RE.test(t)).sort().slice(0, MAX_TIMES);
}

function normalizePrefs(input = {}, existing = {}) {
  const base = { ...DEFAULT_PREFS, ...existing };
  const out = { ...base };
  if (input.enabled !== undefined) out.enabled = input.enabled === true;
  if (input.email !== undefined) out.email = input.email === true;
  if (input.times !== undefined) {
    if (!Array.isArray(input.times)) throw new QuoteError(400, 'bad_time', 'Times must be a list.');
    const times = [...new Set(input.times.map((t) => String(t).trim()))].sort();
    if (!times.length) throw new QuoteError(400, 'bad_time', 'Pick at least one time.');
    if (times.length > MAX_TIMES) throw new QuoteError(400, 'bad_time', `Up to ${MAX_TIMES} times a day.`);
    if (times.some((t) => !TIME_RE.test(t))) throw new QuoteError(400, 'bad_time', 'Pick a time like 08:00.');
    out.times = times;
  } else if (input.time !== undefined) {
    const time = String(input.time).trim();
    if (!TIME_RE.test(time)) throw new QuoteError(400, 'bad_time', 'Pick a time like 08:00.');
    out.times = [time];
  }
  out.times = normalizeTimes(out);
  out.time = out.times[0];
  if (input.categories !== undefined) {
    if (!Array.isArray(input.categories)) throw new QuoteError(400, 'bad_categories', 'Categories must be a list.');
    const picked = [...new Set(input.categories.map((c) => String(c).trim()).filter((c) => CATEGORY_IDS.has(c)))];
    // An empty pick would mean "no quotes at all" by accident; treat it as
    // "surprise me" instead, which is what someone clearing the list means.
    out.categories = picked.length ? picked : CATEGORIES.map((c) => c.id);
  }
  return out;
}

class QuotesService {
  constructor(db = getFirestore()) {
    this.db = db;
  }

  get users() { return this.db.collection(COLLECTIONS.USERS); }
  get quotes() { return this.db.collection(COLLECTIONS.QUOTES); }
  get sends() { return this.db.collection(COLLECTIONS.QUOTE_SENDS); }

  static sendId(userId, dateKey, slot) { return `${userId}_${dateKey}_${String(slot).replace(':', '')}`; }

  prefsOf(user) {
    const prefs = { ...DEFAULT_PREFS, ...(user.quotePrefs || {}) };
    prefs.times = normalizeTimes(prefs);
    prefs.time = prefs.times[0];
    return prefs;
  }

  // MARK: - Preferences

  async getSettings(userId, { now = new Date() } = {}) {
    const doc = await this.users.doc(userId).get();
    if (!doc.exists) throw new QuoteError(404, 'no_user', 'User not found.');
    const user = { id: doc.id, ...doc.data() };
    const prefs = this.prefsOf(user);
    const today = await this.todaysQuote(userId, user, now);
    return { prefs, categories: CATEGORIES, today };
  }

  async updateSettings(userId, input) {
    const doc = await this.users.doc(userId).get();
    if (!doc.exists) throw new QuoteError(404, 'no_user', 'User not found.');
    const user = doc.data();
    const prefs = normalizePrefs(input, user.quotePrefs || {});
    await this.users.doc(userId).update({ quotePrefs: prefs, updatedAt: nowIso() });
    return { prefs, categories: CATEGORIES };
  }

  // What the widget shows: the latest of today's slots that has gone out.
  // One batched read of the day's possible ids; no query, no index.
  async todaysQuote(userId, user, now = new Date()) {
    const zone = (user.notificationPreferences || {}).timezone;
    const dateKey = localDateKey(zone, now);
    const refs = this.prefsOf(user).times.map((slot) => this.sends.doc(QuotesService.sendId(userId, dateKey, slot)));
    const docs = await this.db.getAll(...refs);
    const sent = docs.filter((d) => d.exists).map((d) => d.data()).sort((a, b) => (a.sentAt < b.sentAt ? 1 : -1));
    if (!sent.length) return null;
    const d = sent[0];
    // `id` lets the card open the reel on the quote they were actually sent,
    // the same place the push lands.
    return { id: d.quoteId || null, text: d.text, author: d.author || null, category: d.category || null,
             sentAt: d.sentAt || null, slot: d.slot || null };
  }

  // MARK: - Catalog

  /** Every enabled quote — one read per run, not one per user. */
  async loadEnabledQuotes() {
    const snap = await this.quotes.where('enabled', '==', true).get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  }

  async loadCatalog(categories, enabledQuotes = null) {
    const all = enabledQuotes || await this.loadEnabledQuotes();
    const wanted = new Set(categories || []);
    const matching = all.filter((q) => (q.categories || []).some((c) => wanted.has(c)));
    // Falling back to the whole catalog beats sending nothing because a
    // category happens to be empty today.
    return matching.length ? matching : all;
  }

  /// The reel behind a tapped "quote of the day" push: the quote they were
  /// sent, then the ones most like it, then everything else.
  ///
  /// "Most like it" = how many categories overlap, so a quote filed under both
  /// calm and resilience ranks above one sharing only calm. Ties break on id
  /// so the order is stable between opens — a feed that reshuffles under you
  /// on a re-tap reads as broken.
  ///
  /// The whole enabled catalog is read and ranked in memory. That is the right
  /// shape at this size (tens of quotes): an `array-contains-any` query plus a
  /// cursor would need a composite index and still could not order by overlap.
  /// Revisit past a few thousand.
  rankFeed(all, startId) {
    const enabled = (all || []).filter((q) => q && q.id);
    const start = enabled.find((q) => q.id === startId) || null;
    const startCategories = new Set(start ? (start.categories || []) : []);
    const rest = enabled.filter((q) => q.id !== (start && start.id));
    const overlap = (q) => (q.categories || []).filter((c) => startCategories.has(c)).length;
    rest.sort((a, b) => {
      const diff = overlap(b) - overlap(a);
      return diff !== 0 ? diff : String(a.id).localeCompare(String(b.id));
    });
    return start ? [start, ...rest] : rest;
  }

  /// `startId` missing or unknown (a quote retired since the push) still
  /// returns a readable reel rather than an error — the person tapped a
  /// notification and deserves something.
  async feed(startId = null, { limit = 40 } = {}) {
    const all = await this.loadEnabledQuotes();
    const ranked = this.rankFeed(all, startId);
    const capped = ranked.slice(0, Math.max(1, Math.min(limit, 100)));
    return {
      start: startId && ranked.length && ranked[0].id === startId ? startId : null,
      categories: CATEGORIES,
      quotes: capped.map((q) => ({
        id: q.id,
        text: q.text,
        author: q.author || null,
        categories: q.categories || [],
        // Optional background on the quote or who said it. Absent on most
        // rows; the reel simply doesn't show the line then.
        context: q.context || null
      }))
    };
  }

  // Least-recently-sent wins, so a small catalog still feels varied and a
  // freshly added quote goes out soon rather than waiting for a shuffle.
  pickQuote(catalog, recentIds) {
    if (!catalog.length) return null;
    const unseen = catalog.filter((q) => !recentIds.includes(q.id));
    const pool = unseen.length ? unseen : catalog;
    return pool[Math.floor(Math.random() * pool.length)];
  }

  // MARK: - Delivery

  /** The user's slot ("HH:mm") whose hour contains `now`, in their zone. */
  dueSlot(user, now) {
    const prefs = this.prefsOf(user);
    if (!prefs.enabled) return null;
    const zone = (user.notificationPreferences || {}).timezone;
    const clock = localClock(zone, now);
    return prefs.times.find((slot) => {
      const [h, m] = slot.split(':').map((n) => parseInt(n, 10));
      const delta = clock.minutes - (h * 60 + m);
      return delta >= 0 && delta < RUN_WINDOW_MINUTES;
    }) || null;
  }

  isUsersQuoteHour(user, now) { return this.dueSlot(user, now) !== null; }

  async loadCandidates(userId) {
    if (userId) {
      const doc = await this.users.doc(userId).get();
      return doc.exists ? [{ id: doc.id, ...doc.data() }] : [];
    }
    // Equality on a nested field: no composite index.
    const snap = await this.users.where('quotePrefs.enabled', '==', true).get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  }

  async runDue({ now = new Date(), userId = null, force = false, dryRun = false } = {}) {
    const users = await this.loadCandidates(userId);
    const due = force ? users : users.filter((u) => this.dueSlot(u, now) !== null);
    const results = { candidates: users.length, due: due.length, sent: 0, emailed: 0, skipped: 0, dryRun };
    const enabledQuotes = due.length ? await this.loadEnabledQuotes() : [];

    for (let i = 0; i < due.length; i += BATCH_SIZE) {
      const batch = due.slice(i, i + BATCH_SIZE);
      await Promise.all(batch.map(async (user) => {
        try {
          const outcome = await this.sendToUser(user, { now, dryRun, enabledQuotes });
          if (outcome.sent) results.sent += 1;
          else results.skipped += 1;
          if (outcome.emailed) results.emailed += 1;
        } catch (error) {
          console.error(`💬 quote failed for ${user.id}:`, error.message);
          results.skipped += 1;
        }
      }));
    }
    return results;
  }

  async sendToUser(user, { now = new Date(), dryRun = false, enabledQuotes = null } = {}) {
    const prefs = this.prefsOf(user);
    const zone = (user.notificationPreferences || {}).timezone;
    const dateKey = localDateKey(zone, now);
    const slot = this.dueSlot(user, now) || prefs.times[0];
    const sendRef = this.sends.doc(QuotesService.sendId(user.id, dateKey, slot));

    const catalog = await this.loadCatalog(prefs.categories, enabledQuotes);
    if (!catalog.length) return { sent: false, reason: 'empty_catalog' };

    const recent = (user.quoteRecentIds || []).slice(-RECENT_MEMORY);
    const quote = this.pickQuote(catalog, recent);
    if (!quote) return { sent: false, reason: 'no_quote' };

    if (dryRun) return { sent: false, reason: 'dry_run', preview: { userId: user.id, text: quote.text } };

    // The slot's document id is the lock: a retried run loses the race and
    // stops here rather than sending that slot twice.
    try {
      await sendRef.create({
        userId: user.id, quoteId: quote.id, text: quote.text, author: quote.author || null,
        category: (quote.categories || [])[0] || null, dateKey, slot, sentAt: nowIso(), emailed: false
      });
    } catch (error) {
      return { sent: false, reason: 'already_sent' };
    }

    const body = quote.author ? `${quote.text} — ${quote.author}` : quote.text;
    await notificationService.sendToUser(user.id, {
      type: 'daily_quote',
      title: 'A line for you',
      body,
      data: { type: 'daily_quote', quoteId: quote.id }
    });

    let emailed = false;
    if (prefs.email && user.email) {
      try {
        await emailService.sendEmail({
          to: user.email,
          subject: 'A line for you',
          html: this.emailHtml(quote, user),
          text: body
        });
        emailed = true;
      } catch (error) {
        // The push already landed; a failed email must not look like a failed day.
        console.error(`💬 quote email failed for ${user.id}:`, error.message);
      }
    }

    await Promise.all([
      sendRef.update({ emailed }),
      this.users.doc(user.id).update({
        quoteRecentIds: [...recent, quote.id].slice(-RECENT_MEMORY),
        updatedAt: nowIso()
      })
    ]);
    return { sent: true, emailed, quoteId: quote.id };
  }

  emailHtml(quote, user) {
    const name = (user.displayName || '').split(' ')[0];
    return `<!doctype html><html><body style="margin:0;padding:32px 16px;background:#f5f7fa;font-family:-apple-system,'Segoe UI',Arial,sans-serif">
  <div style="max-width:520px;margin:0 auto;background:#fff;border-radius:16px;padding:36px 32px;box-shadow:0 8px 24px rgba(14,42,71,.08)">
    <p style="margin:0 0 20px;font-size:13px;letter-spacing:2px;text-transform:uppercase;color:#4FD1C5;font-weight:700">A line for you</p>
    <p style="margin:0;font-size:22px;line-height:1.45;color:#0E2A47">${escapeHtml(quote.text)}</p>
    ${quote.author ? `<p style="margin:16px 0 0;font-size:15px;color:#64748b">— ${escapeHtml(quote.author)}</p>` : ''}
    <p style="margin:32px 0 0;font-size:13px;color:#94a3b8">${name ? `Have a good one, ${escapeHtml(name)}.` : 'Have a good one.'}
      <br>You can change the times, the topics, or turn this off in the Quotes widget.</p>
  </div>
</body></html>`;
  }
}


module.exports = new QuotesService();
module.exports.QuotesService = QuotesService;
module.exports.QuoteError = QuoteError;
module.exports.CATEGORIES = CATEGORIES;
module.exports.DEFAULT_PREFS = DEFAULT_PREFS;
module.exports.normalizePrefs = normalizePrefs;
