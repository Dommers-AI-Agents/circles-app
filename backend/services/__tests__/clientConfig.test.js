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

test('the new chat look is on unless the env turns it off (2026-11-23)', () => {
  expect(buildClientConfig().chat).toEqual({ polished: true });
  process.env.CHAT_POLISHED = 'false';
  expect(buildClientConfig().chat).toEqual({ polished: false });
  delete process.env.CHAT_POLISHED;
});

test('the lively Activity feed is on unless the env turns it off (2026-11-16)', () => {
  expect(buildClientConfig().activityFeed).toEqual({ alive: true, groupPages: true });
  process.env.ACTIVITY_FEED_ALIVE = 'false';
  expect(buildClientConfig().activityFeed).toEqual({ alive: false, groupPages: true });
  delete process.env.ACTIVITY_FEED_ALIVE;
});

test('grouped activities page as one card unless the env turns it off (2026-11-24)', () => {
  process.env.ACTIVITY_FEED_GROUP_PAGES = 'false';
  expect(buildClientConfig().activityFeed).toEqual({ alive: true, groupPages: false });
  delete process.env.ACTIVITY_FEED_GROUP_PAGES;
});

test('the "Did you know" tips are the weekly email\'s list, emoji and text only', () => {
  const tips = require('../../config/weeklyTips');
  const c = buildClientConfig();
  expect(c.tips).toHaveLength(tips.length);
  expect(c.tips[0]).toEqual({ emoji: tips[0].emoji, text: tips[0].text });
  c.tips.forEach((tip) => expect(tip.text.length).toBeLessThan(140));
});
