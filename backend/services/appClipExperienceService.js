// Per-store App Clip cards. The generic "/s" advanced experience (set up by
// hand in App Store Connect) is what a scan shows when nothing more specific
// matches. This service gives each enrolled store its own experiences, one
// per code URL (register: earn points; window: save the spot), with the
// store's name, its points, and its cover photo on the card. iOS picks the
// most specific matching URL, so these win over the generic card.
//
// The card is static per experience (Apple bakes it at creation), so it can
// be specific to the store, never to the person scanning. Someone with the
// app installed still gets the store's own card; Open then lands on the
// store page in the full app.
//
// Record on the venue: appClipExperiences.{register|window} =
//   { id, imageId, link, title, subtitle, fingerprint, syncedAt, status }
// The fingerprint (name · points · cover · code) makes syncs idempotent.

const crypto = require('crypto');
const sharp = require('sharp');
const asc = require('./appStoreConnect/ascClient');
const rewardService = require('./rewardService');
const { getFirestore } = require('../config/firebase');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const placePhotos = require('./placePhotoService');
const rewardProgress = require('./rewardProgress');

const APP_BUNDLE_ID = 'com.favcircles.circles';
const KINDS = ['register', 'window'];
// App Store Connect's limits for the card copy
const TITLE_MAX = 30;
const SUBTITLE_MAX = 56;
const W = 1800;
const H = 1200;
// Bump when the header's look changes: every store's card republishes over
// the next nightly runs (the picture alone, so no new text review).
const HEADER_VERSION = 2;
const SANS = "'DejaVu Sans', -apple-system, Helvetica, Arial, sans-serif";
// The generic card's headline, in the window stickers' and coasters' serif.
// Gelasio (assets/fonts, installed by the Dockerfile) is Georgia's open twin.
const SERIF = "Gelasio, Georgia, 'DejaVu Serif', serif";

