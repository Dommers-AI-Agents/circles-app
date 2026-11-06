// backend/services/rewardHistoryService.js
// A customer's own history at one store, for the Get Rewards page
// (Wes, 2026-11-02: "use the empty space to add value"): how many times
// they've been, what they've earned and spent there, and the latest moves.
// Read-only over the rewardEvents ledger (index userId+venueId+createdAt).

const { getFirestore } = require('../config/firebase');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');

/// Ledger rows read per request; plenty for one person at one store
const SCAN_LIMIT = 200;
/// Rows the page lists
const RECENT_LIMIT = 8;

/// Events that put points in; a refund is the store's points coming back
const EARN_TYPES = new Set(['venue_visit', 'sticker_save', 'sticker_signup', 'share_conversion', 'code_redemption']);

/// Pure: totals and the recent list from ledger rows, newest first
function summarize(events) {
  let visits = 0;
  let earned = 0;
  let redeemed = 0;
  let firstAt = null;
  let lastVisitAt = null;
  const recent = [];
  for (const e of events) {
    const points = Number(e.points) || 0;
    if (e.type === 'venue_visit') {
      visits += 1;
      if (!lastVisitAt) lastVisitAt = e.createdAt;
    }
    if (EARN_TYPES.has(e.type)) earned += points;
    // A refunded ticket gave nothing: its spend and its refund both drop out
    if (e.type === 'redemption' && e.status !== 'expired') redeemed += 1;
    firstAt = e.createdAt || firstAt;
    const row = historyRow(e);
    if (row && recent.length < RECENT_LIMIT) recent.push(row);
  }
  return { visits, earned, redeemed, firstAt, lastVisitAt, recent };
}

/// One line the page shows; nil for rows that say nothing to the customer
function historyRow(e) {
  const points = Number(e.points) || 0;
  const base = { at: e.createdAt, points };
  switch (e.type) {
    case 'venue_visit': return { ...base, kind: 'earn', title: e.via === 'delivery_receipt' ? 'Delivery order' : 'Visit' };
    case 'sticker_save': return { ...base, kind: 'earn', title: 'Saved the store' };
    case 'sticker_signup': return { ...base, kind: 'earn', title: 'Joined at the store' };
    case 'share_conversion': return { ...base, kind: 'earn', title: 'A friend saved it from your share' };
    case 'code_redemption': return { ...base, kind: 'earn', title: 'Reward code' };
    case 'redemption':
      // The spend shows as negative; a ticket that ran out shows as such
      return { ...base, points: -Math.abs(points), kind: e.status === 'expired' ? 'expired' : 'redeem', title: e.offerTitle || 'Reward' };
    case 'redemption_refund': return { ...base, kind: 'refund', title: `Points back · ${e.offerTitle || 'reward'}` };
    default: return null;
  }
}

async function forUserAtVenue(userId, venueId) {
  const snap = await getFirestore().collection(STICKER_COLLECTIONS.REWARD_EVENTS)
    .where('userId', '==', userId)
    .where('venueId', '==', venueId)
    .orderBy('createdAt', 'desc')
    .limit(SCAN_LIMIT)
    .get();
  return summarize(snap.docs.map((d) => d.data()));
}

module.exports = { forUserAtVenue, summarize, historyRow };
