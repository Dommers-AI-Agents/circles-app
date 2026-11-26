import { describe, expect, it } from 'vitest';
import type { CouponClaim, ScanResult } from '../api/rewards';
import {
  article, couponAction, couponDetail, countdownText, orderBalances, placeOfVenue, redeemExplainer, shortByText, historyRowOf, isCouponTicket, nextReward, nextRewardLine, parseScanInput, rewardFraction,
  rewardLadder, scanCouponLine, scanOutcome, secondsLeft, signedPoints, ticketRanOutLine, voucherStatusLine
} from './rewards';

const venue = { venueId: 'v1', venueName: 'Sal’s Bakery' };

describe('a scanned link or a typed code', () => {
  it('takes the 6 characters, however they were typed', () => {
    expect(parseScanInput('5gjrc2')).toEqual({ code: '5GJRC2' });
    expect(parseScanInput(' 5GJ RC2 ')).toEqual({ code: '5GJRC2' });
    expect(parseScanInput('5GJ-RC2')).toEqual({ code: '5GJRC2' });
  });
  it('reads a store link with its tag, coupon and inviter', () => {
    expect(parseScanInput('https://api.favcircles.com/s/g4bq5b')).toEqual({ code: 'G4BQ5B' });
    expect(parseScanInput('https://api.favcircles.com/s/5GJRC2?t=ab12&c=FALL10&ref=u9'))
      .toEqual({ code: '5GJRC2', t: 'ab12', c: 'FALL10', ref: 'u9' });
    expect(parseScanInput('api.favcircles.com/s/5GJRC2/')).toEqual({ code: '5GJRC2' });
  });
  it('refuses anything that is not a FavCircles store code', () => {
    expect(parseScanInput('')).toBeNull();
    expect(parseScanInput('12345')).toBeNull();
    expect(parseScanInput('https://example.com/s/5GJRC2')).toBeNull();
    expect(parseScanInput('https://api.favcircles.com/place/abc')).toBeNull();
    expect(parseScanInput('https://api.favcircles.com/q/5GJRC2')).toBeNull();
    expect(parseScanInput('WIFI:S:cafe;P:secret;;')).toBeNull();
  });
});

describe('what a scan did', () => {
  const base: ScanResult = { kind: 'window', venue, loyaltyLive: true, earnRate: 25 };
  it('window: saved with the bonus, saved, or welcome back', () => {
    expect(scanOutcome({ ...base, saved: true, awarded: { type: 'sticker_save', points: 20 } }, 'Sal’s'))
      .toEqual({ title: 'Saved.', gain: '+20 points.', detail: 'Scan the code at the register each visit for 25 more.' });
    expect(scanOutcome({ ...base, saved: true }, 'Sal’s').title).toBe('Saved.');
    expect(scanOutcome({ ...base, alreadySaved: true, saved: false }, 'Sal’s'))
      .toEqual({ title: 'Welcome back.', gain: '', detail: 'Scan the code at the register each visit for 25 points.' });
  });
  it('never mentions points at a store whose rewards are not live', () => {
    const outcome = scanOutcome({ kind: 'window', venue, saved: true, loyaltyLive: false, earnRate: 25 }, 'Sal’s');
    expect(outcome).toEqual({ title: 'Saved.', gain: '', detail: 'Sal’s is on your list.' });
    expect(JSON.stringify(scanOutcome({ kind: 'window', venue, saved: true, loyaltyLive: false }, 'Sal’s'))).not.toMatch(/point/i);
  });
  it('window: a save still being set up asks for another try', () => {
    expect(scanOutcome({ ...base, savePending: true }, 'Sal’s').title).toBe('Almost there.');
  });
  it('register: every answer the server gives', () => {
    const register: ScanResult = { ...base, kind: 'register' };
    expect(scanOutcome({ ...register, awarded: { type: 'venue_visit', points: 25 } }, 'Sal’s'))
      .toEqual({ title: 'Thanks for coming in.', gain: '+25 points.', detail: '' });
    expect(scanOutcome({ ...register, awarded: { type: 'venue_visit', points: 1 } }, 'Sal’s').gain).toBe('+1 point.');
    expect(scanOutcome({ ...register, alreadyEarnedToday: true }, 'Sal’s').title).toBe("You already got today's points.");
    expect(scanOutcome({ ...register, notAtStore: true }, 'Sal’s').detail).toContain('when you are there');
    expect(scanOutcome({ ...register, removedFromRewards: true }, 'Sal’s').detail).toContain('taken you off its rewards');
    expect(scanOutcome({ ...register, loyaltyLive: false, loyaltyPaused: true, loyaltyState: 'paused' }, 'Sal’s').detail)
      .toBe('Rewards at Sal’s are paused right now.');
    expect(scanOutcome({ ...register, loyaltyLive: false, loyaltyPaused: true, loyaltyState: 'not_started' }, 'Sal’s').detail)
      .toBe("Sal’s hasn't started its rewards yet.");
  });
  it('the join code is not a store', () => {
    expect(scanOutcome({ kind: 'generic', generic: true, venue }, '').title).toBe("That code isn't a store's.");
  });
  it('says what happened to a coupon', () => {
    const coupon = { title: '10% off' };
    expect(scanCouponLine({ ...base, coupon: { status: 'claimed', coupon } }, 'Sal’s')).toContain('Your coupon is saved: 10% off.');
    expect(scanCouponLine({ ...base, coupon: { status: 'already', coupon, claim: { claimId: 'c', venueId: 'v1', title: '10% off', status: 'used' } } }, 'Sal’s'))
      .toBe("You've already used this coupon (10% off).");
    expect(scanCouponLine({ ...base, coupon: { status: 'full', coupon } }, 'Sal’s')).toBe('That coupon (10% off) has all been claimed.');
    expect(scanCouponLine({ ...base, coupon: { status: 'paused', coupon: null } }, 'Sal’s')).toBe('Sal’s has paused that coupon.');
    expect(scanCouponLine({ ...base, coupon: { status: 'ticket', voucher: { voucherId: 'x', voucherCode: 'K7', offerTitle: '10% off', expiresAt: '' } } }, 'Sal’s'))
      .toContain('Show the ticket at the counter');
    expect(scanCouponLine(base, 'Sal’s')).toBeNull();
  });
});

