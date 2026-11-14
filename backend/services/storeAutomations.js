// backend/services/storeAutomations.js
//
// A store's automatic nudges (Wes, 2026-11-09): what a store pays a marketing
// tool for, from the loyalty data FavCircles already holds. Business only.
// Three automations, each a switch on the store record (`automations`):
//   * winBack     — a customer who hasn't bought in N days (14/30/60/90):
//                   "We miss you", optionally +bonus points on the next visit
//   * birthday    — a customer's birthday (MM-DD they gave us; never shown to
//                   the store): "Happy birthday", optionally +bonus points
//   * almostThere — one more purchase reaches the store's cheapest reward
// Delivered by push (`store_nudge`, muted with 'Stores you follow') or, when a
// push can't reach them, by email with a one-click unsubscribe. Never SMS.
//
// Rules that keep it from being spam: one nudge per customer per store per
// 14 days (`rewardPointsByVenue.{venue}.lastNudgeAt`); a win-back fires once
// per quiet spell (keyed on the last purchase date), almost-there once per
// points level, a birthday once a year; every send is a `storeAutomationSends`
// doc created once, so a rerun never sends twice; people the store removed
// from rewards are left alone; a lapsed Business plan stops every nudge.
//
// A bonus is a promise, not points: `pendingBonus {points, automation,
// expiresAt}` on the bucket, paid by the next register scan
// (rewardService.awardVenueVisit → applyPendingBonus), 30 days to use it.
//
// Coupons (2026-11-14, services/storeCoupons):
//   * a win-back may hand out a coupon (`winBack.couponId`) instead of, or
//     with, bonus points: the nudge claims it for the customer;
//   * `couponEnding` — a coupon someone claimed ends in 3 days and is still
//     unused: "Your 20% off ends Sunday". Time-bound, so it ignores the
//     14-day gap and never counts as the customer's one nudge; keyed per
//     coupon, so it's said once.
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { STICKER_COLLECTIONS, validateBonusPoints } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const { localDateKey } = require('../utils/localClock');
const { nextReward, article } = require('./rewardProgress');

const SENDS = 'storeAutomationSends';
const TYPES = ['birthday', 'almostThere', 'winBack', 'couponEnding']; // priority order: one nudge per customer per run (couponEnding rides alongside)
const COUPON_ENDING_DAYS = 3;
const WIN_BACK_DAYS = [14, 30, 60, 90];
const NUDGE_GAP_DAYS = 14;
const BONUS_TTL_DAYS = 30;
const EMAIL_KIND = 'storeNudges';
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_CUSTOMERS = 1000;

const DEFAULTS = Object.freeze({
  winBack: { enabled: false, days: 30, bonusPoints: 0, couponId: null },
  birthday: { enabled: false, bonusPoints: 0 },
  almostThere: { enabled: false }
});

const db = () => getFirestore();

// ---------- Settings ----------

/** The store's settings with every field present. */
const settingsOf = (venue) => {
  const raw = (venue && venue.automations) || {};
  const wb = raw.winBack || {};
  const bd = raw.birthday || {};
  const at = raw.almostThere || {};
  return {
    winBack: {
      enabled: wb.enabled === true,
      days: WIN_BACK_DAYS.includes(wb.days) ? wb.days : DEFAULTS.winBack.days,
      bonusPoints: Number.isInteger(wb.bonusPoints) && wb.bonusPoints >= 0 ? wb.bonusPoints : 0,
      couponId: typeof wb.couponId === 'string' && wb.couponId ? wb.couponId : null
    },
    birthday: {
      enabled: bd.enabled === true,
      bonusPoints: Number.isInteger(bd.bonusPoints) && bd.bonusPoints >= 0 ? bd.bonusPoints : 0
    },
    almostThere: { enabled: at.enabled === true }
  };
};

