// backend/services/scan/medReader.js — photos of prescription labels or
// medicine boxes → DRAFT medication reminders for the Medications widget
// (Wes, 2026-11-23). Claude Haiku reads the label; the reminder times come
// from the frequency it reports, mapped here (pure, tested), never from the
// model's guess. Nothing is saved and the photo is not kept: the person
// checks every field in the widget, confirms, and the widget saves to their
// own private widget data.
//
// Only the medicine itself is read: name, strength, amount, directions and
// short warnings. The patient's name, Rx number, pharmacy, prescriber and
// phone numbers are never asked for, returned or logged.
const { ServiceError } = require('../../utils/serviceError');

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = process.env.SCAN_MED_MODEL || 'claude-haiku-4-5';
const MAX_OUTPUT_TOKENS = 3000;
const TIMEOUT_MS = 45000;
const MAX_MEDS = 12;

const FREQUENCIES = [
  'once_daily', 'morning', 'evening', 'bedtime', 'twice_daily', 'three_times_daily',
  'four_times_daily', 'with_meals', 'every_n_hours', 'weekly', 'as_needed', 'other'
];

const SYSTEM = `You read photos of prescription labels, pharmacy bottles and medicine boxes and copy each medicine into the medications tool, so the person can set reminders.
- One entry per distinct medicine. Several photos of the same bottle are one medicine.
- name: the drug name as printed, e.g. "Lisinopril" or "Amoxicillin". Brand in parentheses if both are printed.
- strength: as printed, e.g. "10 mg", "500 mg", "5 mg/5 mL". Empty if not shown.
- amount: how much per dose, e.g. "1 tablet", "2 capsules", "10 mL". Empty if not shown.
- directions: the directions exactly as printed, e.g. "Take 1 tablet by mouth twice daily with food".
- frequency: pick from the list ONLY when the directions state it. "every 8 hours" = every_n_hours with everyHours 8. "once a week on Monday" = weekly with weekday 2 (1 = Sunday … 7 = Saturday). "as needed"/"PRN" = as_needed. Anything else (every other day, tapering, "use as directed", no directions) = other. Never guess a frequency the label doesn't state.
- clockTimes: only if the label prints clock times ("at 8 AM and 8 PM"), as "HH:MM" 24-hour. Otherwise empty.
- note: a short instruction worth repeating at reminder time, e.g. "With food", "Avoid alcohol". Empty if none.
- unsure: true when the photo is blurry, cut off, or you guessed at any field.
- NEVER copy the patient's name, Rx number, pharmacy, prescriber, address or phone numbers anywhere.
- If the photos show no medicine label, return no medications and say so in notes.`;

const TOOL = {
  name: 'medications',
  description: 'Each medicine shown on the labels.',
  input_schema: {
    type: 'object',
    properties: {
      medications: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            strength: { type: 'string' },
            amount: { type: 'string' },
            directions: { type: 'string' },
            frequency: { type: 'string', enum: FREQUENCIES },
            everyHours: { type: 'integer', description: 'Only for every_n_hours.' },
            weekday: { type: 'integer', description: 'Only for weekly: 1 = Sunday … 7 = Saturday, when the label names the day.' },
            clockTimes: { type: 'array', items: { type: 'string' } },
            note: { type: 'string' },
            unsure: { type: 'boolean' }
          },
          required: ['name', 'frequency']
        }
      },
      notes: { type: 'string', description: 'Anything the person should know, e.g. a label that was cut off.' }
    },
    required: ['medications']
  }
};

const isConfigured = () => !!process.env.ANTHROPIC_API_KEY;

const H = 60;
/** frequency → reminder minutes after midnight, or null when the label doesn't say. */
const DEFAULT_TIMES = {
  once_daily: [8 * H],
  morning: [8 * H],
  evening: [18 * H],
  bedtime: [21 * H],
  twice_daily: [8 * H, 20 * H],
  three_times_daily: [8 * H, 14 * H, 20 * H],
  four_times_daily: [8 * H, 12 * H, 16 * H, 20 * H],
  with_meals: [8 * H, 12 * H, 18 * H],
  weekly: [8 * H]
};

/** "08:30" / "8:30 PM" / "20:00" → minutes, or null. Pure. */
function parseClock(text) {
  const m = String(text || '').trim().match(/^(\d{1,2})(?::(\d{2}))?\s*([ap])?\.?m?\.?$/i);
  if (!m) return null;
  let h = parseInt(m[1], 10);
  const min = m[2] ? parseInt(m[2], 10) : 0;
  const ap = m[3] && m[3].toLowerCase();
  if (ap === 'p' && h < 12) h += 12;
  if (ap === 'a' && h === 12) h = 0;
  if (h > 23 || min > 59) return null;
  return h * H + min;
}

