// backend/services/scan/flyerReader.js — a specials board or event flyer →
// a draft announcement: title, message, and the event's date and times when
// it is one. Checked and posted by the owner in the form.
// Clairic reads the date and times (near-certain on real flyers); Claude
// Haiku writes the title and message, because Clairic mangles free wording
// ("HAPP HOUR", "lattes & &ries", 2026-10-21 live test). Either one alone
// still gives a draft.
const clairic = require('./clairic');

const API_URL = 'https://api.anthropic.com/v1/messages';
const WORDING_MODEL = process.env.SCAN_FLYER_MODEL || 'claude-haiku-4-5';
const WORDING_TIMEOUT_MS = 30000;

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

const WORDING_TOOL = {
  name: 'flyer',
  description: 'The flyer or specials board, as an announcement',
  input_schema: {
    type: 'object',
    properties: {
      title: { type: 'string', description: `The headline, as printed (the special or event's name), at most ${TITLE_MAX} characters` },
      details: { type: 'string', description: `What it is, in the flyer's own words: the deal, prices, what's on, conditions. Leave out the date and times. At most ${MESSAGE_MAX} characters` }
    },
    required: ['title', 'details']
  }
};

/** Claude reads the wording: { title, details } | null when it can't. */
async function readWording(images) {
  if (!process.env.ANTHROPIC_API_KEY) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), WORDING_TIMEOUT_MS);
  try {
    const res = await fetch(API_URL, {
      method: 'POST',
      headers: { 'x-api-key': process.env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({
        model: WORDING_MODEL, max_tokens: 600, temperature: 0,
        system: 'You copy a business\u2019s flyer or specials board into the flyer tool. Use its own words, fix only obvious line breaks, and invent nothing.',
        tools: [WORDING_TOOL], tool_choice: { type: 'tool', name: 'flyer' },
        messages: [{ role: 'user', content: [
          ...images.map((img) => ({ type: 'image', source: { type: 'base64', media_type: img.mediaType, data: img.base64 } })),
          { type: 'text', text: 'Copy this flyer into the flyer tool.' }
        ] }]
      }),
      signal: controller.signal
    });
    if (!res.ok) { console.error('Flyer wording failed:', res.status); return null; }
    const data = await res.json();
    const tool = (data.content || []).find((c) => c.type === 'tool_use');
    if (!tool || !tool.input) return null;
    return { title: tool.input.title || '', details: tool.input.details || '', usage: data.usage || {} };
  } catch (e) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Clairic's draft (or null) + Claude's wording (or null) → one draft. The
 * wording wins for title and message; dates and times come from Clairic. Pure.
 */
function mergeWording(draft, wording) {
  const base = draft || { title: '', message: '', event: null, expiresOn: null, unsure: [] };
  if (!wording || (!wording.title && !wording.details)) return base;
  return {
    ...base,
    title: wording.title ? clip(wording.title, TITLE_MAX) : base.title,
    message: wording.details ? clip(wording.details, MESSAGE_MAX) : base.message,
    unsure: base.unsure.filter((f) => f !== 'title' && f !== 'details')
  };
}

async function read(images, { referenceDate } = {}) {
  const [fieldsResult, wording] = await Promise.all([
    clairic.extract({ fields: fields(), images, referenceDate }).then((r) => ({ ok: r }), (e) => ({ error: e })),
    readWording(images)
  ]);
  if (fieldsResult.error && !wording) throw fieldsResult.error;
  if (fieldsResult.error) console.warn('Flyer dates unavailable (Clairic):', fieldsResult.error.message);
  const draft = mergeWording(fieldsResult.ok ? toDraft(fieldsResult.ok.answers) : null, wording);
  return {
    draft,
    usage: {
      engine: wording ? 'clairic+claude' : 'clairic',
      inputTokens: ((fieldsResult.ok && fieldsResult.ok.usage.input_tokens) || 0) + ((wording && wording.usage.input_tokens) || 0),
      outputTokens: (wording && wording.usage.output_tokens) || 0
    }
  };
}

module.exports = { TITLE_MAX, MESSAGE_MAX, fields, toDraft, mergeWording, read };
