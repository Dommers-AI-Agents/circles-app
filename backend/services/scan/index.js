// backend/services/scan/index.js — store-owner scans (Wes, 2026-10-20):
// a photo of the menu, the hours on the door, or a specials/event flyer
// becomes a DRAFT for the matching editor. Nothing is saved here; the owner
// checks it (unsure fields are flagged) and saves through the usual paths.
// Business tier, 20 scans per venue per day, every scan's spend logged.
const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const dailyBudget = require('../dailyBudget');
const images = require('./images');

const KINDS = {
  menu: () => require('./menuReader'),
  hours: () => require('./hoursReader'),
  flyer: () => require('./flyerReader')
};

/** Today in the venue's own zone (dates on a flyer without a year). */
const localToday = (timeZone) => {
  try { return new Intl.DateTimeFormat('en-CA', { timeZone: timeZone || 'America/New_York' }).format(new Date()); }
  catch (e) { return new Date().toISOString().slice(0, 10); }
};

async function scan({ kind, images: raw, venue, userId, db = getFirestore() }) {
  const reader = KINDS[kind];
  if (!reader) throw new ServiceError(400, 'bad_kind', 'Choose what you’re scanning: a menu, hours or a flyer.');
  const prepared = await images.prepare(kind === 'menu' ? raw : (raw || []).slice(0, 1));
  const budget = await dailyBudget.consume('venueScan', venue.venueId);
  if (!budget.allowed) throw new ServiceError(429, 'scan_limit', `That’s ${budget.limit} scans today. Try again tomorrow.`);
  const started = Date.now();
  const { draft, usage } = await reader().read(prepared, { referenceDate: localToday(venue.timeZone) });
  db.collection('scanUsage').add({
    venueId: venue.venueId, userId, kind, images: prepared.length,
    ...usage, ms: Date.now() - started, at: new Date().toISOString()
  }).catch(() => {});
  return { kind, draft, truncated: !!usage.truncated };
}

module.exports = { KINDS, scan, localToday };
