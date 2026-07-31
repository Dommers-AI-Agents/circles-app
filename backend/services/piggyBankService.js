// backend/services/piggyBankService.js
//
// FavCoin piggy bank: the off-chain ledger that is the SOURCE OF TRUTH.
// Two-stage clearing: earns land as `pending` (the deposit animation plays
// immediately), runClearing() promotes to `confirmed` after the clearing
// window, re-validating the underlying fact. Failures become reversal records —
// the ledger is append-only, rows flip status but are never deleted or
// sign-flipped.
//
// Fire-and-forget contract: credit() NEVER throws to its caller. An earning
// failure must never break the user action that triggered it.
//
// Separate from the sticker rewards system (rewardService) by design.

const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const {
  PIGGY_COLLECTIONS,
  derivePiggyDedupKey,
  createPiggyLedgerEntry
} = require('../models/PiggyBankModels');
const config = require('../config/piggyBankConfig');

const MAX_CLEARING_BATCHES = 20;

class PiggyBankService {
  get db() { return getFirestore(); }

  coinsFor(eventType) {
    return config.COINS[String(eventType).toUpperCase()] || 0;
  }

  dailyCapFor(eventType) {
    return config.DAILY_CAPS[String(eventType).toUpperCase()] ?? Infinity;
  }

  // How many rows this user earned for this event type since UTC midnight.
  // Firestore aggregate count — no documents read.
  async countToday(userId, eventType) {
    const dayStart = new Date();
    dayStart.setUTCHours(0, 0, 0, 0);
    const snap = await this.db.collection(PIGGY_COLLECTIONS.LEDGER)
      .where('userId', '==', userId)
      .where('eventType', '==', eventType)
      .where('createdAt', '>=', dayStart.toISOString())
      .count()
      .get();
    return snap.data().count || 0;
  }

  // The single entry point every earning hook calls.
  // Returns { credited, coins?, eventType, duplicate?, reason? } — and never throws.
  async credit({ userId, eventType, sourceRef = {} }) {
    try {
      const coins = this.coinsFor(eventType);
      if (!userId || coins <= 0) {
        return { credited: false, eventType, reason: 'unknown_event' };
      }

      const dedupKey = derivePiggyDedupKey(eventType, { userId, ...sourceRef });
      if (!dedupKey) {
        return { credited: false, eventType, reason: 'missing_key_parts' };
      }

      // Daily cap: past it, the action still succeeds but pays 0.
      const todayCount = await this.countToday(userId, eventType);
      if (todayCount >= this.dailyCapFor(eventType)) {
        return { credited: false, eventType, reason: 'daily_cap' };
      }

      const ledgerRef = this.db.collection(PIGGY_COLLECTIONS.LEDGER).doc(dedupKey);
      const bankRef = this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(userId);
      const entry = createPiggyLedgerEntry({ userId, eventType, coins, sourceRef });

      // Atomic: ledger row + bank increment together, or neither. tx.create
      // throws ALREADY_EXISTS (code 6) on a duplicate key, aborting the tx —
      // so a replayed event can never bump the bank a second time.
      try {
        await this.db.runTransaction(async (tx) => {
          tx.create(ledgerRef, entry);
          tx.set(bankRef, {
            pendingCoins: FieldValue.increment(coins),
            updatedAt: new Date().toISOString()
          }, { merge: true });
        });
      } catch (error) {
        if (error.code === 6 || /already exists/i.test(error.message || '')) {
          return { credited: false, eventType, duplicate: true };
        }
        throw error;
      }

      return { credited: true, coins, eventType };
    } catch (error) {
      console.error(`🐷 piggyBank credit failed (${eventType}):`, error.message);
      return { credited: false, eventType, reason: 'error' };
    }
  }

  // Bank + recent history + display config, so iOS renders without hardcoding.
  async getPiggyBank(userId) {
    const [bankDoc, eventsSnap] = await Promise.all([
      this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(userId).get(),
      this.db.collection(PIGGY_COLLECTIONS.LEDGER)
        .where('userId', '==', userId)
        .orderBy('createdAt', 'desc')
        .limit(config.HISTORY_PAGE_SIZE)
        .get()
    ]);

    const bank = bankDoc.exists ? bankDoc.data() : {};
    return {
      bank: {
        pendingCoins: bank.pendingCoins || 0,
        confirmedCoins: bank.confirmedCoins || 0,
        lifetimeCoins: bank.lifetimeCoins || 0,
        settledOnChain: bank.settledOnChain || 0
      },
      events: eventsSnap.docs.map(doc => ({ id: doc.id, ...doc.data() })),
      config: {
        coinValues: config.COINS,
        clearingWindowHours: config.CLEARING_WINDOW_HOURS,
        minConfirmedToClaim: config.CLAIM.MIN_CONFIRMED_TO_CLAIM
      }
    };
  }

