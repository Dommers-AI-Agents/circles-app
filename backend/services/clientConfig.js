// backend/services/clientConfig.js
//
// The business values the app and the widgets show, served from ONE place
// (Wes, 2026-10-31: "make sure data points … are stored in the db and pulled
// from one place"). The app caches the last answer and keeps its built-in
// copy only as an offline fallback, so changing a limit, an amount or the
// App Store link here changes it everywhere on the next launch.
const { SUBSCRIPTION_LIMITS } = require('../config/subscriptionLimits');
const piggy = require('../config/piggyBankConfig');
const rewards = require('../config/rewardConfig');

const finite = (n) => (Number.isFinite(n) ? n : null);

/** Pure (tested): the JSON the app reads. Keys are part of the app contract. */
function buildClientConfig() {
  const free = SUBSCRIPTION_LIMITS.FREE;
  const coins = piggy.COINS || {};
  return {
    version: 1,
    appStoreUrl: rewards.APP_STORE_URL,
    freeLimits: {
      maxCircles: finite(free.MAX_CIRCLES),
      maxPlacesPerCircle: finite(free.MAX_PLACES_PER_CIRCLE),
      photoPlaces: finite(free.PHOTO_PLACES),
      eventVideoMaxSeconds: finite(free.EVENT_VIDEO_MAX_SECONDS),
      eventVideosPerEvent: finite(free.EVENT_VIDEOS_PER_EVENT)
    },
    // Defaults until a store sets its own (each store's real amounts ride on
    // its own venue data)
    storeRewardDefaults: {
      pointsPerPurchase: rewards.POINTS.VENUE_VISIT,
      pointsForSaving: rewards.POINTS.STICKER_SAVE
    },
    favCoins: {
      firstPlaceAdded: finite(coins.FIRST_PLACE_ADDED),
      drinkReceived: finite(coins.DRINK_RECEIVED),
      eventJoined: finite(coins.EVENT_JOINED)
    }
  };
}

module.exports = { buildClientConfig };
