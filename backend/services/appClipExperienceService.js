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

const APP_BUNDLE_ID = 'com.favcircles.circles';
const KINDS = ['register', 'window'];
// App Store Connect's limits for the card copy
const TITLE_MAX = 30;
const SUBTITLE_MAX = 56;
const W = 1800;
const H = 1200;
// Bump when the header's look changes: every store's card republishes over
// the next nightly runs (the picture alone, so no new text review).
const HEADER_VERSION = 1;
const SANS = "'DejaVu Sans', -apple-system, Helvetica, Arial, sans-serif";

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
  const name = clip(venue.venueName || 'This store', TITLE_MAX);
  if (kind === 'register' && live) {
    const points = rewardService.effectiveEarnRate(venue);
    return {
      title: name,
      subtitle: clip(`Earn ${points} points every visit. Save it to your map.`, SUBTITLE_MAX),
      pill: `Earn ${points} points every visit`,
      lead: 'Scan at the register, collect points, redeem them here.'
    };
  }
  return {
    title: name,
    subtitle: clip('Save this spot to your map and share it with friends.', SUBTITLE_MAX),
    pill: 'Save this spot',
    lead: 'Keep it on your map and see what friends think.'
  };
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

/// 1800×1200 JPEG: the cover photo under a dark gradient (or the brand
/// gradient alone), the store's name, a pill with what the scan does.
async function headerImagePNG(venue, kind, coverUrl, { live = true } = {}) {
  const copy = copyFor(venue, kind, { live });
  const cover = await coverBuffer(coverUrl);
  const nameSize = 112;
  const nameLines = wrapName(venue.venueName || 'This store', nameSize, W - 240, 2);
  const nameTop = 420 - (nameLines.length - 1) * 60;
  const pillW = Math.min(W - 240, Math.round(copy.pill.length * 30 + 140));
  const pillY = nameTop + nameLines.length * 130 + 20;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <linearGradient id="brand" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#2B6CB0"/><stop offset="1" stop-color="#4299E1"/>
    </linearGradient>
    <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0A1428" stop-opacity="0.35"/><stop offset="1" stop-color="#0A1428" stop-opacity="0.88"/>
    </linearGradient>
  </defs>
  ${cover ? '' : `<rect width="${W}" height="${H}" fill="url(#brand)"/>
  <circle cx="1560" cy="180" r="260" fill="#ffffff" fill-opacity="0.08"/>
  <circle cx="220" cy="1080" r="320" fill="#ffffff" fill-opacity="0.07"/>`}
  ${cover ? `<rect width="${W}" height="${H}" fill="url(#shade)"/>` : ''}
  <text x="120" y="200" font-family="${SANS}" font-weight="bold" font-size="54" fill="#ffffff" fill-opacity="0.92">FavCircles</text>
  ${nameLines.map((line, i) => `<text x="120" y="${nameTop + i * 130}" font-family="${SANS}" font-weight="bold" font-size="${nameSize}" fill="#ffffff">${esc(line)}</text>`).join('\n  ')}
  <rect x="120" y="${pillY}" width="${pillW}" height="110" rx="55" fill="#F6C945"/>
  <text x="${120 + pillW / 2}" y="${pillY + 74}" text-anchor="middle" font-family="${SANS}" font-weight="bold" font-size="52" fill="#1A202C">${esc(copy.pill)}</text>
  <text x="120" y="${pillY + 200}" font-family="${SANS}" font-size="46" fill="#ffffff" fill-opacity="0.9">${esc(copy.lead)}</text>
</svg>`;
  const overlay = Buffer.from(svg);
  const base = cover ? sharp(cover) : sharp({ create: { width: W, height: H, channels: 3, background: '#2B6CB0' } });
  return base.composite([{ input: overlay }]).jpeg({ quality: 88 }).toBuffer();
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
  let path = `/appClips/${await clipId()}/appClipAdvancedExperiences?include=localizations&limit=200`;
  while (path) {
    const page = await asc.get(path);
    const hit = (page.data || []).find((e) => e.attributes.link === link && e.attributes.status !== 'REMOVED');
    if (hit) {
      const locIds = new Set(((hit.relationships || {}).localizations?.data || []).map((l) => l.id));
      const loc = (page.included || []).find((i) => i.type === 'appClipAdvancedExperienceLocalizations' && (locIds.size === 0 || locIds.has(i.id)));
      return { id: hit.id, status: hit.attributes.status, title: loc?.attributes?.title, subtitle: loc?.attributes?.subtitle };
    }
    path = page.links && page.links.next ? page.links.next : null;
  }
  return null;
}

/// Only the picture can change on a published card (Apple refuses edits to
/// its localizations), so a text change is a new card instead (see syncVenue).
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
  const points = kind === 'register' && live ? rewardService.effectiveEarnRate(venue) : '';
  return crypto.createHash('md5').update([venue.venueName, points, coverUrl || '', kind, code, `v${HEADER_VERSION}`].join('|')).digest('hex');
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
    let target = current && current.id && current.link === link ? current : await findExperienceByLink(link);
    if (target && target.title === title && target.subtitle === subtitle) {
      const data = await updateExperienceImage({ id: target.id, imageId, status: target.status });
      record = { id: data.id, imageId, link, title, subtitle, fingerprint, status: data.attributes.status };
    } else {
      // The old card (rotated code, or old words) stops serving
      const old = (target && target.id) || (current && current.id);
      if (old) await removeExperience(old).catch((e) => console.warn('⚠️ App Clip: could not remove old experience:', e.message));
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
