// backend/services/nfcStickerService.js
// NFC stickers (2026-11-01): the store owner writes the store's window link
// onto cheap NFC tags (coasters, table stands, the counter) from Manage Store.
// Each sticker gets a tag on the link, /s/<windowCode>?t=<tag>, so a tap opens
// the store's own App Clip card (Apple matches the /s/<code> prefix) and the
// store sees which sticker gets tapped.
//
// Two kinds (Wes, 2026-11-05: "both window and register"): a WINDOW sticker
// (Love it here? Save us — table tents, coasters, the window) and a REGISTER
// sticker (earn points — the counter only, like the printed register card).
// A register sticker is never locked: replacing the register code changes its
// link, and a locked one would be dead. It shows as needing a rewrite then.
//
// Record on the venue: nfcStickers.<tag> =
//   { label, kind, createdAt, taps, lastTapAt, writtenAt, writtenCode, writes, locked }

const { getFirestore, FieldValue } = require('../config/firebase');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const { clean } = require('../utils/text');
const rewardService = require('./rewardService');

const MAX_STICKERS = 200;
const TAG_MAX = 24;
const LABEL_MAX = 40;

/// "Table 7" → "table-7". The tag is a URL piece and a Firestore field path
/// key, so only [a-z0-9-] survives. Nothing usable → null.
function tagKey(raw) {
  if (typeof raw !== 'string') return null;
  const tag = raw.toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, TAG_MAX)
    .replace(/-+$/, '');
  return tag || null;
}

const KINDS = ['window', 'register'];
const kindOf = (record) => (record && record.kind === 'register' ? 'register' : 'window');
const codeFor = (venue, kind) => (kind === 'register' ? venue.registerCode : venue.windowCode);

/// The link written onto the sticker: its kind's code, plus its tag
function stickerLink(venue, tag, kind = 'window') {
  return `${rewardService.stickerUrl(codeFor(venue, kind))}?t=${tag}`;
}

/// A tag not yet used on this venue: "table-7", then "table-7-2", …
function uniqueTag(base, taken) {
  if (!taken.has(base)) return base;
  for (let n = 2; ; n += 1) {
    const suffix = `-${n}`;
    const candidate = `${base.slice(0, TAG_MAX - suffix.length).replace(/-+$/, '')}${suffix}`;
    if (!taken.has(candidate)) return candidate;
  }
}

function listStickers(venue) {
  return Object.entries(venue.nfcStickers || {})
    .map(([tag, s]) => ({
      tag,
      label: s.label || tag,
      kind: kindOf(s),
      url: stickerLink(venue, tag, kindOf(s)),
      // Written with a code the store has since replaced: write it again
      needsRewrite: !!(s.writtenCode && String(s.writtenCode).toUpperCase() !== String(codeFor(venue, kindOf(s)) || '').toUpperCase()),
      taps: s.taps || 0,
      lastTapAt: s.lastTapAt || null,
      createdAt: s.createdAt || null,
      writtenAt: s.writtenAt || null,
      writes: s.writes || 0,
      locked: s.locked === true
    }))
    .sort((a, b) => String(a.createdAt || '').localeCompare(String(b.createdAt || '')));
}

const venueRef = (venueId) => getFirestore().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venueId);

async function createSticker(venue, rawLabel, rawKind = 'window') {
  const kind = KINDS.includes(rawKind) ? rawKind : 'window';
  if (!codeFor(venue, kind)) {
    throw new ServiceError(400, kind === 'register' ? 'NO_REGISTER_CODE' : 'NO_WINDOW_CODE',
      `This store has no ${kind} code yet`);
  }
  const label = clean(rawLabel, LABEL_MAX);
  if (!label) throw new ServiceError(400, 'LABEL_REQUIRED', 'Name the sticker, like "Table 7"');
  const existing = venue.nfcStickers || {};
  if (Object.keys(existing).length >= MAX_STICKERS) {
    throw new ServiceError(400, 'TOO_MANY_STICKERS', `A store can have up to ${MAX_STICKERS} stickers`);
  }
  const tag = uniqueTag(tagKey(label) || 'sticker', new Set(Object.keys(existing)));
  const record = { label, kind, createdAt: new Date().toISOString(), taps: 0 };
  await venueRef(venue.venueId).update({ [`nfcStickers.${tag}`]: record });
  return listStickers({ ...venue, nfcStickers: { ...existing, [tag]: record } }).find((s) => s.tag === tag);
}

function requireSticker(venue, rawTag) {
  const tag = tagKey(rawTag);
  if (!tag || !(venue.nfcStickers || {})[tag]) throw new ServiceError(404, 'STICKER_NOT_FOUND', 'Sticker not found');
  return tag;
}

/// The phone wrote (and maybe locked) a sticker with this tag's link
async function markWritten(venue, rawTag, { locked = false } = {}) {
  const tag = requireSticker(venue, rawTag);
  const kind = kindOf(venue.nfcStickers[tag]);
  if (locked && kind === 'register') {
    throw new ServiceError(400, 'REGISTER_NOT_LOCKABLE', 'Register stickers stay rewritable: replacing the register code changes their link');
  }
  const update = {
    [`nfcStickers.${tag}.writtenAt`]: new Date().toISOString(),
    [`nfcStickers.${tag}.writtenCode`]: codeFor(venue, kind) || null,
    [`nfcStickers.${tag}.writes`]: FieldValue.increment(1)
  };
  if (locked) update[`nfcStickers.${tag}.locked`] = true;
  await venueRef(venue.venueId).update(update);
}

async function renameSticker(venue, rawTag, rawLabel) {
  const tag = requireSticker(venue, rawTag);
  const label = clean(rawLabel, LABEL_MAX);
  if (!label) throw new ServiceError(400, 'LABEL_REQUIRED', 'Name the sticker, like "Table 7"');
  await venueRef(venue.venueId).update({ [`nfcStickers.${tag}.label`]: label });
}

/// Stops counting it. The sticker itself still opens the store: its link is
/// the store's window (or register) code.
async function deleteSticker(venue, rawTag) {
  const tag = requireSticker(venue, rawTag);
  await venueRef(venue.venueId).update({ [`nfcStickers.${tag}`]: FieldValue.delete() });
}

/// One tap on a sticker: `code` is the code the link carried. It counts only
/// for a tag the store made, carrying that sticker's own kind of code (a
/// typed URL can't fill the venue doc with junk). Never throws.
async function recordTap(venue, code, rawTag) {
  const tag = tagKey(rawTag);
  if (!venue || !tag || !(venue.nfcStickers || {})[tag]) return false;
  const expected = codeFor(venue, kindOf(venue.nfcStickers[tag]));
  if (String(code || '').toUpperCase() !== String(expected || '').toUpperCase()) return false;
  try {
    await venueRef(venue.venueId).update({
      [`nfcStickers.${tag}.taps`]: FieldValue.increment(1),
      [`nfcStickers.${tag}.lastTapAt`]: new Date().toISOString()
    });
    rewardService.incrementVenueStats(venue.venueId, 'nfcTaps');
    return true;
  } catch (error) {
    console.error(`⚠️ NFC sticker tap not counted (${venue.venueId}/${tag}):`, error.message);
    return false;
  }
}

module.exports = {
  MAX_STICKERS, TAG_MAX, LABEL_MAX,
  KINDS, tagKey, uniqueTag, stickerLink, listStickers,
  createSticker, markWritten, renameSticker, deleteSticker, recordTap
};
