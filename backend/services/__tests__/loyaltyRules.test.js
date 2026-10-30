// Who earns what (Wes, 2026-10-30): the owner sets every amount; nothing is
// paid until the store's rewards are live; a super-user demo makes it live.
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({ collection: () => ({ doc: () => ({ get: async () => ({ exists: false }) }) }) }) }));
const subs = require('../ownerSubscriptionService');
const rewardService = require('../rewardService');

describe('owner-set points', () => {
  test('defaults are 25 for joining and saving; the owner can change or turn them off', () => {
    expect(rewardService.effectiveJoinPoints({})).toBe(25);
    expect(rewardService.effectiveSavePoints({})).toBe(25);
    expect(rewardService.effectiveJoinPoints({ joinPoints: 40 })).toBe(40);
    expect(rewardService.effectiveSavePoints({ savePoints: 0 })).toBe(0);
    expect(rewardService.effectiveEarnRate({})).toBe(25);
  });
});

describe('no points until rewards are live', () => {
  test('an unclaimed store earns nothing now (it used to pay visit points as a demo)', async () => {
    expect(await subs.registerScanEarns({ venueId: 'v1' })).toMatchObject({ earns: false, demo: false });
  });
  test("a super-user demo makes any store live until it expires", async () => {
    const future = new Date(Date.now() + 86400000).toISOString();
    const past = new Date(Date.now() - 1000).toISOString();
    expect(await subs.venueLoyaltyStatus({ venueId: 'v1', loyaltyDemoUntil: future })).toEqual({ active: true, reason: 'demo' });
    expect(await subs.registerScanEarns({ venueId: 'v1', loyaltyDemoUntil: future })).toMatchObject({ earns: true });
    expect(await subs.venueLoyaltyStatus({ venueId: 'v1', loyaltyDemoUntil: past })).toMatchObject({ active: false, reason: 'no_owner' });
  });
});
