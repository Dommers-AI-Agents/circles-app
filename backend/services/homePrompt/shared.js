// backend/services/homePrompt/shared.js
// Constants, config and pure helpers shared by homePromptService.js and its ./ mixins.
//
// Home "daily card": one intriguing thing per visit. The server picks at most
// one card for a user, roughly once a day, from a fixed priority list —
// something a connection just did, the newest network moment, a nudge to add
// a place, the piggy-bank balance, then evergreen "have you seen…" feature
// tips from the `notificationTips` catalog (surfaces: ["home"]).
//
// All memory of what a user has seen or already knows lives on the user doc
// (`homePrompt`), never on the device, so a reinstall doesn't re-ask and two
// devices agree. Three signals stop a card from repeating:
//   1. explicit acks — Skip / acted / shown, keyed by card key;
//   2. behavioural evidence — has widget data → knows the Widgets tab; has any
//      video view → has scrolled Moments; added a place this week → no nudge;
//   3. the catalog's own `tipsSeen` list (push tips already delivered).
//
// Showing nothing is a normal outcome. The card is stamped as shown on pick
// (not on a client ack) — if the phone drops the response the user misses one
// card today, which is the cheap failure. Ships dark behind HOME_PROMPTS_ENABLED.

const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { PIGGY_COLLECTIONS } = require('../../models/PiggyBankModels');
const { queryInChunks } = require('../../utils/firestoreChunks');
const { excludedUserIds } = require('../moderationService');
const tipsService = require('../tipsService');
const homeCards = require('../homeCards');
const { getAssumedLocation } = require('../userCardEnrichment');
const { haversineMeters } = require('../globalPlaceResolver');
const { canViewCircle, canViewMoment, isPlaceVisibleToViewer } = require('../visibility');
const { makeViewerContext } = require('../viewerContext');
const { getInnerCircleGrantorIds } = require('../../utils/networkAccess');

const CATALOG_COLLECTION = 'notificationTips';
// Scheduled campaigns Wes writes from the backend — see services/homeCards.js.
const CARDS_COLLECTION = 'homeCards';
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

// Rolling window between cards. 20h (not 24h) so "first open of the day"
// still qualifies for someone who opened at 9am yesterday and 8am today.
// Between cards. Two hours reads as "you came back", not "you switched tabs":
// the card is meant to greet someone arriving, not interrupt someone working.
const SHOW_INTERVAL_MS = parseInt(process.env.HOME_PROMPT_INTERVAL_HOURS || '2', 10) * HOUR;
// A catalog tip comes round again — this is a rotation, not a one-time
// announcement — but not too soon, and less soon the more clearly the person
// has already dealt with it: tried it, skipped it, or merely seen it.
const TIP_REPEAT_MS = parseInt(process.env.HOME_TIP_REPEAT_HOURS || '24', 10) * HOUR;
const TIP_REPEAT_SKIPPED_MS = 3 * DAY;
const TIP_REPEAT_ACTED_MS = 7 * DAY;
// New accounts get the onboarding chain, not cards.
const NEW_ACCOUNT_GUARD_MS = 48 * HOUR;
// A connection's activity is only "news" for a day.
const ACTIVITY_WINDOW_MS = DAY;
// Dynamic acks (per activity / moment) are app state, not user content —
// prune them after this so the map stays bounded. Static keys are kept
// forever: that's the "never ask twice" memory.
const DYNAMIC_ACK_TTL_MS = 90 * DAY;
// Personal nudges may repeat, but not more often than this.
const NUDGE_REPEAT_MS = 7 * DAY;
// The postcard nudge is rarer than the rest: it asks for effort (and, if the
// user picks print, money), so a fortnight between asks. Shared with the
// post-save pop-up in the app — both read and write the `postcard_nudge` ack,
// so being asked in one place silences the other.
const POSTCARD_REPEAT_MS = parseInt(process.env.POSTCARD_NUDGE_REPEAT_DAYS || '14', 10) * DAY;
// A "Not now" is a smaller answer than being asked and making one: it holds
// a few days, not the fortnight. Wes said no to the offer on a Saturday and
// found the photo-upload offer gone the next week at the airport — the
// fortnight was meant to space out asks, not to punish a "not right now".
const POSTCARD_REPEAT_SKIPPED_MS = parseInt(process.env.POSTCARD_NUDGE_REPEAT_SKIPPED_DAYS || '3', 10) * DAY;
// Only nudge about places saved recently enough to still feel like news.
const POSTCARD_PLACE_WINDOW_MS = 7 * DAY;
// Optional tightener: only nudge when the place is at least this far from
// where the user usually is, i.e. it reads as a trip. Unset = off (and then
// the picker never pays for a location lookup).
// Newest activities scanned per actor chunk.
const ACTIVITY_SCAN_LIMIT = 10;

const ACTIVITY_TYPES = new Set(['place_added', 'video_uploaded', 'photo_uploaded', 'check_in']);
const ACTIONS = new Set(['skipped', 'acted', 'shown']);

const METERS_PER_MILE = 1609.344;
// Recent saves scanned for one with a photo.
const POSTCARD_PLACE_SCAN_LIMIT = 20;

// Keys that may be acked by the client directly (not derived from a card):
// the FavCoins explainer records itself when the user finishes it, and the
// post-save postcard pop-up records itself so the home card honours the same
// cooldown (and vice versa).
const CLIENT_ACK_KEYS = new Set(['favcoins_intro', 'postcard_nudge']);

const isEnabled = () => process.env.HOME_PROMPTS_ENABLED === '1';
// Read per call, like isEnabled: 0/unset keeps the tightener off.
const minTripMiles = () => parseFloat(process.env.POSTCARD_NUDGE_MIN_MILES || '0');

// Firestore Timestamp, Date, ISO string, or millis → millis (NaN if unknown).
function toMillis(value) {
  if (!value) return NaN;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return new Date(value).getTime();
  if (typeof value._seconds === 'number') return value._seconds * 1000;
  return NaN;
}

const isDynamicKey = (key) => key.includes(':');

class HomePromptError extends ServiceError {}

module.exports = { TIP_REPEAT_MS, TIP_REPEAT_SKIPPED_MS, TIP_REPEAT_ACTED_MS, ACTIONS, ACTIVITY_SCAN_LIMIT, ACTIVITY_TYPES, ACTIVITY_WINDOW_MS, CARDS_COLLECTION, CATALOG_COLLECTION, CLIENT_ACK_KEYS, COLLECTIONS, DAY, DYNAMIC_ACK_TTL_MS, HOUR, HomePromptError, METERS_PER_MILE, NEW_ACCOUNT_GUARD_MS, NUDGE_REPEAT_MS, PIGGY_COLLECTIONS, POSTCARD_PLACE_SCAN_LIMIT, POSTCARD_PLACE_WINDOW_MS, POSTCARD_REPEAT_MS, POSTCARD_REPEAT_SKIPPED_MS, SHOW_INTERVAL_MS, canViewCircle, canViewMoment, excludedUserIds, getAssumedLocation, getFirestore, getInnerCircleGrantorIds, haversineMeters, homeCards, isDynamicKey, isEnabled, isPlaceVisibleToViewer, makeViewerContext, minTripMiles, queryInChunks, tipsService, toMillis };
