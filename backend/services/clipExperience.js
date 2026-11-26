// backend/services/clipExperience.js
// What the App Clip shows after Open at a store's window code (Wes, 2026-11-26):
// a Welcome screen (the store's photo, what staying connected brings, one
// button), a sign-in screen over a second photo of the store that says what
// FavCircles is, and the "you're connected" screen. The same layout at every
// store, filled from that store; the owner can change any part later through
// `venue.clipExperience` (overrides). Pure: the controller passes the records.
//
// Rules:
// - The rows promise what the customer will get (specials, events, news,
//   the menu); never a count, a date, or "nothing posted yet".
// - The rewards row and the points words appear only while the store's
//   rewards are live, and an owner can switch them off (it can only hide).
// - Alerts are "from <store>", never "only".

const MAX_SHORT_NAME = 24;

const ROW_KINDS = ['rewards', 'menu', 'specials', 'events', 'announcements'];

const str = (value, max = 200) => {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed.slice(0, max) : null;
};

const httpUrl = (value) => {
  const url = str(value, 500);
  return url && /^https?:\/\//i.test(url) ? url : null;
};

/** The name the buttons and lines use: the owner's short name, else the store's. */
function shortNameFor(venue, overrides) {
  return str(overrides.shortName, MAX_SHORT_NAME) || str(venue.venueName, 80) || 'this store';
}

function rewardsLine(firstReward, earnRate) {
  if (firstReward && firstReward.title && firstReward.pointsCost) {
    return `${firstReward.pointsCost} points = ${firstReward.title}`;
  }
  return earnRate ? `${earnRate} points every visit` : 'Points every visit';
}

/** One row per kind; null when the store can't back it (no menu link, rewards off). */
function rowFor(kind, ctx) {
  const { name, showRewards, menuUrl, firstReward, earnRate } = ctx;
  switch (kind) {
    case 'rewards':
      return showRewards ? { kind, title: 'Rewards', detail: rewardsLine(firstReward, earnRate) } : null;
    case 'menu':
      return menuUrl ? { kind, title: 'See the menu', detail: `${name}'s menu, one tap away`, url: menuUrl } : null;
    case 'specials':
      return { kind, title: 'Specials', detail: 'New specials the moment they’re posted' };
    case 'events':
      return { kind, title: 'Events', detail: 'Hear about events before they happen' };
    case 'announcements':
      return { kind, title: 'Announcements', detail: `News from ${name}, right on your phone` };
    default:
      return null;
  }
}

/**
 * @param {object} args
 * @param {object} args.venue         the stickerVenues record
 * @param {object} [args.globalPlace] the canonical venue (photos, googleData, description)
 * @param {boolean} args.loyaltyLive  the store's rewards are live
 * @param {object[]} [args.offers]    the reward ladder, cheapest first
 * @param {number} [args.earnRate]
 * @param {number} [args.savePoints]  what the save pays here (0 when not live)
 * @param {string} [args.coverUrl]
 * @param {string[]} [args.photoUrls] the store's public photos, cover first
 */
