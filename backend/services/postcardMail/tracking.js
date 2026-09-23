// services/postcardMail/tracking.js — methods of PostcardMailService (mixed into its prototype by the facade).
//
// Where the card actually is, from Lob itself. Webhooks are the fast path;
// this is the truth, because webhooks arrive late, get dropped, or were not
// configured yet (the first real orders, 2026-09-17..21: three cards sat at
// "rendered" under a funding hold and one had failed at render, and the app
// said "printed and mailed" about all four).
//
// Two callers: the hourly reconciler sweeps every live order, and a read of
// an order list kicks a background refresh for rows that have gone stale —
// stale-while-revalidate, so the list never waits on Lob.
const { STATUS, lobClient } = require('./shared');

const LIVE = [STATUS.SUBMITTED, STATUS.IN_TRANSIT];
const STALE_MS = 30 * 60 * 1000;
const MAX_AGE_DAYS = 45;

// Lob's tracking event names are human ("Processed for Delivery"); the
// webhook vocabulary is snake_case. One normaliser feeds the webhook handler.
const eventName = (event) => {
  const raw = event && (event.name || event.event_type || event.type || '');
  return String(raw).trim().toLowerCase().replace(/[\s-]+/g, '_');
};

module.exports = {
  /**
   * Pulls one order's state from Lob and applies it through the same handler
   * the webhooks use, so a status change reached either way behaves the same
   * (captures, refunds, the delivered push). Never throws.
   */
  async syncFromLob(doc, row) {
    if (!row.lobPostcardId) return { synced: false };
    let lob;
    try {
      lob = await lobClient.getPostcard(row.lobPostcardId);
    } catch (error) {
      console.warn(`[postcard-mail] ${doc.id} Lob lookup failed: ${error.message}`);
      return { synced: false };
    }
    if (!lob) return { synced: false };

    const now = new Date().toISOString();
    const events = Array.isArray(lob.tracking_events) ? [...lob.tracking_events] : [];
    events.sort((a, b) => String(a.time || a.date_created || '').localeCompare(String(b.time || b.date_created || '')));
    const last = events.length ? eventName(events[events.length - 1]) : null;
    const lobStatus = typeof lob.status === 'string' ? lob.status : null;

    await doc.ref.update({
      lobStatus,
      lobFundingStatus: lob.lob_credits_funding_status || null,
      lobSendDate: lob.send_date || null,
      lobExpectedDeliveryDate: lob.expected_delivery_date || row.lobExpectedDeliveryDate || null,
      lobLastTrackingEvent: last,
      lobSyncedAt: now
    });

    // Print refused, or the carrier reported movement: same path as a webhook.
    let applied = null;
    if (lobStatus === 'failed' || lobStatus === 'rejected') {
      applied = await this.handleLobEvent({ body: { id: row.lobPostcardId }, event_type: { id: `postcard.${lobStatus}` } });
    } else if (last) {
      applied = await this.handleLobEvent({ body: { id: row.lobPostcardId }, event_type: { id: `postcard.${last}` } });
    }
    return { synced: true, lobStatus, funding: lob.lob_credits_funding_status || null, applied: applied && applied.handled };
  },

  /** Every live order, oldest first, for the hourly sweep. */
  async syncLiveOrders(limit = 100) {
    const summary = { synced: 0, holds: 0, failed: 0 };
    const cutoff = Date.now() - MAX_AGE_DAYS * 86400000;
    for (const status of LIVE) {
      const snap = await this.col.where('status', '==', status).limit(limit).get();
      for (const doc of snap.docs) {
        const row = doc.data();
        if (Date.parse(row.createdAt || '') < cutoff) continue;
        const result = await this.syncFromLob(doc, row);
        if (!result.synced) continue;
        summary.synced++;
        if (result.funding === 'funding_hold') summary.holds++;
        if (result.lobStatus === 'failed' || result.lobStatus === 'rejected') summary.failed++;
      }
    }
    if (summary.holds) console.error(`[postcard-mail] ${summary.holds} card(s) held at Lob for funding — check the Lob account's billing`);
    return summary;
  },

  /** Rows a list just returned that are live and haven't been asked about lately. */
  isStale(row, now = Date.now()) {
    if (!LIVE.includes(row.status) || !row.lobPostcardId) return false;
    const synced = Date.parse(row.lobSyncedAt || '');
    return !Number.isFinite(synced) || now - synced > STALE_MS;
  },

  /** Fire-and-forget refresh for stale rows; the caller has already answered. */
  syncStaleInBackground(docs) {
    const stale = docs.filter((doc) => this.isStale(doc.data()));
    if (!stale.length) return 0;
    Promise.all(stale.map((doc) => this.syncFromLob(doc, doc.data())))
      .catch((error) => console.warn(`[postcard-mail] background Lob sync failed: ${error.message}`));
    return stale.length;
  },

  /** What the app shows about the printer, on top of our own status. */
  printerFields(row) {
    return {
      printerStatus: row.lobStatus || null,
      printerHold: row.lobFundingStatus === 'funding_hold',
      lastTrackingEvent: row.lobLastTrackingEvent || null
    };
  }
};
