// backend/services/quotesService.js
//
// A daily quote, delivered at the hour the user picked, in the categories they
// picked, to their phone and — if they asked for it — their inbox.
//
// Delivery follows dailySummaryService: an hourly Cloud Scheduler tick, each
// user gated on their OWN local clock, and a per-day document id so a retried
// run cannot send twice.
//
//   quotes/{id}                  the catalog (text, author, categories[])
//   quoteSends/{userId_YYYY-MM-DD}  proof today's quote went out
//
// Preferences live on the user doc under `quotePrefs`, next to the other
// notification settings, because that is what the scheduler has to scan.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { localClock } = require('../utils/localClock');
const notificationService = require('./notificationService');
const emailService = require('./emailService');

class QuoteError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

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
  time: '08:00',
  email: false
};
/** The tick runs hourly; a user's slot is "now" inside this window. */
const RUN_WINDOW_MINUTES = 60;
/** Don't repeat a quote until this many have gone by. */
const RECENT_MEMORY = 60;
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
const BATCH_SIZE = 25;

const nowIso = () => new Date().toISOString();

/** "2026-09-19" in the user's zone — the key that makes a day a day. */
function localDateKey(timeZone, now = new Date()) {
  const read = (zone) => {
    const parts = new Intl.DateTimeFormat('en-US', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(now);
    const get = (t) => parts.find((p) => p.type === t).value;
    return `${get('year')}-${get('month')}-${get('day')}`;
  };
  try { return read(timeZone || 'America/New_York'); } catch (e) { return read('America/New_York'); }
}

function normalizePrefs(input = {}, existing = {}) {
  const base = { ...DEFAULT_PREFS, ...existing };
  const out = { ...base };
  if (input.enabled !== undefined) out.enabled = input.enabled === true;
  if (input.email !== undefined) out.email = input.email === true;
  if (input.time !== undefined) {
    const time = String(input.time).trim();
    if (!TIME_RE.test(time)) throw new QuoteError(400, 'bad_time', 'Pick a time like 08:00.');
    out.time = time;
  }
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

  static sendId(userId, dateKey) { return `${userId}_${dateKey}`; }

  prefsOf(user) {
    return { ...DEFAULT_PREFS, ...(user.quotePrefs || {}) };
  }

  // MARK: - Preferences

  async getSettings(userId) {
    const doc = await this.users.doc(userId).get();
    if (!doc.exists) throw new QuoteError(404, 'no_user', 'User not found.');
    const user = { id: doc.id, ...doc.data() };
    const prefs = this.prefsOf(user);
    const today = await this.todaysQuote(userId, user);
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

  // What the widget shows: whatever was last delivered today, if anything.
  async todaysQuote(userId, user) {
    const zone = (user.notificationPreferences || {}).timezone;
    const doc = await this.sends.doc(QuotesService.sendId(userId, localDateKey(zone))).get();
    if (!doc.exists) return null;
    const d = doc.data();
    return { text: d.text, author: d.author || null, category: d.category || null, sentAt: d.sentAt || null };
  }

  // MARK: - Catalog

  async loadCatalog(categories) {
    const snap = await this.quotes.where('enabled', '==', true).get();
    const all = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const wanted = new Set(categories || []);
    const matching = all.filter((q) => (q.categories || []).some((c) => wanted.has(c)));
    // Falling back to the whole catalog beats sending nothing because a
    // category happens to be empty today.
    return matching.length ? matching : all;
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

  isUsersQuoteHour(user, now) {
    const prefs = this.prefsOf(user);
    if (!prefs.enabled) return false;
    const zone = (user.notificationPreferences || {}).timezone;
    const clock = localClock(zone, now);
    const [h, m] = String(prefs.time).split(':').map((n) => parseInt(n, 10));
    if (!Number.isInteger(h)) return false;
    const delta = clock.minutes - (h * 60 + m);
    return delta >= 0 && delta < RUN_WINDOW_MINUTES;
  }

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
    const due = force ? users : users.filter((u) => this.isUsersQuoteHour(u, now));
    const results = { candidates: users.length, due: due.length, sent: 0, emailed: 0, skipped: 0, dryRun };

    for (let i = 0; i < due.length; i += BATCH_SIZE) {
      const batch = due.slice(i, i + BATCH_SIZE);
      await Promise.all(batch.map(async (user) => {
        try {
          const outcome = await this.sendToUser(user, { now, dryRun });
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

  async sendToUser(user, { now = new Date(), dryRun = false } = {}) {
    const prefs = this.prefsOf(user);
    const zone = (user.notificationPreferences || {}).timezone;
    const dateKey = localDateKey(zone, now);
    const sendRef = this.sends.doc(QuotesService.sendId(user.id, dateKey));

    const catalog = await this.loadCatalog(prefs.categories);
    if (!catalog.length) return { sent: false, reason: 'empty_catalog' };

    const recent = (user.quoteRecentIds || []).slice(-RECENT_MEMORY);
    const quote = this.pickQuote(catalog, recent);
    if (!quote) return { sent: false, reason: 'no_quote' };

    if (dryRun) return { sent: false, reason: 'dry_run', preview: { userId: user.id, text: quote.text } };

    // The day's document id is the lock: a retried run loses the race and
    // stops here rather than sending a second quote.
    try {
      await sendRef.create({
        userId: user.id, quoteId: quote.id, text: quote.text, author: quote.author || null,
        category: (quote.categories || [])[0] || null, dateKey, sentAt: nowIso(), emailed: false
      });
    } catch (error) {
      return { sent: false, reason: 'already_sent' };
    }

    const body = quote.author ? `${quote.text} — ${quote.author}` : quote.text;
    await notificationService.sendToUser(user.id, {
      type: 'daily_quote',
      title: 'Today\'s quote',
      body,
      data: { type: 'daily_quote', quoteId: quote.id }
    });

    let emailed = false;
    if (prefs.email && user.email) {
      try {
        await emailService.sendEmail({
          to: user.email,
          subject: 'Today\'s quote',
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
    <p style="margin:0 0 20px;font-size:13px;letter-spacing:2px;text-transform:uppercase;color:#4FD1C5;font-weight:700">Today's quote</p>
    <p style="margin:0;font-size:22px;line-height:1.45;color:#0E2A47">${escapeHtml(quote.text)}</p>
    ${quote.author ? `<p style="margin:16px 0 0;font-size:15px;color:#64748b">— ${escapeHtml(quote.author)}</p>` : ''}
    <p style="margin:32px 0 0;font-size:13px;color:#94a3b8">${name ? `Have a good one, ${escapeHtml(name)}.` : 'Have a good one.'}
      <br>You can change the time, the topics, or turn this off in the Quotes widget.</p>
  </div>
</body></html>`;
  }
}

function escapeHtml(value) {
  return String(value || '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

module.exports = new QuotesService();
module.exports.QuotesService = QuotesService;
module.exports.QuoteError = QuoteError;
module.exports.CATEGORIES = CATEGORIES;
module.exports.DEFAULT_PREFS = DEFAULT_PREFS;
module.exports.normalizePrefs = normalizePrefs;