describe('how far a balance is from a reward', () => {
  const offers = [
    { offerId: 'b', title: 'Free croissant', pointsCost: 150 },
    { offerId: 'a', title: 'Free drip coffee', pointsCost: 100 },
    { offerId: 'off', title: 'Old one', pointsCost: 10, active: false },
    { offerId: 'zero', title: 'Nothing', pointsCost: 0 }
  ];
  it('orders the ladder cheapest first and drops switched-off and free ones', () => {
    expect(rewardLadder(offers).map((o) => o.offerId)).toEqual(['a', 'b']);
  });
  it('works toward the cheapest reward out of reach', () => {
    const next = nextReward(offers, 20, 25);
    expect(next).toMatchObject({ offerId: 'a', remaining: 80, visitsLeft: 4, canRedeem: false });
    expect(rewardFraction(next, 20)).toBeCloseTo(0.2);
    expect(nextRewardLine(next)).toBe('80 more points for a free drip coffee · about 4 more purchases');
  });
  it('once something is affordable, names the best one they can take', () => {
    const next = nextReward(offers, 160, 25);
    expect(next).toMatchObject({ offerId: 'b', remaining: 0, canRedeem: true });
    expect(rewardFraction(next, 160)).toBe(1);
    expect(nextRewardLine(next)).toBe('Ready: Free croissant. Redeem it at the counter.');
  });
  it('has nothing to say when the store posted no rewards', () => {
    expect(nextReward([], 50, 25)).toBeNull();
    expect(nextReward(undefined, 50)).toBeNull();
    expect(rewardFraction(null, 50)).toBe(0);
    expect(nextRewardLine(null)).toBe('');
  });
  it('leaves purchases out when the earn rate is unknown', () => {
    expect(nextRewardLine(nextReward(offers, 99, null))).toBe('1 more point for a free drip coffee');
  });
  it('puts the right article in front', () => {
    expect(article('Iced latte')).toBe('an iced latte');
    expect(article('The big one')).toBe('The big one');
  });
});

