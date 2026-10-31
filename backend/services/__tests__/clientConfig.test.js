// One source for the business values the app shows (Wes, 2026-10-31).
const { buildClientConfig } = require('../clientConfig');
const { SUBSCRIPTION_LIMITS } = require('../../config/subscriptionLimits');
const piggy = require('../../config/piggyBankConfig');
const rewards = require('../../config/rewardConfig');

test('the app reads limits, amounts and the App Store link from the server config', () => {
  const c = buildClientConfig();
  expect(c.version).toBe(1);
  expect(c.appStoreUrl).toBe(rewards.APP_STORE_URL);
  expect(c.freeLimits).toMatchObject({
    maxCircles: SUBSCRIPTION_LIMITS.FREE.MAX_CIRCLES,
    maxPlacesPerCircle: SUBSCRIPTION_LIMITS.FREE.MAX_PLACES_PER_CIRCLE,
    photoPlaces: SUBSCRIPTION_LIMITS.FREE.PHOTO_PLACES
  });
  expect(c.storeRewardDefaults).toEqual({ pointsPerPurchase: rewards.POINTS.VENUE_VISIT, pointsForSaving: rewards.POINTS.STICKER_SAVE });
  expect(c.favCoins).toEqual({
    firstPlaceAdded: piggy.COINS.FIRST_PLACE_ADDED, drinkReceived: piggy.COINS.DRINK_RECEIVED, eventJoined: piggy.COINS.EVENT_JOINED
  });
  // JSON-safe: no Infinity sneaks through
  expect(JSON.parse(JSON.stringify(c))).toEqual(c);
});
