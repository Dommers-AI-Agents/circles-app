// backend/services/scan/hoursReader.js — a photo of the hours on the door
// → a draft for the hours editor (Clairic). Never saved here: the owner
// checks it in the editor and saves through venueDetailsService.
const clairic = require('./clairic');

const DAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat']; // day 0-6, Sun = 0
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** The Clairic field map. Pure. */
function fields() {
  const out = {};
  DAYS.forEach((d, i) => {
    out[`${d}_open`] = { type: 'time', instructions: `Opening time on ${DAY_NAMES[i]}` };
    out[`${d}_close`] = { type: 'time', instructions: `Closing time on ${DAY_NAMES[i]}` };
    out[`${d}_closed`] = { type: 'text', instructions: `The word or phrase saying the store is closed all day on ${DAY_NAMES[i]}, if it says so` };
  });
  return out;
}

/** "07:00:00" / "7:00" → "07:00", or null. Pure. */
function hhmm(value) {
  const m = String(value || '').match(/^(\d{1,2}):(\d{2})/);
  if (!m) return null;
  const h = Number(m[1]); const min = Number(m[2]);
  if (h > 23 || min > 59) return null;
  return `${String(h).padStart(2, '0')}:${String(min).padStart(2, '0')}`;
}

/**
 * Clairic answers → { hours: [{day, open, close, isClosed, unsure}], found }.
 * A day the sign doesn't mention comes back empty (open/close null), not
 * guessed; `found` is how many days it read. Pure.
 */
function toDraft(answers) {
  let found = 0;
  const hours = DAYS.map((d, day) => {
    const open = clairic.read(answers[`${d}_open`]);
    const close = clairic.read(answers[`${d}_close`]);
    const closed = clairic.read(answers[`${d}_closed`]);
    const o = hhmm(open.value); const c = hhmm(close.value);
    if (closed.value && !o) {
      found += 1;
      return { day, open: null, close: null, isClosed: true, unsure: closed.unsure };
    }
    if (o || c) found += 1;
    return { day, open: o, close: c, isClosed: false, unsure: open.unsure || close.unsure || (!!o !== !!c) };
  });
  return { hours, found };
}

async function read(images) {
  const { answers, usage } = await clairic.extract({ fields: fields(), images });
  return { draft: toDraft(answers), usage: { engine: 'clairic', inputTokens: usage.input_tokens || 0 } };
}

module.exports = { DAYS, fields, hhmm, toDraft, read };
