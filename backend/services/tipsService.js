// backend/services/tipsService.js
//
// "Did you know…" educational tips — a low-cadence (2×/week) push + in-app
// notification channel that deep-links into a specific view (Mapstr-style).
//
// Deliberately infrequent. The daily engagement nag was retired 2026-08-12
// because over-notifying drove notification opt-outs; this channel is capped at
// twice a week, sends each tip at most once (no repeats), and honors a dedicated
// `tips` opt-out preference.
//
// The catalog lives in Firestore (`notificationTips`) so tips can be added or
// edited without an app release — any tip that reuses an already-wired deep-link
// target ships live the moment it's enabled. A brand-new *target* still needs an
// iOS release (the app must know how to route it).
//
// Delivery mirrors dailySummaryService: an hourly Cloud Scheduler tick, per-user
// local-time gating (deliver on the configured local weekday + hour, in the
// user's own timezone), a rolling-window frequency cap, and a distributed lock
// against concurrent double-sends.
//
// Routing note: the push goes out with type `did_you_know` (the wrapper used for
// preference gating + in-app persistence), while `data.type` carries the actual
// deep-link target (e.g. "all_places_map"). notificationService lets data.type
// win in the delivered payload, so the iOS router navigates on the target with
// no app change required.

const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS, createNotification, validateNotification } = require('../models/FirestoreModels');
const notificationService = require('./notificationService');
const sseService = require('./sseService');

const db = getFirestore();

// Local weekdays tips go out on (0=Sun … 6=Sat). Tue + Fri = the 2×/week
// cadence. Overridable via env so the cadence can be tuned without a code change.
const TIP_DAYS = String(process.env.TIP_DAYS || '2,5')
  .split(',')
  .map(d => parseInt(d, 10))
  .filter(d => !Number.isNaN(d));
// Local hour (24h clock) tips are delivered at, in the user's own timezone.
const TIP_HOUR = parseInt(process.env.TIP_HOUR || '12', 10);
// Frequency cap: never send two tips within this many hours, even if the
// scheduler double-fires or the day config ever overlaps. Tue→Fri is ~72h, so
// 60h leaves margin without ever allowing two in the same window.
const MIN_HOURS_BETWEEN_TIPS = parseInt(process.env.TIP_MIN_HOURS || '60', 10);
const BATCH_SIZE = 25;

