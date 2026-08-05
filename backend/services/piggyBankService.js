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
  createPiggyLedgerEntry,
  createPiggyClaimEntry
} = require('../models/PiggyBankModels');
const config = require('../config/piggyBankConfig');
const cactusWallet = require('./cactusWalletService');

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

    // In-flight claim, fetched by ref (never a query) so the UI can show
    // "on the way to your wallet" state.
    let activeClaim = null;
    if (bank.activeClaimId) {
      const claimDoc = await this.db.collection(PIGGY_COLLECTIONS.LEDGER)
        .doc(bank.activeClaimId).get();
      if (claimDoc.exists) {
        const row = claimDoc.data();
        activeClaim = {
          id: claimDoc.id,
          status: row.status,
          coins: row.coins,
          feeCoins: row.feeCoins,
          netCoins: row.netCoins,
          catAmount: row.catAmount,
          address: row.address,
          txId: row.txId || null,
          createdAt: row.createdAt
        };
      }
    }

    return {
      bank: {
        pendingCoins: bank.pendingCoins || 0,
        confirmedCoins: bank.confirmedCoins || 0,
        lifetimeCoins: bank.lifetimeCoins || 0,
        settledOnChain: bank.settledOnChain || 0,
        walletAddress: bank.walletAddress || null
      },
      activeClaim,
      events: eventsSnap.docs.map(doc => ({ id: doc.id, ...doc.data() })),
      config: {
        coinValues: config.COINS,
        clearingWindowHours: config.CLEARING_WINDOW_HOURS,
        minConfirmedToClaim: config.CLAIM.MIN_CONFIRMED_TO_CLAIM,
        claimFeeCoins: config.CLAIM.CLAIM_FEE_COINS,
        coinsPerCat: config.CLAIM.COINS_PER_CAT,
        claimsEnabled: cactusWallet.isEnabled(),
        explorerBaseUrl: cactusWallet.explorerBaseUrl()
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

  // ---- Claims (Phase 4: on-chain settlement) ------------------------------
  //
  // State machine (each transition re-reads the row and bails if the status
  // isn't the expected source — that's what makes overlapping workers safe):
  //
  //   T1 claim()          →  claim_pending   confirmedCoins debited, activeClaimId set
  //   T2 worker           →  claim_sending   marker commits BEFORE any RPC
  //   T3 rpc 'sent'       →  claim_sent      txId recorded
  //   T4 rpc 'rejected'   →  claim_failed    refund (fee only charged on success)
  //   T5 rpc 'unknown' / stale claim_sending → needsReview, NEVER auto-retried
  //   T6 tx confirmed     →  settled         settledOnChain credited
  //   T7 unconfirmed 24h  →  needsReview (keep polling; never auto-refund)
  //   T8 resolveClaim()   →  claim_sent | claim_failed (human verdict)
  //
  // The only actor allowed to call cat_spend for a row is the pass that just
  // moved it pending→sending itself. Ambiguity always parks; no path double-sends.

  // Save/replace the user's self-custody claim address. Validation (bech32m,
  // 'cac' prefix) happens in the route; claims snapshot the address, so
  // changing it mid-claim is safe — the in-flight claim keeps its target.
  async linkWallet(userId, address) {
    await this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(userId).set({
      walletAddress: address,
      walletLinkedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    }, { merge: true });
    return { walletAddress: address };
  }

  // T1: snapshot the user's entire confirmed balance into a claim row.
  async claim(userId) {
    const bankRef = this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(userId);
    let result;
    try {
      result = await this.db.runTransaction(async (tx) => {
        const bankDoc = await tx.get(bankRef);
        const bank = bankDoc.exists ? bankDoc.data() : {};
        if (!bank.walletAddress) return { ok: false, code: 'no_wallet' };
        if (bank.activeClaimId) {
          return { ok: false, code: 'claim_in_flight', activeClaimId: bank.activeClaimId };
        }
        const confirmed = bank.confirmedCoins || 0;
        if (confirmed < config.CLAIM.MIN_CONFIRMED_TO_CLAIM) {
          return {
            ok: false, code: 'below_minimum',
            minimum: config.CLAIM.MIN_CONFIRMED_TO_CLAIM, confirmed
          };
        }
        const entry = createPiggyClaimEntry({
          userId, confirmedCoins: confirmed, address: bank.walletAddress
        });
        if (entry.catAmount < 1) return { ok: false, code: 'nothing_to_send' };

        const seq = (bank.claimCount || 0) + 1;
        const claimId = derivePiggyDedupKey('claim', { userId, seq });
        tx.create(this.db.collection(PIGGY_COLLECTIONS.LEDGER).doc(claimId), entry);
        tx.set(bankRef, {
          confirmedCoins: FieldValue.increment(-entry.coins),
          activeClaimId: claimId,
          claimCount: FieldValue.increment(1),
          updatedAt: new Date().toISOString()
        }, { merge: true });
        return { ok: true, claim: { id: claimId, ...entry } };
      });
    } catch (error) {
      // Concurrent claim lost the dedup-key race — same answer as the
      // activeClaimId check it slipped past.
      if (error.code === 6 || /already exists/i.test(error.message || '')) {
        return { ok: false, code: 'claim_in_flight' };
      }
      console.error('🐷 claim failed:', error.message);
      return { ok: false, code: 'error' };
    }

    if (result.ok) {
      // Kick settlement so claims usually land within seconds; the scheduled
      // worker is the backstop. Never awaited, never fails the request.
      this.runSettlement().catch((e) =>
        console.error('🐷 inline settlement kick failed:', e.message));
    }
    return result;
  }

  // One transition attempt in a transaction: expectedStatus gate + updates.
  // Returns true if this call performed the transition.
  async transitionClaim(claimRef, expectedStatus, rowUpdates, bankMutation = null) {
    return await this.db.runTransaction(async (tx) => {
      const fresh = await tx.get(claimRef);
      if (!fresh.exists || fresh.data().status !== expectedStatus) return false;
      tx.update(claimRef, rowUpdates);
      if (bankMutation) {
        const bankRef = this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(fresh.data().userId);
        tx.set(bankRef, bankMutation, { merge: true });
      }
      return true;
    });
  }

  // The settlement worker. Pass order matters: confirmations first, then
  // quarantine, then new sends.
  async runSettlement() {
    const summary = { settled: 0, sent: 0, refunded: 0, flagged: 0, skipped: 0 };
    if (!cactusWallet.isEnabled()) {
      return { ...summary, disabled: true };
    }
    const C = config.CLAIM;
    const ledger = this.db.collection(PIGGY_COLLECTIONS.LEDGER);
    const nowMs = Date.now();

    // 1. Poll broadcast transactions for confirmation (T6 / T7).
    const sentSnap = await ledger.where('status', '==', 'claim_sent')
      .limit(C.SETTLEMENT_BATCH_SIZE).get();
    for (const doc of sentSnap.docs) {
      const row = doc.data();
      try {
        const confirmed = await cactusWallet.getTransactionConfirmed(row.txId);
        if (confirmed) {
          const stamp = new Date().toISOString();
          const did = await this.transitionClaim(doc.ref, 'claim_sent',
            { status: 'settled', settledAt: stamp },
            {
              settledOnChain: FieldValue.increment(row.coins),
              activeClaimId: null,
              updatedAt: stamp
            });
          if (did) summary.settled++; else summary.skipped++;
        } else if (row.sentAt
            && nowMs - Date.parse(row.sentAt) > C.SENT_TIMEOUT_HOURS * 3600000
            && !row.needsReview) {
          // Broadcast but unconfirmed for a day: a human should look. Keep
          // polling; NEVER auto-refund (a slow tx may still confirm).
          await doc.ref.update({ needsReview: true });
          console.error(`🐷 [claims] ${doc.id} unconfirmed >${C.SENT_TIMEOUT_HOURS}h — flagged`);
          summary.flagged++;
        } else {
          summary.skipped++;
        }
      } catch (error) {
        summary.skipped++; // transport blip; next pass retries the poll
      }
    }

    // 2. Quarantine stale claim_sending rows (T5). A row *found* in sending
    // is a crash or an in-progress RPC; past the grace window it's quarantined
    // for manual resolution — auto-retrying could pay twice.
    const sendingSnap = await ledger.where('status', '==', 'claim_sending')
      .limit(C.SETTLEMENT_BATCH_SIZE).get();
    for (const doc of sendingSnap.docs) {
      const row = doc.data();
      const age = row.sendingAt ? nowMs - Date.parse(row.sendingAt) : Infinity;
      if (age > C.SENDING_GRACE_MINUTES * 60000 && !row.needsReview) {
        await doc.ref.update({ needsReview: true });
        console.error(`🐷 [claims] ${doc.id} stuck in claim_sending — flagged for manual resolution (resolve-claim task)`);
        summary.flagged++;
      } else {
        summary.skipped++;
      }
    }

    // 3. Send new claims (T2 → RPC → T3/T4/T5).
    const pendingSnap = await ledger.where('status', '==', 'claim_pending')
      .limit(C.SETTLEMENT_BATCH_SIZE).get();
    for (const doc of pendingSnap.docs) {
      const row = doc.data();

      // T2: the marker MUST commit before the RPC. Only the pass that wins
      // this transition may call cat_spend for this row.
      const took = await this.transitionClaim(doc.ref, 'claim_pending', {
        status: 'claim_sending',
        sendingAt: new Date().toISOString(),
        attempts: (row.attempts || 0) + 1
      });
      if (!took) { summary.skipped++; continue; }

      const outcome = await cactusWallet.sendCat({
        address: row.address, mojos: row.mojos, memo: doc.id
      });

      if (outcome.outcome === 'sent') {
        await this.transitionClaim(doc.ref, 'claim_sending', {
          status: 'claim_sent', txId: outcome.txId, sentAt: new Date().toISOString()
        });
        summary.sent++;
      } else if (outcome.outcome === 'rejected') {
        // A response arrived, so nothing broadcast — refund the gross coins.
        const stamp = new Date().toISOString();
        await this.transitionClaim(doc.ref, 'claim_sending',
          { status: 'claim_failed', failedAt: stamp, failReason: outcome.reason },
          {
            confirmedCoins: FieldValue.increment(row.coins),
            activeClaimId: null,
            updatedAt: stamp
          });
        console.error(`🐷 [claims] ${doc.id} rejected by wallet (${outcome.reason}) — refunded`);
        summary.refunded++;
      } else {
        // Transport ambiguity: the spend may exist. Park it.
        await doc.ref.update({ needsReview: true, failReason: outcome.reason });
        console.error(`🐷 [claims] ${doc.id} ambiguous send (${outcome.reason}) — quarantined, NOT retried`);
        summary.flagged++;
      }
    }

    return summary;
  }

  // T8: human verdict on a quarantined/stuck claim, via the admin task route.
  // resolution 'sent' (+txId): the spend really happened — record it and let
  // polling settle it. resolution 'failed': verified never-broadcast — refund.
  async resolveClaim({ claimId, resolution, txId = null }) {
    const claimRef = this.db.collection(PIGGY_COLLECTIONS.LEDGER).doc(claimId);
    return await this.db.runTransaction(async (tx) => {
      const doc = await tx.get(claimRef);
      if (!doc.exists) return { ok: false, code: 'not_found' };
      const row = doc.data();
      if (row.eventType !== 'claim') return { ok: false, code: 'not_a_claim' };
      if (!['claim_sending', 'claim_sent'].includes(row.status)) {
        return { ok: false, code: `not_resolvable_from_${row.status}` };
      }
      const stamp = new Date().toISOString();
      if (resolution === 'sent') {
        if (!txId) return { ok: false, code: 'tx_id_required' };
        tx.update(claimRef, {
          status: 'claim_sent', txId, sentAt: row.sentAt || stamp, needsReview: false
        });
        return { ok: true, status: 'claim_sent' };
      }
      if (resolution === 'failed') {
        tx.update(claimRef, {
          status: 'claim_failed', failedAt: stamp,
          failReason: 'manual_resolution', needsReview: false
        });
        tx.set(this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(row.userId), {
          confirmedCoins: FieldValue.increment(row.coins),
          activeClaimId: null,
          updatedAt: stamp
        }, { merge: true });
        return { ok: true, status: 'claim_failed' };
      }
      return { ok: false, code: 'bad_resolution' };
    });
  }

  // Recompute one user's bank from the ledger; report (and optionally fix) drift.
  async reconcile(userId, { repair = false } = {}) {
    const snap = await this.db.collection(PIGGY_COLLECTIONS.LEDGER)
      .where('userId', '==', userId).get();
    const computed = { pendingCoins: 0, confirmedCoins: 0, lifetimeCoins: 0, settledOnChain: 0 };
    snap.docs.forEach(doc => {
      const row = doc.data();
      if (row.eventType === 'claim') {
        // Every non-failed claim holds its gross coins out of confirmedCoins;
        // only settled ones count as on-chain. Invariant when nothing is in
        // flight: confirmedCoins + settledOnChain === lifetimeCoins.
        if (['claim_pending', 'claim_sending', 'claim_sent', 'settled'].includes(row.status)) {
          computed.confirmedCoins -= row.coins;
        }
        if (row.status === 'settled') computed.settledOnChain += row.coins;
        return;
      }
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
      (bank.lifetimeCoins || 0) !== computed.lifetimeCoins ||
      (bank.settledOnChain || 0) !== computed.settledOnChain;
    if (drift && repair) {
      await this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(userId).set({
        ...computed, updatedAt: new Date().toISOString()
      }, { merge: true });
    }
    return { drift, computed, bank };
  }
}

module.exports = new PiggyBankService();
