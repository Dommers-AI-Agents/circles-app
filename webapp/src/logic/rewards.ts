// Rules for store rewards: reading a scanned or typed code, the words for
// what a scan did, how far a balance is from the next reward, a ticket's
// countdown. Pure. The server's rewardProgress.js and the store web page
// (backend/public/store-page.js) hold the same rules; keep them agreeing.
import type { CouponClaim, HistoryRow, NextReward, RewardEvent, ScanInput, ScanResult, Voucher } from '../api/rewards';

export const pointsWord = (n: number): string => (n === 1 ? 'point' : 'points');
export const pointsText = (n: number): string => `${n} ${pointsWord(n)}`;

// ---- a scanned link or a typed code

const CODE = /^[A-Z0-9]{6}$/;
const HOSTS = ['api.favcircles.com', 'favcircles.com', 'www.favcircles.com', 'app.favcircles.com', 'localhost'];

/**
 * A FavCircles store link (https://api.favcircles.com/s/<code>?t=&c=&ref=)
 * or the 6 characters printed under the QR. null for anything else, so a
 * menu's QR or a stranger's link never reaches the server as a code.
 */
export function parseScanInput(raw: string): ScanInput | null {
  const text = String(raw || '').trim();
  if (!text) return null;
  const typed = text.replace(/[\s-]/g, '').toUpperCase();
  if (CODE.test(typed)) return { code: typed };
  let url: URL;
  try {
    url = new URL(/^https?:\/\//i.test(text) ? text : `https://${text}`);
  } catch {
    return null;
  }
  if (!HOSTS.includes(url.hostname.toLowerCase())) return null;
  const match = url.pathname.match(/^\/s\/([A-Za-z0-9]{6})\/?$/);
  if (!match) return null;
  const input: ScanInput = { code: match[1].toUpperCase() };
  const t = url.searchParams.get('t');
  const c = url.searchParams.get('c');
  const ref = url.searchParams.get('ref');
  if (t) input.t = t;
  if (c) input.c = c;
  if (ref) input.ref = ref;
  return input;
}

// ---- what a scan did

export interface ScanOutcome {
  /** The headline, e.g. "Saved." */
  title: string;
  /** The gold part of the headline, e.g. "+25 points." */
  gain: string;
  detail: string;
}

/**
 * The words for a scan's answer. Points are only ever mentioned when the
 * server says the store's rewards are live (it sends an earn rate or an
 * award); a store with no live rewards is just "on your list".
 */
export function scanOutcome(data: ScanResult, storeName: string): ScanOutcome {
  const name = storeName || 'this store';
  const points = data.awarded ? data.awarded.points : 0;
  const rate = data.loyaltyLive && data.earnRate && data.earnRate > 0 ? data.earnRate : 0;
  if (data.kind === 'generic' || !data.venue) {
    return { title: "That code isn't a store's.", gain: '', detail: 'It is the code for joining FavCircles, and you are already in. Scan the code at a store to save it.' };
  }
  if (data.kind === 'register') {
    if (points > 0) return { title: 'Thanks for coming in.', gain: `+${pointsText(points)}.`, detail: '' };
    if (data.notAtStore) {
      return { title: 'No points this time.', gain: '', detail: `Points are for visits to ${name}. Scan the code at the register when you are there.` };
    }
    if (data.alreadyEarnedToday) return { title: "You already got today's points.", gain: '', detail: 'Come back tomorrow for more.' };
    if (data.removedFromRewards) {
      return { title: 'No points this time.', gain: '', detail: `${name} has taken you off its rewards. Ask at the counter if that's a mistake.` };
    }
    if (data.loyaltyPaused) {
      return {
        title: 'No points this time.',
        gain: '',
        detail: data.loyaltyState === 'not_started' ? `${name} hasn't started its rewards yet.` : `Rewards at ${name} are paused right now.`
      };
    }
    return { title: 'No points this time.', gain: '', detail: '' };
  }
  // The window code: saving the store
  if (data.savePending) {
    return { title: 'Almost there.', gain: '', detail: `We're still setting up your list. Enter the code again in a moment to save ${name}.` };
  }
  if (points > 0) {
    return { title: 'Saved.', gain: `+${pointsText(points)}.`, detail: rate ? `Scan the code at the register each visit for ${rate} more.` : '' };
  }
  return {
    title: data.alreadySaved && !data.saved ? 'Welcome back.' : 'Saved.',
    gain: '',
    detail: rate ? `Scan the code at the register each visit for ${pointsText(rate)}.` : `${name} is on your list.`
  };
}

/** The line about the coupon a scan link carried (iOS StoreCouponCopy.scanLine). */
export function scanCouponLine(data: ScanResult, storeName: string): string | null {
  const result = data.coupon;
  if (!result) return null;
  const title = (result.coupon && result.coupon.title) || (result.claim && result.claim.title) || (result.voucher && result.voucher.offerTitle) || '';
  const named = (words: string, bare: string) => (title ? words : bare);
  switch (result.status) {
    case 'ticket':
      return title ? `Your coupon is open: ${title}. Show the ticket at the counter.` : null;
    case 'claimed':
      return title ? `Your coupon is saved: ${title}. Scan the code at the register when you're there to use it.` : null;
    case 'already': {
      if (!title) return null;
      const status = result.claim && result.claim.status;
      if (status === 'used') return `You've already used this coupon (${title}).`;
      if (status === 'expired') return `That coupon (${title}) has ended.`;
      return `You already have this coupon: ${title}.`;
    }
    case 'expired': return named(`That coupon (${title}) has ended.`, 'That coupon has ended.');
    case 'full': return named(`That coupon (${title}) has all been claimed.`, 'That coupon has all been claimed.');
    case 'paused': return named(`${storeName} has paused that coupon (${title}).`, `${storeName} has paused that coupon.`);
    default: return null;
  }
}

// ---- how far a balance is from a reward

type LadderOffer = { offerId?: string; title: string; pointsCost: number; active?: boolean };

/** Live offers, cheapest first; never the ones switched off or free. */
export function rewardLadder<T extends LadderOffer>(offers: T[] | undefined | null): T[] {
  return (offers || [])
    .filter((o) => o && o.active !== false && Number.isInteger(o.pointsCost) && o.pointsCost > 0 && !!o.title)
    .sort((a, b) => a.pointsCost - b.pointsCost);
}

/**
 * The cheapest reward still out of reach; or, once something is affordable,
 * the best one they can take now. null when the store has posted none.
 */
export function nextReward(offers: LadderOffer[] | undefined | null, points: number, earnRate?: number | null): NextReward | null {
  const ladder = rewardLadder(offers);
  if (!ladder.length) return null;
  const have = Math.max(0, Number(points) || 0);
  const affordable = ladder.filter((o) => o.pointsCost <= have);
  if (affordable.length) {
    const best = affordable[affordable.length - 1];
    return { offerId: best.offerId, title: best.title, pointsCost: best.pointsCost, remaining: 0, visitsLeft: 0, canRedeem: true };
  }
  const next = ladder[0];
  const remaining = next.pointsCost - have;
  const rate = Number(earnRate);
  return {
    offerId: next.offerId, title: next.title, pointsCost: next.pointsCost, remaining,
    visitsLeft: Number.isFinite(rate) && rate > 0 ? Math.ceil(remaining / rate) : null, canRedeem: false
  };
}

/** How full the bar is, 0 to 1. */
export function rewardFraction(reward: NextReward | null | undefined, points: number): number {
  if (!reward || !(reward.pointsCost > 0)) return 0;
  if (reward.canRedeem) return 1;
  return Math.min(1, Math.max(0, (Number(points) || 0) / reward.pointsCost));
}

/** "Free coffee" → "a free coffee"; titles already starting with a/an/the/your keep theirs. */
export function article(title: string): string {
  const t = String(title || '').trim();
  if (!t) return t;
  const lower = t.toLowerCase();
  if (['a ', 'an ', 'the ', 'your ', 'free!'].some((p) => lower.startsWith(p))) return t;
  return `${'aeiou'.includes(lower[0]) ? 'an' : 'a'} ${t[0].toLowerCase()}${t.slice(1)}`;
}

/** "75 more points for a free coffee · about 3 more purchases" */
export function nextRewardLine(reward: NextReward | null | undefined): string {
  if (!reward) return '';
  if (reward.canRedeem) return `Ready: ${reward.title}. Redeem it at the counter.`;
  let line = `${reward.remaining} more ${pointsWord(reward.remaining)} for ${article(reward.title)}`;
  if (reward.visitsLeft && reward.visitsLeft > 0) line += ` · about ${reward.visitsLeft} more ${reward.visitsLeft === 1 ? 'purchase' : 'purchases'}`;
  return line;
}

// ---- a counter ticket

/** Whole seconds a ticket has left (0 once it has run out). */
export function secondsLeft(expiresAt: string | undefined, now: number): number {
  const end = Date.parse(expiresAt || '');
  if (!Number.isFinite(end)) return 0;
  return Math.max(0, Math.floor((end - now) / 1000));
}

/** "14:05" */
export function countdownText(seconds: number): string {
  const left = Math.max(0, Math.floor(seconds));
  const s = left % 60;
  return `${Math.floor(left / 60)}:${s < 10 ? '0' : ''}${s}`;
}

/** A coupon's ticket cost no points, so none come back when it runs out. */
export const isCouponTicket = (voucher: Pick<Voucher, 'couponId' | 'pointsCost'>): boolean =>
  !!voucher.couponId || voucher.pointsCost === 0;

/** What happens when the time runs out with no "Given" tap. */
export function ticketRanOutLine(voucher: Pick<Voucher, 'couponId' | 'pointsCost' | 'venueName'>, storeName?: string): string {
  const store = storeName || voucher.venueName || 'the store';
  if (isCouponTicket(voucher)) {
    return `This coupon wasn't marked as given, so it's still yours at ${store}. Open it again when you're at the counter.`;
  }
  return voucher.pointsCost && voucher.pointsCost > 0
    ? `This reward wasn't marked as given, so your ${pointsText(voucher.pointsCost)} are back at ${store}.`
    : `This reward wasn't marked as given, so your points are back at ${store}.`;
}

/** A past ticket, in a word. */
export function voucherStatusLine(voucher: Voucher): string {
  if (voucher.status === 'given') return 'Given';
  if (voucher.status === 'expired') return isCouponTicket(voucher) ? 'Ran out · coupon kept' : 'Ran out · points back';
  return 'Open';
}

// ---- coupons

export const isOpenCoupon = (coupon: CouponClaim): boolean => coupon.status === 'claimed' || coupon.status === 'ticket';

// ---- history

/** One line of the points ledger, as the customer reads it (backend rewardHistoryService.historyRow). */
export function historyRowOf(event: RewardEvent): HistoryRow | null {
  const points = Number(event.points) || 0;
  const base = { at: event.createdAt, points };
  switch (event.type) {
    case 'venue_visit': return { ...base, kind: 'earn', title: event.via === 'delivery_receipt' ? 'Delivery order' : 'Visit' };
    case 'sticker_save': return { ...base, kind: 'earn', title: 'Saved the store' };
    case 'sticker_signup': return { ...base, kind: 'earn', title: 'Joined at the store' };
    case 'share_conversion': return { ...base, kind: 'earn', title: 'A friend saved it from your share' };
    case 'code_redemption': return { ...base, kind: 'earn', title: 'Reward code' };
    case 'redemption':
      return { ...base, points: -Math.abs(points), kind: event.status === 'expired' ? 'expired' : 'redeem', title: event.offerTitle || 'Reward' };
    case 'redemption_refund': return { ...base, kind: 'refund', title: `Points back · ${event.offerTitle || 'reward'}` };
    case 'coupon_redemption': return { ...base, points: 0, kind: event.status === 'expired' ? 'expired' : 'redeem', title: `Coupon · ${event.offerTitle || 'coupon'}` };
    default: return null;
  }
}

/** "+25", "−100", "" for a row that moved no points. */
export function signedPoints(points: number): string {
  if (!points) return '';
  return points > 0 ? `+${points}` : `−${Math.abs(points)}`;
}

// ---- coupons, as the customer reads them (iOS StoreCouponCopy)

const DAY_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const shortDay = (iso: string | null | undefined, now: Date): string => {
  const at = new Date(String(iso || ''));
  if (Number.isNaN(at.getTime())) return '';
  const text = `${DAY_MONTHS[at.getMonth()]} ${at.getDate()}`;
  return at.getFullYear() === now.getFullYear() ? text : `${text}, ${at.getFullYear()}`;
};

/** "10% off any loaf · Ends Dec 5 · Online code SAL10" */
export function couponDetail(coupon: CouponClaim, now: Date = new Date()): string {
  const parts: string[] = [];
  if (coupon.detail) parts.push(coupon.detail);
  if (coupon.status === 'used') {
    const day = shortDay(coupon.usedAt, now);
    parts.push(day ? `Used ${day}` : 'Used');
  } else if (coupon.status === 'ticket') {
    parts.push('Ticket open · show it at the counter');
  } else if (coupon.expiresAt) {
    const day = shortDay(coupon.expiresAt, now);
    if (day) parts.push(`${new Date(coupon.expiresAt).getTime() < now.getTime() ? 'Ended' : 'Ends'} ${day}`);
  }
  if (isOpenCoupon(coupon) && coupon.onlineCode) parts.push(`Online code ${coupon.onlineCode}`);
  return parts.join(' · ');
}

/** The button on an open coupon; null when it can't be used. */
export function couponAction(coupon: CouponClaim): string | null {
  if (coupon.status === 'claimed') return 'Use at the register';
  if (coupon.status === 'ticket') return 'Show ticket';
  return null;
}

export const COUPON_USE_EXPLAINER =
  "Opens a 15-minute ticket to show at the counter. Staff tap Given on it. If it isn't used in time, the coupon stays yours.";

/** "This uses 100 of your points at Sal's and opens a 15-minute ticket…" */
export function redeemExplainer(pointsCost: number, storeName: string): string {
  return `This uses ${pointsCost} of your points at ${storeName || 'this store'} and opens a 15-minute ticket to show at the counter. If it isn’t used in time, your points come back.`;
}

// ---- my stores

/** The store just earned at leads, then the most points (iOS "Your rewards by store"). */
export function orderBalances<T extends { venueId: string; points: number }>(balances: T[] | null | undefined, leadVenueId?: string | null): T[] {
  return (balances || []).slice().sort((a, b) => {
    const lead = (x: T) => (leadVenueId && x.venueId === leadVenueId ? 0 : 1);
    return lead(a) - lead(b) || (b.points || 0) - (a.points || 0);
  });
}

/** "120 more points" when an offer is out of reach. */
export function shortByText(pointsCost: number, have: number): string {
  const missing = Math.max(0, pointsCost - Math.max(0, Number(have) || 0));
  return `${missing} more ${pointsWord(missing)}`;
}

/** Find a store's place from anything that lists it (balances, the offers list). */
export function placeOfVenue(venueId: string, ...lists: ({ venueId: string; globalPlaceId?: string | null }[] | null | undefined)[]): string | null {
  for (const list of lists) {
    const found = (list || []).find((row) => row && row.venueId === venueId && row.globalPlaceId);
    if (found && found.globalPlaceId) return found.globalPlaceId;
  }
  return null;
}
