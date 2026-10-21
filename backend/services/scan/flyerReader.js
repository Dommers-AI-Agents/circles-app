// backend/services/scan/flyerReader.js — a specials board or event flyer →
// a draft announcement (Clairic): title, message, and the event's date and
// times when it is one. Checked and posted by the owner in the form.
const clairic = require('./clairic');

const TITLE_MAX = 80;
const MESSAGE_MAX = 500;

function fields() {
  return {
    title: { type: 'text', instructions: 'The headline: the special or the event’s name' },
    details: { type: 'text', instructions: 'What it is: the deal, prices, what’s on, any conditions' },
    event_date: { type: 'date', instructions: 'The date the event or special happens, if it is a one-time event' },
    start_time: { type: 'time', instructions: 'When it starts' },
    end_time: { type: 'time', instructions: 'When it ends' },
    is_free: { type: 'text', instructions: 'Words saying entry is free, if it says so' },
    ends_on: { type: 'date', instructions: 'The last day a special or offer is good for, if it says' }
  };
}

const clip = (s, max) => {
  const t = String(s || '').replace(/\s+/g, ' ').trim();
  return t.length > max ? `${t.slice(0, max - 1).trim()}…` : t;
};

/**
 * Clairic answers → { title, message, event: { localDate, localTime,
 * endTime, isFree } | null, expiresOn, unsure: [field names] }. Pure.
 */
function toDraft(answers) {
  const unsure = [];
  const get = (name) => {
    const r = clairic.read(answers[name]);
    if (r.value !== null && r.unsure) unsure.push(name);
    return r.value;
  };
  const title = get('title'); const details = get('details');
  const date = get('event_date'); const start = get('start_time'); const end = get('end_time');
  const free = get('is_free'); const endsOn = get('ends_on');
  const hhmm = (v) => { const m = String(v || '').match(/^(\d{1,2}):(\d{2})/); return m ? `${m[1].padStart(2, '0')}:${m[2]}` : null; };
  const isoDate = (v) => { const m = String(v || '').match(/^\d{4}-\d{2}-\d{2}/); return m ? m[0] : null; };
  const localDate = isoDate(date);
  return {
    title: title ? clip(title, TITLE_MAX) : '',
    message: details ? clip(details, MESSAGE_MAX) : '',
    event: localDate ? { localDate, localTime: hhmm(start), endTime: hhmm(end), isFree: free ? true : null } : null,
    expiresOn: localDate ? null : isoDate(endsOn),
    unsure
  };
}

async function read(images, { referenceDate } = {}) {
  const { answers, usage } = await clairic.extract({ fields: fields(), images, referenceDate });
  return { draft: toDraft(answers), usage: { engine: 'clairic', inputTokens: usage.input_tokens || 0 } };
}

module.exports = { TITLE_MAX, MESSAGE_MAX, fields, toDraft, read };