describe('a counter ticket', () => {
  it('counts down to zero and stops', () => {
    const now = Date.parse('2026-11-26T17:00:00Z');
    expect(secondsLeft('2026-11-26T17:14:05Z', now)).toBe(845);
    expect(countdownText(845)).toBe('14:05');
    expect(countdownText(9)).toBe('0:09');
    expect(secondsLeft('2026-11-26T16:59:00Z', now)).toBe(0);
    expect(secondsLeft(undefined, now)).toBe(0);
  });
  it('gives the points back for a reward and keeps a coupon', () => {
    expect(ticketRanOutLine({ pointsCost: 100, venueName: 'Sal’s' })).toBe("This reward wasn't marked as given, so your 100 points are back at Sal’s.");
    expect(ticketRanOutLine({ venueName: 'Sal’s' })).toContain('your points are back at Sal’s');
    expect(isCouponTicket({ pointsCost: 0 })).toBe(true);
    expect(ticketRanOutLine({ pointsCost: 0, couponId: 'c1', venueName: null }, 'Sal’s')).toContain("it's still yours at Sal’s");
  });
  it('says what became of a past ticket', () => {
    const voucher = { voucherId: 'v', voucherCode: 'K7QP', offerTitle: 'Coffee', expiresAt: '', pointsCost: 100 };
    expect(voucherStatusLine({ ...voucher, status: 'given' })).toBe('Given');
    expect(voucherStatusLine({ ...voucher, status: 'expired' })).toBe('Ran out · points back');
    expect(voucherStatusLine({ ...voucher, status: 'expired', pointsCost: 0 })).toBe('Ran out · coupon kept');
  });
});

describe('the points ledger', () => {
  it('reads each kind of row', () => {
    expect(historyRowOf({ id: '1', type: 'venue_visit', points: 25 })).toMatchObject({ kind: 'earn', title: 'Visit', points: 25 });
    expect(historyRowOf({ id: '2', type: 'venue_visit', points: 25, via: 'delivery_receipt' })?.title).toBe('Delivery order');
    expect(historyRowOf({ id: '3', type: 'redemption', points: 100, offerTitle: 'Free coffee' })).toMatchObject({ kind: 'redeem', points: -100, title: 'Free coffee' });
    expect(historyRowOf({ id: '4', type: 'redemption', points: 100, status: 'expired' })?.kind).toBe('expired');
    expect(historyRowOf({ id: '5', type: 'redemption_refund', points: 100, offerTitle: 'Free coffee' })?.title).toBe('Points back · Free coffee');
    expect(historyRowOf({ id: '6', type: 'something_new', points: 5 })).toBeNull();
  });
  it('signs the points', () => {
    expect(signedPoints(25)).toBe('+25');
    expect(signedPoints(-100)).toBe('−100');
    expect(signedPoints(0)).toBe('');
  });
});

describe('coupons and my stores', () => {
  const now = new Date(2026, 10, 26, 12);
  const coupon = (over: Partial<CouponClaim>): CouponClaim => ({ claimId: 'c1', venueId: 'v1', title: '10% off', status: 'claimed', ...over });
  it('says what a coupon gives, when it ends and its online code', () => {
    expect(couponDetail(coupon({ detail: 'Any loaf', expiresAt: new Date(2026, 11, 5).toISOString(), onlineCode: 'SAL10' }), now))
      .toBe('Any loaf · Ends Dec 5 · Online code SAL10');
    expect(couponDetail(coupon({ status: 'ticket' }), now)).toBe('Ticket open · show it at the counter');
    expect(couponDetail(coupon({ status: 'used', usedAt: new Date(2026, 10, 2).toISOString(), onlineCode: 'X' }), now)).toBe('Used Nov 2');
  });
  it('offers the right button', () => {
    expect(couponAction(coupon({}))).toBe('Use at the register');
    expect(couponAction(coupon({ status: 'ticket' }))).toBe('Show ticket');
    expect(couponAction(coupon({ status: 'used' }))).toBeNull();
  });
  it('explains what redeeming spends', () => {
    expect(redeemExplainer(100, 'Sal’s')).toMatch(/^This uses 100 of your points at Sal’s/);
    expect(redeemExplainer(100, 'Sal’s')).toMatch(/points come back/);
  });
  it('puts the store just earned at first, then the most points', () => {
    const rows = [{ venueId: 'a', points: 10 }, { venueId: 'b', points: 50 }, { venueId: 'c', points: 5 }];
    expect(orderBalances(rows).map((r) => r.venueId)).toEqual(['b', 'a', 'c']);
    expect(orderBalances(rows, 'c').map((r) => r.venueId)).toEqual(['c', 'b', 'a']);
  });
  it('says how many points are missing', () => {
    expect(shortByText(100, 75)).toBe('25 more points');
    expect(shortByText(100, 99)).toBe('1 more point');
  });
  it("finds a store's place in whichever list has it", () => {
    expect(placeOfVenue('v1', [{ venueId: 'v2', globalPlaceId: 'g2' }], [{ venueId: 'v1', globalPlaceId: 'g1' }])).toBe('g1');
    expect(placeOfVenue('v9', [{ venueId: 'v1', globalPlaceId: 'g1' }], null)).toBeNull();
  });
});