// Apple's required businessCategory for an advanced experience, from the
// store's own category. Food is the common case; anything unknown is a shop.
const BUSINESS_CATEGORY = [
  [/restaurant|cafe|coffee|bar|pub|bakery|food|drink|brew|winery|pizza|diner|tavern|grill|deli|dessert|ice ?cream|tea/i, 'FOOD_AND_DRINK'],
  [/grocery|market/i, 'GROCERY'],
  [/gym|fitness|yoga|pilates|crossfit|climb/i, 'FITNESS'],
  [/hotel|inn|lodg|travel|resort|hostel/i, 'HOTEL_AND_TRAVEL'],
  [/salon|spa|beauty|barber|nail|tattoo/i, 'BEAUTY'],
  [/health|medical|clinic|dental|pharmacy|doctor|vet/i, 'HEALTH_AND_MEDICAL'],
  [/pet|dog|cat|groom/i, 'PETS'],
  [/entertainment|theater|theatre|cinema|museum|arcade|bowling|golf|park/i, 'ENTERTAINMENT'],
  [/music|record|concert|venue/i, 'MUSIC'],
  [/book/i, 'BOOKS'],
  [/bike|bicycle/i, 'BIKES'],
  [/auto|car|tire|mechanic/i, 'AUTOMOTIVE'],
  [/gas|fuel/i, 'GAS'],
  [/education|school|tutor|class/i, 'EDUCATION'],
  [/service|repair|clean|law|account|agency|office/i, 'PROFESSIONAL_SERVICES']
];
function businessCategoryFor(venue) {
  const text = [venue.category, venue.placeName, venue.venueName].filter(Boolean).join(' ');
  const hit = BUSINESS_CATEGORY.find(([re]) => re.test(text));
  return hit ? hit[1] : 'SHOPPING';
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// --- copy -----------------------------------------------------------------

const clip = (s, max) => {
  const text = String(s || '').trim().replace(/\s+/g, ' ');
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1).trimEnd()}…`;
};

/// Title: the store's name. Subtitle: what scanning does here.
// `live`: the store's loyalty program runs (claimed, owner on Business). A
// register card before that is the store's own card without the points
// promise (Wes, 2026-10-29: every code gets the store's card; the generic
// one is only for codes no store owns), and it republishes with the points
// the night loyalty goes live.
function copyFor(venue, kind, { live = true } = {}) {
  // Each line says something new (Wes, 2026-10-30): the picture carries the
  // hook, the title the store's name, the subtitle why to keep it; FavCircles
  // itself only in Apple's "Powered by" row. `hook` is the picture's two
  // serif lines, `lead` an optional line under them.
  const subtitle = 'Stay connected. Catch every moment.';
  const saveUs = ['Love it here?', 'Save us.'];
  // The generic "Join FavCircles" code (coasters, anything not one store's)
  if (venue.genericJoin) {
    return { title: 'Build your map.', subtitle, hook: saveUs, lead: 'Never forget your favorite places.' };
  }
  const title = clip(venue.venueName || 'This store', TITLE_MAX);
  if (kind === 'register' && live) {
    const points = rewardService.effectiveEarnRate(venue);
    // The store's first reward rides in the picture, never the words: owners
    // edit offers often and a picture change needs no new words.
    const first = rewardProgress.firstReward(venue.offers);
    return {
      title,
      subtitle,
      hook: [`Earn ${points} points`, 'every visit.'],
      lead: first ? clip(rewardProgress.firstRewardLine(first), 44) : null
    };
  }
  // The window sticker, and the register code before loyalty is live
  return { title, subtitle, hook: saveUs, lead: null };
}

// --- the header image ---------------------------------------------------

// Word-wraps the store name into at most `maxLines` lines for a given width,
// using a crude average glyph width (DejaVu Sans Bold ≈ 0.6 em).
function wrapName(name, fontSize, maxWidth, maxLines) {
  const perLine = Math.max(8, Math.floor(maxWidth / (fontSize * 0.6)));
  const words = String(name).split(/\s+/);
  const lines = [];
  let line = '';
  for (const word of words) {
    const next = line ? `${line} ${word}` : word;
    if (next.length > perLine && line) { lines.push(line); line = word; } else { line = next; }
  }
  if (line) lines.push(line);
  if (lines.length > maxLines) {
    // Words were dropped: the last line says so
    const kept = lines.slice(0, maxLines);
    const last = kept[maxLines - 1];
    kept[maxLines - 1] = clip(`${last}…`, perLine);
    return kept;
  }
  return lines;
}

async function coverBuffer(coverUrl) {
  if (!coverUrl) return null;
  try {
    const res = await fetch(coverUrl, { signal: AbortSignal.timeout(15000) });
    if (!res.ok) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    return await sharp(buf).resize(W, H, { fit: 'cover', position: 'attention' }).jpeg().toBuffer();
  } catch (error) {
    console.warn('⚠️ App Clip header: cover photo unavailable, drawing without it:', error.message);
    return null;
  }
}

// A street map drawn faintly behind the generic card: a skewed grid with two
// avenues. Seeded, so every render is the same picture.
function streetGridSVG(opacity) {
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const lines = [];
  for (let x = -200; x < W + 200; x += 70 + rnd() * 60) lines.push(`M${x},-50 L${x + 260},${H + 50}`);
  for (let y = -100; y < H + 200; y += 60 + rnd() * 70) lines.push(`M-50,${y} L${W + 50},${y - 220}`);
  return `<g stroke="#ffffff" stroke-opacity="${opacity}" fill="none">
    <path d="${lines.join(' ')}" stroke-width="3"/>
    <path d="M-50,760 L${W + 50},300" stroke-width="12"/>
    <path d="M520,-50 L900,${H + 50}" stroke-width="12"/>
  </g>`;
}

const mapPin = (x, y, scale, color) => `<g transform="translate(${x},${y}) scale(${scale})">
    <path d="M0,-60 C-33,-60 -50,-35 -50,-12 C-50,20 0,60 0,60 C0,60 50,20 50,-12 C50,-35 33,-60 0,-60 Z" fill="${color}"/>
    <circle cx="0" cy="-14" r="17" fill="#15171C"/></g>`;

// The hook in the App Clip cards' serif: white first line, gold second, and
// an optional lead under a rule. Vertically centred either way.
function hookSVG(copy) {
  const [ask, answer] = copy.hook;
  const top = copy.lead ? 470 : 540;
  return `<text x="130" y="${top}" font-family="${SERIF}" font-weight="bold" font-size="150" fill="#ffffff">${esc(ask)}</text>
  <text x="130" y="${top + 180}" font-family="${SERIF}" font-weight="bold" font-size="150" fill="#F6C945">${esc(answer)}</text>${copy.lead ? `
  <path d="M130,${top + 270} H560" stroke="#ffffff" stroke-opacity="0.5" stroke-width="2"/>
  <text x="130" y="${top + 360}" font-family="${SANS}" font-size="56" fill="#ffffff" fill-opacity="0.88">${esc(copy.lead)}</text>` : ''}`;
}

const charcoalSVG = `<defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2E333B"/><stop offset="1" stop-color="#111317"/></linearGradient>
    <radialGradient id="glow" cx="0.78" cy="0.42" r="0.6"><stop offset="0" stop-color="#3182CE" stop-opacity="0.18"/><stop offset="1" stop-color="#3182CE" stop-opacity="0"/></radialGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#g)"/>
  ${streetGridSVG(0.045)}
  <rect width="${W}" height="${H}" fill="url(#glow)"/>`;

/// 1800×1200 JPEG. The generic card: charcoal like the window stickers and
/// coasters, a faint street map, the hook, and a route through three saved
/// spots on the right (clear of Apple's close button in the corner). A
/// store's card: its cover photo darkened on the left under the hook, or the
/// charcoal map when it has no photo. The store's name is the card's title,
/// so it isn't in the picture.
async function headerImagePNG(venue, kind, coverUrl, { live = true } = {}) {
  const copy = copyFor(venue, kind, { live });
  const route = `<path d="M1080,1010 C1200,900 1150,760 1290,690 S1460,520 1560,430" fill="none" stroke="#ffffff" stroke-opacity="0.45" stroke-width="4" stroke-dasharray="16 14" stroke-linecap="round"/>
  ${mapPin(1080, 1000, 0.9, '#C8442F')}${mapPin(1300, 680, 0.9, '#D9A62E')}${mapPin(1560, 420, 1.15, '#6A8F3C')}`;
  const cover = venue.genericJoin ? null : await coverBuffer(coverUrl);
  const backdrop = cover
    ? `<defs><linearGradient id="shade" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#111317" stop-opacity="0.9"/><stop offset="0.55" stop-color="#111317" stop-opacity="0.65"/><stop offset="1" stop-color="#111317" stop-opacity="0.2"/>
    </linearGradient></defs>
  <rect width="${W}" height="${H}" fill="url(#shade)"/>`
    : `${charcoalSVG}
  ${venue.genericJoin ? route : ''}`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  ${backdrop}
  ${hookSVG(copy)}
</svg>`;
  const base = cover ? sharp(cover) : sharp({ create: { width: W, height: H, channels: 3, background: '#1B1E24' } });
  return base.composite([{ input: Buffer.from(svg) }]).jpeg({ quality: 88 }).toBuffer();
}