const TIP_WRAPPER_TYPE = 'did_you_know'; // preference-gating + in-app doc type
const CATALOG_COLLECTION = 'notificationTips';
const WEEKDAY_ABBR = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class TipsService {
  // Entry point (called by /api/tasks/tips). Options:
  //   dryRun — compute who/what would send, but don't send, persist, or record
  //   userId — restrict to a single user (testing)
  //   force  — bypass day/hour/frequency gating for that user (testing E2E)
  async sendTips({ dryRun = false, userId = null, force = false } = {}) {
    console.log(`💡 Tips run started (dryRun=${dryRun}, userId=${userId || 'all'}, force=${force})`);

    // Distributed lock only for the real all-users scheduled run. Targeted or
    // forced test runs never take the lock, so they always execute.
    let lockAcquired = false;
    if (!userId && !force && !dryRun) {
      lockAcquired = await this.acquireLock();
      if (!lockAcquired) {
        console.log('⚠️ Tips already running for this hour — skipping');
        return { skipped: 'locked' };
      }
    }

    try {
      const catalog = await this.loadCatalog();
      if (catalog.length === 0) {
        console.log('💡 No enabled tips in catalog — nothing to send');
        return { sent: 0, reason: 'empty_catalog' };
      }

      const users = await this.loadCandidateUsers(userId);
      const eligible = force ? users : users.filter(u => this.isUsersTipTime(u));

      const results = {
        candidates: users.length,
        matched: eligible.length,
        sent: 0,
        dryRun,
        previews: []
      };

      for (let i = 0; i < eligible.length; i += BATCH_SIZE) {
        const batch = eligible.slice(i, i + BATCH_SIZE);
        await Promise.all(batch.map(async user => {
          const outcome = await this.sendTipToUser(user, catalog, { dryRun, force });
          if (outcome && outcome.sent) results.sent += 1;
          if (outcome && outcome.preview && results.previews.length < 25) {
            results.previews.push(outcome.preview);
          }
        }));
      }

      console.log(`💡 Tips run complete — matched ${results.matched}, sent ${results.sent}${dryRun ? ' (dry run)' : ''}`);
      return results;
    } finally {
      if (lockAcquired) await this.releaseLock();
    }
  }

  async sendTipToUser(user, catalog, { dryRun, force }) {
    try {
      const prefs = user.notificationPreferences || {};
      if (prefs.tips === false) return null; // opted out of the tips channel

      if (!force && await this.sentTipRecently(user)) return null;

      const tip = this.pickTip(user, catalog);
      if (!tip) return null; // nothing new for this user (all seen / not eligible)

      const preview = { userId: user.id, tipId: tip.id, title: tip.title };
      if (dryRun) return { sent: false, preview };

      const data = {
        type: tip.target,        // iOS routes on this (data.type wins in payload)
        tipId: tip.id,
        ...(tip.data || {})
      };

      // In-app: persist + SSE so a missed banner still lives in the user's
      // Notifications list (the durable half of "also land in-app").
      const notificationData = createNotification({
        userId: user.id,
        type: TIP_WRAPPER_TYPE,
        title: tip.title,
        body: tip.body,
        data
      });
      const errs = validateNotification(notificationData);
      if (errs.length === 0) {
        const ref = await db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
        sseService.notifyUser(user.id, 'new_notification', {
          notificationId: ref.id,
          type: TIP_WRAPPER_TYPE,
          title: tip.title,
          body: tip.body,
          data
        });
      } else {
        console.error('❌ Tip notification failed validation:', errs);
      }

      // Push (sendToUser gates on the `tips` pref + quiet hours + device tokens).
      await notificationService.sendToUser(user.id, {
        type: TIP_WRAPPER_TYPE,
        title: tip.title,
        body: tip.body,
        data
      });

      await this.recordTipSent(user.id, tip.id);
      return { sent: true, preview };
    } catch (error) {
      console.error(`❌ Error sending tip to ${user.id}:`, error);
      return null;
    }
  }

  // First enabled, unseen tip (by ascending order) whose targeting predicate the
  // user satisfies. No repeats — once seen, a tip never fires again.
  pickTip(user, catalog) {
    const seen = new Set(user.tipsSeen || []);
    return catalog.find(tip => !seen.has(tip.id) && this.userMatchesRequirement(user, tip)) || null;
  }

  userMatchesRequirement(user, tip) {
    if (tip.requires === 'hasPlaces') {
      const count = user.placesCount ?? user.totalPlaces ?? user.placeCount;
      // Only suppress when we can affirmatively see zero saved places; an
      // unknown/absent count falls through to "allow" so targeting can never
      // silently mute the whole catalog.
      return count === undefined || count === null || count > 0;
    }
    return true;
  }

  async loadCatalog() {
    const snap = await db.collection(CATALOG_COLLECTION).where('enabled', '==', true).get();
    const tips = [];
    snap.forEach(doc => tips.push({ id: doc.id, ...doc.data() }));
    tips.sort((a, b) => (a.order ?? 9999) - (b.order ?? 9999)); // missing order sinks last
    return tips;
  }

  async loadCandidateUsers(userId) {
    if (userId) {
      const doc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      return doc.exists ? [{ id: doc.id, ...doc.data() }] : [];
    }
    // Tips are opt-OUT (default on), so a `where tips == true` filter would
    // exclude everyone who never touched the toggle. Fetch all and gate in
    // memory, the same whole-base iteration the engagement service uses.
    const snap = await db.collection(COLLECTIONS.USERS).get();
    const users = [];
    snap.forEach(doc => users.push({ id: doc.id, ...doc.data() }));
    return users;
  }

  // True when the user's local clock is on a configured tip weekday AND at the
  // tip hour right now. Mirrors dailySummaryService.isUsersSummaryHour; invalid/
  // missing timezone falls back to America/New_York.
  isUsersTipTime(user) {
    const prefs = user.notificationPreferences || {};
    const tz = prefs.timezone || 'America/New_York';
    let parts;
    try {
      parts = new Intl.DateTimeFormat('en-US', {
        timeZone: tz, weekday: 'short', hour: 'numeric', hour12: false
      }).formatToParts(new Date());
    } catch (error) {
      parts = new Intl.DateTimeFormat('en-US', {
        timeZone: 'America/New_York', weekday: 'short', hour: 'numeric', hour12: false
      }).formatToParts(new Date());
    }
    const weekdayStr = (parts.find(p => p.type === 'weekday') || {}).value || '';
    const hour = parseInt((parts.find(p => p.type === 'hour') || {}).value || '-1', 10) % 24;
    const dayIndex = WEEKDAY_ABBR.indexOf(weekdayStr);
    return TIP_DAYS.includes(dayIndex) && hour === TIP_HOUR;
  }

  async sentTipRecently(user) {
    if (!user.lastTipSentAt) return false;
    const hours = (Date.now() - new Date(user.lastTipSentAt).getTime()) / (1000 * 60 * 60);
    return hours < MIN_HOURS_BETWEEN_TIPS;
  }

  async recordTipSent(userId, tipId) {
    try {
      await db.collection(COLLECTIONS.USERS).doc(userId).update({
        lastTipSentAt: new Date().toISOString(),
        tipsSeen: FieldValue.arrayUnion(tipId)
      });
    } catch (error) {
      console.error(`Error recording tip sent for ${userId}:`, error);
    }
  }

  lockId() {
    const now = new Date();
    const key = `${now.toISOString().split('T')[0]}-${String(now.getUTCHours()).padStart(2, '0')}`;
    return `tips-${key}`;
  }

  async acquireLock() {
    const lockId = this.lockId();
    try {
      await db.collection('system_locks').doc(lockId).create({
        lockType: 'tips',
        date: lockId,
        acquiredAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(), // 2h expiry
        status: 'acquired'
      });
      console.log(`🔒 Acquired tips lock: ${lockId}`);
      return true;
    } catch (error) {
      if (error.code === 6) { // ALREADY_EXISTS
        console.log(`⚠️ Tips lock already held for ${lockId}`);
        return false;
      }
      throw error;
    }
  }

  async releaseLock() {
    try {
      await db.collection('system_locks').doc(this.lockId()).update({
        status: 'completed',
        completedAt: new Date().toISOString()
      });
    } catch (error) {
      console.warn('Warning: could not release tips lock:', error.message);
    }
  }
}

module.exports = new TipsService();
