// A scan in the store's own terms (2026-10-29): the first reward, and the
// distance from a balance to the next one. Mirrors Logic/RewardsAvailability.
const p = require('../rewardProgress');

const OFFERS = [
  { offerId: 'o3', title: 'Free lunch', pointsCost: 300 },
  { offerId: 'o1', title: 'Free coffee', pointsCost: 100 },
  { offerId: 'off', title: 'Retired', pointsCost: 50, active: false },
  { offerId: 'o2', title: 'Espresso shot', pointsCost: 150 }
];

test('the first reward is the cheapest live offer', () => {
  expect(p.firstReward(OFFERS)).toEqual({ offerId: 'o1', title: 'Free coffee', pointsCost: 100 });
  expect(p.firstReward([])).toBeNull();
  expect(p.firstRewardLine(p.firstReward(OFFERS))).toBe('100 points = Free coffee');
});

test('the next reward is the cheapest out of reach, with visits at the earn rate', () => {
  expect(p.nextReward(OFFERS, 25, 25)).toMatchObject({ title: 'Free coffee', remaining: 75, visitsLeft: 3, canRedeem: false });
  expect(p.nextReward(OFFERS, 0, null)).toMatchObject({ title: 'Free coffee', remaining: 100, visitsLeft: null });
  expect(p.nextRewardLine(p.nextReward(OFFERS, 25, 25))).toBe('75 more points for a free coffee · about 3 more visits');
  expect(p.nextRewardLine(p.nextReward(OFFERS, 99, 25))).toBe('1 more point for a free coffee · about 1 more visit');
});

test('once something is affordable it is the best one they can take now', () => {
  expect(p.nextReward(OFFERS, 160, 25)).toMatchObject({ title: 'Espresso shot', remaining: 0, canRedeem: true });
  expect(p.nextRewardLine(p.nextReward(OFFERS, 160, 25))).toBe("You've got enough for an espresso shot. Scan at the register to use it.");
  expect(p.nextReward([], 500, 25)).toBeNull();
});

test('articles read naturally', () => {
  expect(p.article('Free coffee')).toBe('a free coffee');
  expect(p.article('A slice')).toBe('A slice');
  expect(p.article('your choice of pastry')).toBe('your choice of pastry');
});