// --- App Store Connect ----------------------------------------------------

let cachedClipId = null;
async function clipId() {
  if (cachedClipId) return cachedClipId;
  const apps = await asc.get(`/apps?filter[bundleId]=${APP_BUNDLE_ID}&fields[apps]=bundleId`);
  const app = apps.data && apps.data[0];
  if (!app) throw new Error('App Store Connect: app not found');
  const clips = await asc.get(`/apps/${app.id}/appClips`);
  const clip = clips.data && clips.data[0];
  if (!clip) throw new Error('App Store Connect: the app has no App Clip');
  cachedClipId = clip.id;
  return cachedClipId;
}

async function uploadHeaderImage(png, fileName) {
  const reserved = await asc.post('/appClipAdvancedExperienceImages', {
    data: { type: 'appClipAdvancedExperienceImages', attributes: { fileName, fileSize: png.length } }
  });
  const image = reserved.data;
  const upload = await asc.uploadOperations(image.attributes.uploadOperations || [], png);
  if (upload.existingId) return upload.existingId;   // these exact bytes were uploaded before
  await asc.patch(`/appClipAdvancedExperienceImages/${image.id}`, {
    data: {
      type: 'appClipAdvancedExperienceImages',
      id: image.id,
      attributes: { uploaded: true, sourceFileChecksum: crypto.createHash('md5').update(png).digest('hex') }
    }
  });
  return image.id;
}

// An inline-created localization is named by a placeholder that the
// relationship repeats; Apple assigns the real id. ('EN' is refused as an
// invalid id, and '${new-localization}' as an unknown relationship.)
const LOC_PLACEHOLDER = '${new-localization-en}';