function buildClipExperience({ venue, globalPlace, loyaltyLive, offers, earnRate, savePoints, coverUrl, photoUrls }) {
  const overrides = (venue && typeof venue.clipExperience === 'object' && venue.clipExperience) || {};
  const google = (globalPlace && globalPlace.googleData) || {};
  const name = shortNameFor(venue || {}, overrides);
  const fullName = str((venue || {}).venueName, 80) || name;
  // The owner can hide points; nothing turns them on where rewards aren't live
  const showRewards = !!loyaltyLive && overrides.showRewards !== false;
  const menuUrl = httpUrl(overrides.menuUrl) || httpUrl(venue && venue.menuUrl) || httpUrl(google.website);
  const firstReward = (offers || [])[0] || null;

  const order = Array.isArray(overrides.rows) && overrides.rows.length
    ? overrides.rows.filter((kind) => ROW_KINDS.includes(kind))
    : ROW_KINDS;
  const rows = [...new Set(order)]
    .map((kind) => rowFor(kind, { name, showRewards, menuUrl, firstReward, earnRate }))
    .filter(Boolean);

  // The sign-in screen's photo: the owner's pick, else the store's second
  // photo, else its cover (never a blank screen)
  const photos = (photoUrls || []).filter(Boolean);
  const connectPhotoUrl = httpUrl(overrides.connectPhotoUrl)
    || photos.find((url) => url !== coverUrl)
    || coverUrl || null;

  const rating = Number(google.rating);
  const reviews = Number(google.userRatingsTotal);
  const ratingLine = rating >= 1
    ? `${rating.toFixed(1)} on Google${reviews > 0 ? ` · ${reviews.toLocaleString('en-US')} reviews` : ''}`
    : null;

  const points = showRewards && savePoints > 0 ? savePoints : 0;

  return {
    version: 1,
    shortName: name,
    welcome: {
      title: fullName,
      // Under the name: the owner's words, else what it is and how it rates
      line: str(overrides.welcomeLine, 160)
        || `Stay connected to ${name}. Save it to your FavCircles map and you’ll get:`,
      ratingLine,
      photoUrl: coverUrl || null,
      rows,
      button: `Save ${name} & stay connected`
    },
    connect: {
      hook: ['Stay connected', `to ${name}.`],
      photoUrl: connectPhotoUrl,
      // What FavCircles is, in one line, for someone who has never heard of it
      about: 'FavCircles is your map of the places you love. Save them, share them with friends, and hear from them.',
      alerts: `Get alerts from ${name}: specials, events and announcements.`,
      pointsLine: points ? `+${points} points when it’s saved` : null
    },
    done: {
      hook: ['You’re connected', `to ${name}.`],
      line: str(overrides.doneLine, 160)
        || `${name} is on your map. You’ll get their specials, events and news.`,
      showRewards,
      showWallet: showRewards && overrides.showWallet !== false
    }
  };
}

const OVERRIDE_TEXT = { shortName: MAX_SHORT_NAME, welcomeLine: 160, doneLine: 160 };

/**
 * An owner's edits, checked: words trimmed to length, rows from the known
 * kinds, switches as booleans, the sign-in photo one of the store's own
 * public photos, the menu an http(s) link. `null` clears a field (back to
 * the default). Returns { overrides, errors }; `current` is what's saved.
 */
function cleanOverrides(input, { current = {}, photoUrls = [] } = {}) {
  const body = input && typeof input === 'object' ? input : {};
  const next = { ...current };
  const errors = [];
  for (const [key, max] of Object.entries(OVERRIDE_TEXT)) {
    if (!(key in body)) continue;
    if (body[key] === null || body[key] === '') { delete next[key]; continue; }
    if (typeof body[key] !== 'string') { errors.push(`${key} must be text`); continue; }
    const text = body[key].trim();
    if (text.length > max) errors.push(`${key} is ${text.length} characters; ${max} at most`);
    else if (text) next[key] = text; else delete next[key];
  }
  if ('rows' in body) {
    if (body.rows === null) delete next.rows;
    else if (!Array.isArray(body.rows)) errors.push('rows must be a list');
    else {
      const unknown = body.rows.filter((kind) => !ROW_KINDS.includes(kind));
      if (unknown.length) errors.push(`Unknown rows: ${unknown.join(', ')}`);
      else next.rows = [...new Set(body.rows)];
    }
  }
  for (const key of ['showRewards', 'showWallet']) {
    if (!(key in body)) continue;
    if (body[key] === null) delete next[key];
    else if (typeof body[key] !== 'boolean') errors.push(`${key} must be true or false`);
    else if (body[key]) delete next[key]; // on is the default
    else next[key] = false;
  }
  if ('connectPhotoUrl' in body) {
    if (!body.connectPhotoUrl) delete next.connectPhotoUrl;
    else if (!photoUrls.includes(body.connectPhotoUrl)) errors.push('The sign-in photo must be one of the store\u2019s photos');
    else next.connectPhotoUrl = body.connectPhotoUrl;
  }
  if ('menuUrl' in body) {
    if (!body.menuUrl) delete next.menuUrl;
    else if (!httpUrl(body.menuUrl)) errors.push('The menu link must start with http:// or https://');
    else next.menuUrl = httpUrl(body.menuUrl);
  }
  return { overrides: next, errors };
}

/** Whether the preview carries the experience: off until Wes turns it on. */
const clipExperienceEnabled = () => process.env.CLIP_STORE_WELCOME === '1';

module.exports = { buildClipExperience, cleanOverrides, clipExperienceEnabled, ROW_KINDS };