/** The owner's edit, checked; refuses with 400 invalid_automations. */
const normalizeSettings = (body) => {
  const input = body && typeof body === 'object' ? body : {};
  const bool = (v, name) => {
    if (v === undefined) return false;
    if (typeof v !== 'boolean') throw new ServiceError(400, 'invalid_automations', `${name} must be on or off.`);
    return v;
  };
  const bonus = (v, name) => {
    const n = v === undefined || v === null ? 0 : Number(v);
    const errors = validateBonusPoints(n, name);
    if (errors.length) throw new ServiceError(400, 'invalid_automations', errors[0]);
    return n;
  };
  const wb = input.winBack || {};
  const days = wb.days === undefined ? DEFAULTS.winBack.days : Number(wb.days);
  if (!WIN_BACK_DAYS.includes(days)) {
    throw new ServiceError(400, 'invalid_automations', `Win-back waits ${WIN_BACK_DAYS.join(', ')} days.`);
  }
  let couponId = null;
  if (wb.couponId !== undefined && wb.couponId !== null && wb.couponId !== '') {
    couponId = require('./storeCoupons').normalizeId(wb.couponId);
    if (!couponId) throw new ServiceError(400, 'invalid_automations', 'Pick one of your coupons for the win-back.');
  }
  return {
    winBack: { enabled: bool(wb.enabled, 'Win-back'), days, bonusPoints: bonus(wb.bonusPoints, 'Win-back bonus'), couponId },
    birthday: { enabled: bool((input.birthday || {}).enabled, 'Birthday'), bonusPoints: bonus((input.birthday || {}).bonusPoints, 'Birthday bonus') },
    almostThere: { enabled: bool((input.almostThere || {}).enabled, 'Almost there') }
  };
};

const anyEnabled = (settings) => TYPES.some((t) => settings[t] && settings[t].enabled);

// ---------- Birthday ----------