/** One medicine's schedule from the label: { times, days, asNeeded, unsure, why }. Pure. */
function schedule(item) {
  const freq = FREQUENCIES.includes(item && item.frequency) ? item.frequency : 'other';
  const printed = (Array.isArray(item && item.clockTimes) ? item.clockTimes : []).map(parseClock).filter((v) => v != null);
  const uniq = (list) => Array.from(new Set(list)).sort((a, b) => a - b).slice(0, 6);
  if (freq === 'as_needed') {
    return { times: [], days: [], asNeeded: true, unsure: false, why: 'Take as needed: no reminder unless you add a time.' };
  }
  if (freq === 'other') {
    return { times: uniq(printed), days: [], asNeeded: false, unsure: true, why: 'The label doesn’t give a simple daily schedule. Set the times yourself.' };
  }
  if (freq === 'every_n_hours') {
    const n = parseInt(item.everyHours, 10);
    if (!(n >= 2 && n <= 24)) return { times: uniq(printed), days: [], asNeeded: false, unsure: true, why: 'Couldn’t read how many hours apart. Set the times yourself.' };
    const times = [];
    for (let m = 8 * H; m < 8 * H + 24 * H && times.length < 6; m += n * H) times.push(m % (24 * H));
    return { times: uniq(printed.length ? printed : times), days: [], asNeeded: false, unsure: true, why: `Every ${n} hours, starting at 8 AM. Move the times to fit your day.` };
  }
  if (freq === 'weekly') {
    const d = parseInt(item.weekday, 10);
    if (!(d >= 1 && d <= 7)) return { times: [], days: [], asNeeded: false, unsure: true, why: 'Once a week, but the label doesn’t say which day. Pick the day and time.' };
    return { times: uniq(printed.length ? printed : DEFAULT_TIMES.weekly), days: [d], asNeeded: false, unsure: false, why: null };
  }
  const times = printed.length ? uniq(printed) : DEFAULT_TIMES[freq].slice();
  return { times, days: [], asNeeded: false, unsure: false, why: printed.length ? null : 'Suggested times. Change them to fit your day.' };
}

/** The model's tool input → draft medications: trimmed, deduped, scheduled. Pure. */
function toDraft(input) {
  const clean = (v, max) => String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max);
  const seen = new Set();
  const meds = [];
  for (const it of (Array.isArray(input && input.medications) ? input.medications : [])) {
    if (meds.length >= MAX_MEDS) break;
    const name = clean(it && it.name, 80);
    if (!name) continue;
    const strength = clean(it.strength, 40);
    const key = `${name.toLowerCase()}|${strength.toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const s = schedule(it);
    meds.push({
      name,
      strength: strength || null,
      amount: clean(it.amount, 40) || null,
      directions: clean(it.directions, 240) || null,
      note: clean(it.note, 80) || null,
      frequency: FREQUENCIES.includes(it.frequency) ? it.frequency : 'other',
      times: s.times,
      days: s.days,
      asNeeded: s.asNeeded,
      unsure: it.unsure === true || s.unsure,
      why: s.why
    });
  }
  return { medications: meds, notes: clean(input && input.notes, 300) || null };
}

async function read(images) {
  if (!isConfigured()) throw new ServiceError(503, 'scan_unavailable', 'Label scanning isn’t available right now. You can add medications by hand.');
  const content = [
    ...images.map((img) => ({ type: 'image', source: { type: 'base64', media_type: img.mediaType, data: img.base64 } })),
    { type: 'text', text: images.length > 1 ? `These ${images.length} photos are medicine labels. Copy each medicine into the medications tool.` : 'Copy the medicine on this label into the medications tool.' }
  ];
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let res;
  try {
    res = await fetch(API_URL, {
      method: 'POST',
      headers: { 'x-api-key': process.env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({
        model: MODEL, max_tokens: MAX_OUTPUT_TOKENS, temperature: 0, system: SYSTEM,
        tools: [TOOL], tool_choice: { type: 'tool', name: 'medications' },
        messages: [{ role: 'user', content }]
      }),
      signal: controller.signal
    });
  } catch (e) {
    throw new ServiceError(503, 'scan_unavailable', 'Reading the label took too long. Try again.');
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    // Status only: the error body can echo the request, which is health data
    console.error('Medication label scan failed:', res.status);
    throw new ServiceError(503, 'scan_unavailable', 'Label scanning isn’t available right now. You can add medications by hand.');
  }
  const data = await res.json();
  const tool = (data.content || []).find((c) => c.type === 'tool_use');
  return {
    draft: toDraft(tool && tool.input),
    usage: { engine: 'claude', model: MODEL, inputTokens: (data.usage && data.usage.input_tokens) || 0, outputTokens: (data.usage && data.usage.output_tokens) || 0, truncated: data.stop_reason === 'max_tokens' }
  };
}

module.exports = { MODEL, SYSTEM, TOOL, FREQUENCIES, DEFAULT_TIMES, isConfigured, parseClock, schedule, toDraft, read };