async function createExperience({ link, title, subtitle, imageId, businessCategory }) {
  const created = await asc.post('/appClipAdvancedExperiences', {
    data: {
      type: 'appClipAdvancedExperiences',
      attributes: { link, defaultLanguage: 'EN', action: 'OPEN', isPoweredBy: true, businessCategory },
      relationships: {
        appClip: { data: { type: 'appClips', id: await clipId() } },
        headerImage: { data: { type: 'appClipAdvancedExperienceImages', id: imageId } },
        localizations: { data: [{ type: 'appClipAdvancedExperienceLocalizations', id: LOC_PLACEHOLDER }] }
      }
    },
    included: [{
      type: 'appClipAdvancedExperienceLocalizations',
      id: LOC_PLACEHOLDER,
      attributes: { language: 'EN', title, subtitle }
    }]
  });
  return created.data;
}

/// Apple refuses a second experience for a link, and a single GET by id is
/// not always answered for a fresh one, so the clip's list is the lookup.
async function findExperienceByLink(link) {
  let path = `/appClips/${await clipId()}/appClipAdvancedExperiences?limit=200`;
  while (path) {
    const page = await asc.get(path);
    // A retired card for the link still counts: Apple blocks a second one,
    // and it can be brought back (removed: false) and edited
    const forLink = (page.data || []).filter((e) => e.attributes.link === link);
    const hit = forLink.find((e) => e.attributes.status !== 'REMOVED') || forLink[0];
    if (hit) {
      // The words from the card itself: the list's included localizations
      // don't line up with its cards (every card read as one store's words)
      const one = await asc.get(`/appClipAdvancedExperiences/${hit.id}?include=localizations`);
      const loc = (one.included || []).find((i) => i.type === 'appClipAdvancedExperienceLocalizations');
      return { id: hit.id, status: hit.attributes.status, title: loc?.attributes?.title, subtitle: loc?.attributes?.subtitle };
    }
    path = page.links && page.links.next ? page.links.next : null;
  }
  return null;
}

/// New words on an existing card, in place: a new localization replaces the
/// old one (2026-10-29: Apple accepts this; retiring the card and creating a
/// new one for the same link does not, and a new card takes hours to show).
/// A retired card is brought back into service first.
async function updateExperienceWords({ id, title, subtitle }) {
  const patch = () => asc.patch(`/appClipAdvancedExperiences/${id}`, {
    data: {
      type: 'appClipAdvancedExperiences',
      id,
      relationships: { localizations: { data: [{ type: 'appClipAdvancedExperienceLocalizations', id: LOC_PLACEHOLDER }] } }
    },
    included: [{ type: 'appClipAdvancedExperienceLocalizations', id: LOC_PLACEHOLDER, attributes: { language: 'EN', title, subtitle } }]
  });
  try {
    await patch();
  } catch (error) {
    // Already says this: nothing to do
    if (/no change to the original/i.test(error.message)) return;
    if (!/no longer active|removed/i.test(error.message)) throw error;
    await asc.patch(`/appClipAdvancedExperiences/${id}`, {
      data: { type: 'appClipAdvancedExperiences', id, attributes: { removed: false } }
    });
    await patch();
  }
}

/// Only the picture of a card is set here; words go through updateExperienceWords.
async function updateExperienceImage({ id, imageId, status }) {
  try {
    const updated = await asc.patch(`/appClipAdvancedExperiences/${id}`, {
      data: {
        type: 'appClipAdvancedExperiences',
        id,
        attributes: { action: 'OPEN', isPoweredBy: true },
        relationships: { headerImage: { data: { type: 'appClipAdvancedExperienceImages', id: imageId } } }
      }
    });
    return updated.data;
  } catch (error) {
    // Same picture as before (Apple keeps one copy per image): nothing to do
    if (/no change to the original/i.test(error.message)) return { id, attributes: { status: status || 'RECEIVED' } };
    throw error;
  }
}

/// Apple has no delete for experiences; `removed` takes one out of service.
async function removeExperience(id) {
  await asc.patch(`/appClipAdvancedExperiences/${id}`, {
    data: { type: 'appClipAdvancedExperiences', id, attributes: { removed: true } }
  });
}