  // Paginated ledger history (createdAt descending, before-cursor).
  async getHistory(userId, before) {
    let query = this.db.collection(PIGGY_COLLECTIONS.LEDGER)
      .where('userId', '==', userId)
      .orderBy('createdAt', 'desc');
    if (before) query = query.where('createdAt', '<', before);
    const snap = await query.limit(config.HISTORY_PAGE_SIZE).get();
    return snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  // ---- Clearing -----------------------------------------------------------

  // Re-validates the underlying fact for one pending row. Returns
  // { valid: true } or { valid: false, reason }.
  async validateEntry(entry) {
    const ref = entry.sourceRef || {};
    try {
      switch (entry.eventType) {
        case 'add_place': {
          if (!ref.placeId) return { valid: false, reason: 'missing_place_ref' };
          const doc = await this.db.collection(COLLECTIONS.PLACES).doc(ref.placeId).get();
          if (!doc.exists || doc.data().deletedAt) return { valid: false, reason: 'place_deleted' };
          return { valid: true };
        }
        case 'create_circle': {
          if (!ref.circleId) return { valid: false, reason: 'missing_circle_ref' };
          const doc = await this.db.collection(COLLECTIONS.CIRCLES).doc(ref.circleId).get();
          if (!doc.exists) return { valid: false, reason: 'circle_deleted' };
          if ((doc.data().placesCount || 0) < config.CREATE_CIRCLE_MIN_PLACES) {
            return { valid: false, reason: 'circle_below_min_places' };
          }
          return { valid: true };
        }
        case 'share_circle': {
          if (!ref.circleId) return { valid: false, reason: 'missing_circle_ref' };
          const doc = await this.db.collection(COLLECTIONS.CIRCLES).doc(ref.circleId).get();
          return doc.exists ? { valid: true } : { valid: false, reason: 'circle_deleted' };
        }
        case 'connection_accepted': {
          if (!ref.connectionId) return { valid: false, reason: 'missing_connection_ref' };
          const doc = await this.db.collection(COLLECTIONS.CONNECTIONS).doc(ref.connectionId).get();
          if (!doc.exists || doc.data().status !== 'accepted') {
            return { valid: false, reason: 'connection_not_accepted' };
          }
          return { valid: true };
        }
        case 'referral_signup': {
          if (!ref.inviteeId) return { valid: false, reason: 'missing_invitee_ref' };
          const invitee = await this.db.collection(COLLECTIONS.USERS).doc(ref.inviteeId).get();
          if (!invitee.exists) return { valid: false, reason: 'invitee_missing' };
          if (invitee.data().referredBy !== entry.userId) {
            return { valid: false, reason: 'referrer_mismatch' };
          }
          // Activation: the invitee actually used the app — at least one
          // non-deleted place or one accepted connection.
          const placeSnap = await this.db.collection(COLLECTIONS.PLACES)
            .where('addedBy', '==', ref.inviteeId)
            .where('deletedAt', '==', null)
            .limit(1).get();
          if (!placeSnap.empty) return { valid: true };
          const [connA, connB] = await Promise.all([
            this.db.collection(COLLECTIONS.CONNECTIONS)
              .where('userId', '==', ref.inviteeId).where('status', '==', 'accepted').limit(1).get(),
            this.db.collection(COLLECTIONS.CONNECTIONS)
              .where('connectedUserId', '==', ref.inviteeId).where('status', '==', 'accepted').limit(1).get()
          ]);
          if (!connA.empty || !connB.empty) return { valid: true };
          return { valid: false, reason: 'invitee_not_activated' };
        }
        case 'place_adopted': {
          if (!ref.adderPlaceId) return { valid: false, reason: 'missing_adder_place_ref' };
          const doc = await this.db.collection(COLLECTIONS.PLACES).doc(ref.adderPlaceId).get();
          if (!doc.exists || doc.data().deletedAt) return { valid: false, reason: 'adopted_place_deleted' };
          return { valid: true };
        }
        case 'suggestion_posted': {
          if (!ref.suggestionId) return { valid: false, reason: 'missing_suggestion_ref' };
          const doc = await this.db.collection(COLLECTIONS.SUGGESTIONS).doc(ref.suggestionId).get();
          return doc.exists ? { valid: true } : { valid: false, reason: 'suggestion_deleted' };
        }
        default:
          return { valid: false, reason: 'unknown_event_type' };
      }
    } catch (error) {
      // Validation infrastructure failure: HOLD by not deciding — the row
      // stays pending and the next run retries.
      console.error(`🐷 validate ${entry.eventType} errored:`, error.message);
      return { valid: null, reason: 'validation_error' };
    }
  }

  // Promote cleared pendings to confirmed; reverse the invalid ones.
  // Bank arithmetic rides in the same transaction as each status flip.
  async runClearing() {
    const summary = { scanned: 0, confirmed: 0, reversed: 0, retried: 0 };
    const nowIso = new Date().toISOString();

    for (let batch = 0; batch < MAX_CLEARING_BATCHES; batch++) {
      const snap = await this.db.collection(PIGGY_COLLECTIONS.LEDGER)
        .where('status', '==', 'pending')
        .where('clearAt', '<=', nowIso)
        .orderBy('clearAt')
        .limit(config.CLEARING_BATCH_SIZE)
        .get();
      if (snap.empty) break;

      for (const doc of snap.docs) {
        const entry = doc.data();
        summary.scanned++;

        const verdict = await this.validateEntry(entry);
        if (verdict.valid === null) { summary.retried++; continue; }

        const bankRef = this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(entry.userId);
        const stamp = new Date().toISOString();
        try {
          await this.db.runTransaction(async (tx) => {
            // Re-read inside the tx: overlapping runs must not double-apply.
            const fresh = await tx.get(doc.ref);
            if (!fresh.exists || fresh.data().status !== 'pending') return;

            if (verdict.valid) {
              tx.update(doc.ref, { status: 'confirmed', confirmedAt: stamp });
              tx.set(bankRef, {
                pendingCoins: FieldValue.increment(-entry.coins),
                confirmedCoins: FieldValue.increment(entry.coins),
                lifetimeCoins: FieldValue.increment(entry.coins),
                updatedAt: stamp
              }, { merge: true });
            } else {
              tx.update(doc.ref, {
                status: 'reversed', reversedAt: stamp, reverseReason: verdict.reason
              });
              tx.set(bankRef, {
                pendingCoins: FieldValue.increment(-entry.coins),
                updatedAt: stamp
              }, { merge: true });
            }
          });
          if (verdict.valid) summary.confirmed++; else summary.reversed++;
        } catch (error) {
          console.error(`🐷 clearing tx failed for ${doc.id}:`, error.message);
          summary.retried++;
        }
      }

      if (snap.size < config.CLEARING_BATCH_SIZE) break;
      // Rows that stayed pending (retried) would loop forever if a whole batch
      // failed — the batch guard caps the damage; next scheduled run resumes.
    }

    return summary;
  }

  // Recompute one user's bank from the ledger; report (and optionally fix) drift.
  async reconcile(userId, { repair = false } = {}) {
    const snap = await this.db.collection(PIGGY_COLLECTIONS.LEDGER)
      .where('userId', '==', userId).get();
    const computed = { pendingCoins: 0, confirmedCoins: 0, lifetimeCoins: 0 };
    snap.docs.forEach(doc => {
      const row = doc.data();
      if (row.status === 'pending') computed.pendingCoins += row.coins;
      if (row.status === 'confirmed') {
        computed.confirmedCoins += row.coins;
        computed.lifetimeCoins += row.coins;
      }
    });
    const bankDoc = await this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(userId).get();
    const bank = bankDoc.exists ? bankDoc.data() : {};
    const drift =
      (bank.pendingCoins || 0) !== computed.pendingCoins ||
      (bank.confirmedCoins || 0) !== computed.confirmedCoins ||
      (bank.lifetimeCoins || 0) !== computed.lifetimeCoins;
    if (drift && repair) {
      await this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(userId).set({
        ...computed, updatedAt: new Date().toISOString()
      }, { merge: true });
    }
    return { drift, computed, bank };
  }
}

module.exports = new PiggyBankService();