const BIRTHDAY_RE = /^(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;

/** "MM-DD" or null to clear; anything else refuses. */
const normalizeBirthday = (value) => {
  if (value === null || value === undefined || value === '') return null;
  const text = String(value).trim();
  if (!BIRTHDAY_RE.test(text)) throw new ServiceError(400, 'invalid_birthday', 'Use a month and day, like 03-14.');
  return text;
};

// ---------- The plan (pure) ----------

const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

/** The words for one nudge. Pure. Never mentions texting. */
const messageFor = (type, { venueName, bonusPoints = 0, reward = null, coupon = null }) => {
  const store = venueName || 'your store';
  switch (type) {
    case 'winBack':
      if (coupon) {
        return {
          title: `We miss you at ${store}`,
          body: `${coupon.title} — it's yours, saved in FavCircles${bonusPoints > 0 ? `, and your next purchase earns +${bonusPoints} bonus points too` : ''}. Scan the register code when you're in and show the ticket.`
        };
      }
      return {
        title: `We miss you at ${store}`,
        body: bonusPoints > 0
          ? `Come back soon — your next purchase earns +${bonusPoints} bonus points on top of the usual.`
          : `It's been a while. Your points here are waiting for your next visit.`
      };
    case 'couponEnding': {
      const when = coupon && coupon.expiresAt ? new Date(coupon.expiresAt).toLocaleDateString('en-US', { weekday: 'long', timeZone: 'America/New_York' }) : 'soon';
      return {
        title: coupon ? `Your ${coupon.title} at ${store} ends ${when}` : `Your coupon at ${store} ends ${when}`,
        body: `It's saved in FavCircles and on your ${store} Wallet card: scan the register code when you're in and show the ticket.${coupon && coupon.onlineCode ? ` Ordering online? Use code ${coupon.onlineCode}.` : ''}`
      };
    }
    case 'birthday':
      return {
        title: `Happy birthday from ${store}!`,
        body: bonusPoints > 0
          ? `Celebrate with us: +${bonusPoints} bonus points on your next purchase this month.`
          : `Come celebrate with us — we'd love to see you.`
      };
    case 'almostThere':
      return {
        title: reward ? `One more visit to ${article(reward.title)}` : `One more visit to your reward`,
        body: reward
          ? `You're ${plural(reward.remaining, 'point')} from ${article(reward.title)} at ${store}. One more purchase does it.`
          : `One more purchase at ${store} and your reward is ready.`
      };
    default:
      return { title: store, body: '' };
  }
};

/**
 * Which customers get which nudge today. Pure. `customers` rows carry the
 * bucket (points, purchases, lastScanAt, removed, lastNudgeAt) and the
 * person's birthday (MM-DD) and time zone. One nudge per customer, the
 * most time-sensitive first: birthday, almost there, win-back.
 */
const planNudges = ({ venue, settings, customers = [], claims = [], now = new Date() }) => {
  const nowMs = now.getTime();
  const gapBefore = new Date(nowMs - NUDGE_GAP_DAYS * DAY_MS).toISOString();
  const earnRate = require('./rewardService').effectiveEarnRate(venue);
  const coupons = require('./storeCoupons');
  // The win-back's coupon, only while the store still offers it
  const winBackCoupon = settings.winBack.couponId ? coupons.findCoupon(venue, settings.winBack.couponId) : null;
  const winBackCouponLive = winBackCoupon && coupons.claimVerdict({ coupon: winBackCoupon, counts: coupons.countsOf(venue, winBackCoupon.couponId), now }) === 'ok';
  const plan = [];
  for (const c of customers) {
    if (c.removed) continue;
    if (c.lastNudgeAt && String(c.lastNudgeAt) >= gapBefore) continue;
    const year = localDateKey(c.timeZone || null, now).slice(0, 4);
    const today = localDateKey(c.timeZone || null, now).slice(5);

    if (settings.birthday.enabled && c.birthday && c.birthday === today) {
      plan.push({
        userId: c.userId, type: 'birthday', key: `birthday_${year}`,
        bonusPoints: settings.birthday.bonusPoints,
        message: messageFor('birthday', { venueName: venue.venueName, bonusPoints: settings.birthday.bonusPoints })
      });
      continue;
    }
    if (settings.almostThere.enabled) {
      const reward = nextReward(venue.offers, c.points || 0, earnRate);
      if (reward && !reward.canRedeem && reward.visitsLeft === 1) {
        plan.push({
          userId: c.userId, type: 'almostThere', key: `almost_${c.points || 0}`, bonusPoints: 0,
          message: messageFor('almostThere', { venueName: venue.venueName, reward })
        });
        continue;
      }
    }
    if (settings.winBack.enabled && (c.purchases || 0) >= 1 && c.lastScanAt) {
      const quietSince = new Date(nowMs - settings.winBack.days * DAY_MS).toISOString();
      if (String(c.lastScanAt) < quietSince) {
        const coupon = winBackCouponLive ? coupons.publicCoupon(winBackCoupon) : null;
        plan.push({
          userId: c.userId, type: 'winBack', key: `winBack_${String(c.lastScanAt).slice(0, 10)}`,
          bonusPoints: settings.winBack.bonusPoints,
          ...(coupon ? { couponId: coupon.couponId } : {}),
          message: messageFor('winBack', { venueName: venue.venueName, bonusPoints: settings.winBack.bonusPoints, coupon })
        });
      }
    }
  }
  // A claimed, unused coupon ending within 3 days: said once per coupon,
  // whatever else the person was told lately (it can't wait 14 days)
  const removed = new Set(customers.filter((c) => c.removed).map((c) => c.userId));
  const endingBefore = new Date(nowMs + COUPON_ENDING_DAYS * DAY_MS).toISOString();
  const nowIso = now.toISOString();
  for (const claim of claims) {
    if (!coupons.isOpen(claim, now) || removed.has(String(claim.userId))) continue;
    if (!claim.expiresAt || String(claim.expiresAt) > endingBefore || String(claim.expiresAt) <= nowIso) continue;
    plan.push({
      userId: String(claim.userId), type: 'couponEnding', key: `couponEnd_${claim.couponId}`, bonusPoints: 0, timeBound: true,
      message: messageFor('couponEnding', { venueName: venue.venueName, coupon: claim })
    });
  }
  return plan;
};

/**
 * The bonus a visit pays on top of the earn rate. Pure. A bonus past its
 * expiry pays nothing but is still cleared.
 */
const applyPendingBonus = (bucket, now = new Date()) => {
  const pending = bucket && bucket.pendingBonus;
  if (!pending || typeof pending !== 'object') return { bonus: 0, consume: false };
  const live = !pending.expiresAt || String(pending.expiresAt) > now.toISOString();
  const points = Number.isInteger(pending.points) && pending.points > 0 ? pending.points : 0;
  return { bonus: live ? points : 0, consume: true };
};

// ---------- Loading ----------

const field = (venueId, name) => `rewardPointsByVenue.${venueId}.${name}`;

/** Everyone with a bucket at the store, with what the plan and the send need. Read-only. */
async function loadCustomers(venue) {
  const { isHiddenAccount } = require('./hiddenAccounts');
  const { countsFromLedger } = require('./storeCustomers');
  const snap = await db().collection(COLLECTIONS.USERS)
    .where(field(venue.venueId, 'points'), '>=', 0).limit(MAX_CUSTOMERS).get();
  const rows = [];
  for (const doc of snap.docs) {
    const user = doc.data();
    if (isHiddenAccount(user)) continue;
    let bucket = ((user.rewardPointsByVenue || {})[venue.venueId]) || {};
    if (!bucket.countsBackfilled) bucket = { ...bucket, ...(await countsFromLedger(doc.id, venue.venueId)) };
    rows.push({
      userId: doc.id,
      points: bucket.points || 0,
      purchases: bucket.purchases || 0,
      lastScanAt: bucket.lastScanAt || null,
      removed: !!bucket.removedFromRewards,
      lastNudgeAt: bucket.lastNudgeAt || null,
      birthday: user.birthday || null,
      timeZone: (user.notificationPreferences && user.notificationPreferences.timezone) || null,
      user
    });
  }
  return rows;
}

// ---------- Delivery ----------

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const emailHtml = ({ title, body, venueName, unsub }) => `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#EEF1F6;">
  <div style="max-width:520px;margin:0 auto;padding:28px 20px;font-family:-apple-system,Helvetica,Arial,sans-serif;color:#0F1E3A;">
    <div style="background:#fff;border-radius:14px;padding:26px 24px;">
      <p style="margin:0 0 6px;font-size:13px;color:#6B7280;">A note from ${esc(venueName)} on FavCircles</p>
      <h1 style="margin:0 0 12px;font-size:22px;">${esc(title)}</h1>
      <p style="margin:0 0 18px;font-size:16px;line-height:1.55;">${esc(body)}</p>
      <a href="https://api.favcircles.com/app/open?path=rewards" style="display:inline-block;background:#3478F6;color:#fff;text-decoration:none;font-weight:600;padding:12px 18px;border-radius:10px;">Open my rewards</a>
    </div>
    <p style="font-size:12px;color:#6B7280;text-align:center;margin:18px 0 0;">
      You get this because you earn rewards at ${esc(venueName)} in FavCircles.
      <a href="${unsub}" style="color:#6B7280;">Stop these emails</a>
    </p>
  </div>
</body></html>`;

/** How this person can be reached for a store's nudge: 'push' | 'email' | null. */
const channelFor = (user) => {
  if (user.notificationPreferences && user.notificationPreferences.storeAlerts === false) return null;
  if (require('./emailFallback').pushReachable(user)) return 'push';
  const email = String(user.email || '').trim();
  if (!email.includes('@') || email.endsWith('@privaterelay.appleid.com')) return null;
  if (user.emailPreferences && user.emailPreferences[EMAIL_KIND] === false) return null;
  return 'email';
};

async function deliver(venue, globalPlaceId, nudge, customer, now) {
  const channel = channelFor(customer.user);
  if (!channel) return 'unreachable';
  const sendRef = db().collection(SENDS).doc(`${venue.venueId}_${nudge.userId}_${nudge.key}`);
  try {
    await sendRef.create({
      venueId: venue.venueId, userId: nudge.userId, type: nudge.type, key: nudge.key,
      bonusPoints: nudge.bonusPoints || 0, channel, sentAt: now.toISOString()
    });
  } catch (error) {
    if (error.code === 6 || /already exists/i.test(error.message || '')) return 'duplicate';
    throw error;
  }

  if (channel === 'push') {
    // Awaited, not fire-and-forget: sendToUser DROPS a push inside the
    // person's quiet hours, and a nudge keyed per quiet spell would never
    // come back. Deferred = no send doc, no bucket stamp; tomorrow's run
    // plans it again.
    const outcome = await require('./notificationService').sendToUser(nudge.userId, {
      type: 'store_nudge',
      title: nudge.message.title,
      body: nudge.message.body,
      data: { type: 'store_nudge', venueId: venue.venueId, placeId: globalPlaceId || null, automation: nudge.type }
    });
    if (outcome && outcome.success === false) {
      await sendRef.delete().catch(() => {});
      return /quiet hours/i.test(outcome.error || '') ? 'deferred' : 'unreachable';
    }
  } else {
    const { unsubscribeUrl } = require('./followSuggestionEmailService');
    const unsub = unsubscribeUrl(nudge.userId, EMAIL_KIND);
    await require('./emailService').sendEmail({
      to: customer.user.email,
      subject: nudge.message.title,
      html: emailHtml({ ...nudge.message, venueName: venue.venueName || 'your store', unsub }),
      text: `${nudge.message.title}\n\n${nudge.message.body}\n\nOpen my rewards: https://api.favcircles.com/app/open?path=rewards\nStop these emails: ${unsub}`,
      headers: { 'List-Unsubscribe': `<${unsub}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' },
      // Tracked by nudge type (services/emailTracking): store_win_back, store_coupon_ending…
      kind: `store_${String(nudge.type).replace(/[A-Z]/g, (m) => `_${m.toLowerCase()}`)}`
    });
  }

  // A win-back's coupon: claimed for them now, so it's on their card when they come in
  if (nudge.couponId) {
    await require('./storeCoupons').claim({ venue, couponId: nudge.couponId, userId: nudge.userId, via: 'win_back', now })
      .catch((e) => console.warn(`coupon for win-back (${venue.venueName} → ${nudge.userId}): ${e.message}`));
  }

  // A time-bound nudge (a coupon ending) isn't the customer's one nudge for
  // the fortnight; everything else stamps the bucket (field-path pairs, so
  // sibling fields stay)
  if (nudge.timeBound) return channel;
  const bucketUpdate = [field(venue.venueId, 'lastNudgeAt'), now.toISOString()];
  if (nudge.bonusPoints > 0) {
    bucketUpdate.push(field(venue.venueId, 'pendingBonus'), {
      points: nudge.bonusPoints, automation: nudge.type,
      expiresAt: new Date(now.getTime() + BONUS_TTL_DAYS * DAY_MS).toISOString()
    });
  }
  await db().collection(COLLECTIONS.USERS).doc(nudge.userId).update(...bucketUpdate);
  return channel;
}

/**
 * The daily run: every active Business store with an automation on. With
 * `dryRun`, nothing is sent or written — the answer lists what would go.
 */
async function runDue({ now = new Date(), dryRun = false } = {}) {
  const { isVenueBusinessLive } = require('./ownerSubscriptionService');
  const { venueGlobalPlaceId } = require('./venueHelpers');
  const snapshot = await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).where('active', '==', true).get();
  const summary = { dryRun, venues: 0, lapsed: 0, planned: 0, sent: { push: 0, email: 0 }, unreachable: 0, deferred: 0, duplicate: 0, byType: {}, would: [] };
  for (const doc of snapshot.docs) {
    const venue = { venueId: doc.id, ...doc.data() };
    const settings = settingsOf(venue);
    const hasCoupons = require('./storeCoupons').liveCoupons(venue).length > 0;
    if (!anyEnabled(settings) && !hasCoupons) continue;
    if (!(await isVenueBusinessLive(venue))) { summary.lapsed++; continue; }
    summary.venues++;
    const customers = await loadCustomers(venue);
    // Open claims ending soon: the "ends Sunday" reminder (services/storeCoupons)
    const claims = hasCoupons ? await require('./storeCoupons').claimsForVenue(venue.venueId).catch(() => []) : [];
    const plan = planNudges({ venue, settings, customers, claims, now });
    summary.planned += plan.length;
    if (!plan.length) continue;
    const globalPlaceId = dryRun ? null : await venueGlobalPlaceId(venue);
    const byUser = new Map(customers.map((c) => [c.userId, c]));
    // Someone who claimed a coupon but never bought here has no bucket row yet
    for (const nudge of plan) {
      if (!byUser.has(nudge.userId)) {
        const userDoc = await db().collection(COLLECTIONS.USERS).doc(nudge.userId).get().catch(() => null);
        if (userDoc && userDoc.exists) byUser.set(nudge.userId, { userId: nudge.userId, user: userDoc.data() });
      }
    }
    for (const nudge of plan) {
      const customer = byUser.get(nudge.userId);
      if (!customer) continue;
      summary.byType[nudge.type] = (summary.byType[nudge.type] || 0) + 1;
      if (dryRun) {
        summary.would.push({ venue: venue.venueName, userId: nudge.userId, type: nudge.type, key: nudge.key, bonusPoints: nudge.bonusPoints, couponId: nudge.couponId || null, channel: channelFor(customer.user) });
        continue;
      }
      try {
        const outcome = await deliver(venue, globalPlaceId, nudge, customer, now);
        if (outcome === 'push' || outcome === 'email') summary.sent[outcome]++;
        else summary[outcome]++;
      } catch (error) {
        console.error(`❌ store nudge failed (${venue.venueName} → ${nudge.userId} ${nudge.type}): ${error.message}`);
      }
    }
  }
  return summary;
}

// ---------- The owner's results ----------

/** Per automation: how many were sent, how many of those bought again since. */
async function stats(venue) {
  const snap = await db().collection(SENDS).where('venueId', '==', venue.venueId).get();
  const sends = snap.docs.map((d) => d.data()).sort((a, b) => String(b.sentAt).localeCompare(String(a.sentAt))).slice(0, 500);
  const result = {};
  TYPES.forEach((t) => { result[t] = { sent: 0, cameBack: 0 }; });
  if (!sends.length) return result;
  const ids = [...new Set(sends.map((s) => s.userId))];
  const lastScan = new Map();
  for (let i = 0; i < ids.length; i += 100) {
    const docs = await db().getAll(...ids.slice(i, i + 100).map((id) => db().collection(COLLECTIONS.USERS).doc(id)));
    docs.forEach((d) => {
      if (!d.exists) return;
      const bucket = ((d.data().rewardPointsByVenue || {})[venue.venueId]) || {};
      lastScan.set(d.id, bucket.lastScanAt || null);
    });
  }
  sends.forEach((s) => {
    if (!result[s.type]) return;
    result[s.type].sent += 1;
    const last = lastScan.get(s.userId);
    if (last && String(last) > String(s.sentAt)) result[s.type].cameBack += 1;
  });
  return result;
}

module.exports = {
  DEFAULTS, WIN_BACK_DAYS, NUDGE_GAP_DAYS, BONUS_TTL_DAYS, COUPON_ENDING_DAYS, EMAIL_KIND, TYPES, SENDS,
  settingsOf, normalizeSettings, anyEnabled, normalizeBirthday,
  messageFor, planNudges, applyPendingBonus, channelFor,
  loadCustomers, runDue, stats
};