// --- the sync -------------------------------------------------------------

async function coverUrlFor(venue) {
  if (!venue.globalPlaceId) return null;
  const doc = await getFirestore().collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(venue.globalPlaceId).get();
  if (!doc.exists) return null;
  const data = doc.data();
  return data.coverPhotoUrl || placePhotos.coverUrl(data.photos || []) || null;
}

function fingerprintFor(venue, kind, code, coverUrl, { live = true } = {}) {
  const rewarding = kind === 'register' && live;
  const points = rewarding ? rewardService.effectiveEarnRate(venue) : '';
  const first = rewarding ? rewardProgress.firstReward(venue.offers) : null;
  const reward = first ? `${first.pointsCost}:${first.title}` : '';
  // The card's words too: a copy change republishes without a version bump
  const copy = copyFor(venue, kind, { live });
  const words = [copy.subtitle, ...copy.hook, copy.lead || ''].join('/');
  return crypto.createHash('md5').update([venue.venueName, points, reward, words, coverUrl || '', kind, code, `v${HEADER_VERSION}`].join('|')).digest('hex');
}

/// Creates or refreshes the store's experiences. Returns what's on the venue
/// afterwards, with `changed` listing the kinds that were (re)published.
async function syncVenue(venue, { force = false, kinds = KINDS, live = true } = {}) {
  if (!asc.configured()) return { skipped: 'not configured', experiences: venue.appClipExperiences || {} };
  const existing = { ...(venue.appClipExperiences || {}) };
  const coverUrl = await coverUrlFor(venue);
  const changed = [];
  for (const kind of kinds) {
    const code = kind === 'register' ? venue.registerCode : venue.windowCode;
    if (!code) continue;
    const link = rewardService.stickerUrl(code);
    const fingerprint = fingerprintFor(venue, kind, code, coverUrl, { live });
    const current = existing[kind];
    if (current && current.fingerprint === fingerprint && current.link === link && !force) continue;

    const { title, subtitle } = copyFor(venue, kind, { live });
    const image = await headerImagePNG(venue, kind, coverUrl, { live });
    const imageId = await uploadHeaderImage(image, `${venue.venueId}-${kind}-1800x1200.jpg`);
    let record;
    // Whatever Apple already has for this link is the card to keep, if its
    // words still fit: the venue's record, or a card published before the
    // record existed. Words changed (a rename, new points) mean a new card,
    // since Apple lets only the picture change on a published one.
    // One card per link, kept for life: new words or a new picture edit it
    // in place. Only a code that changed (a rotated register code) gets a
    // new card, and the old code's card stops serving.
    let target = current && current.id && current.link === link ? current : await findExperienceByLink(link);
    if (target) {
      if (target.title !== title || target.subtitle !== subtitle || target.status === 'REMOVED') {
        await updateExperienceWords({ id: target.id, title, subtitle });
      }
      const data = await updateExperienceImage({ id: target.id, imageId, status: target.status });
      record = { id: data.id, imageId, link, title, subtitle, fingerprint, status: data.attributes.status };
    } else {
      if (current && current.id && current.link !== link) {
        await removeExperience(current.id).catch((e) => console.warn('⚠️ App Clip: could not retire the old code\'s card:', e.message));
      }
      const data = await createExperience({ link, title, subtitle, imageId, businessCategory: businessCategoryFor(venue) });
      record = { id: data.id, imageId, link, title, subtitle, fingerprint, status: data.attributes.status };
    }
    record.syncedAt = new Date().toISOString();
    existing[kind] = record;
    changed.push(kind);
  }
  if (changed.length) {
    await getFirestore().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId)
      .set({ appClipExperiences: existing }, { merge: true });
  }
  return { changed, experiences: existing };
}

/// Fire-and-forget for request handlers: a card that lags is never a reason
/// to fail a rename or a cover-photo change.
function syncVenueQuiet(venue, options) {
  if (!asc.configured()) return;
  syncVenue(venue, options).catch((error) => console.error('⚠️ App Clip experience sync failed:', venue.venueId, error.message));
}

module.exports = { KINDS, HEADER_VERSION, copyFor, businessCategoryFor, wrapName, headerImagePNG, fingerprintFor, syncVenue, syncVenueQuiet, removeExperience, TITLE_MAX, SUBTITLE_MAX };
