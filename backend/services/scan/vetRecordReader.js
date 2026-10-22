// backend/services/scan/vetRecordReader.js — "Import from your vet" (Wes,
// 2026-10-22: "add a way to import pet records from people's vets"). There
// is no common vet system to connect to, so the person brings the records:
// up to 4 photos of the paperwork, or the PDF the vet emailed. Claude Haiku
// copies out vaccines (with due dates), visits, medications, weights and the
// clinic into a DRAFT; the phone shows it for review and merges what they
// keep into their private dog records. Nothing is stored here: no upload,
// no public URL, only a usage line (tokens, no content).
const { ServiceError } = require('../../utils/serviceError');

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = process.env.SCAN_VET_MODEL || 'claude-haiku-4-5';
const MAX_OUTPUT_TOKENS = 8000;
const TIMEOUT_MS = 90000;
const MAX_PDF_BYTES = 10 * 1024 * 1024;
const MAX_PDF_PAGES = 20;
const MAX_ROWS = 100;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const KG_TO_LBS = 2.20462;

const SYSTEM = `You read a pet's veterinary records (invoices, visit summaries, vaccine certificates, rabies tags, discharge notes) and copy the facts into the pet records tool.
- Copy only what the records say. Don't guess, infer or add medical advice.
- Dates: YYYY-MM-DD. If only a month and year are shown, use the 1st and set unsure. If a year is missing, leave the date empty.
- vaccines: one row per vaccine given. name as printed (e.g. "Rabies 3yr", "DHPP", "Bordetella"). givenOn = date given; dueOn = the next-due or expiry date printed for it.
- vetVisits: one row per visit/exam date, with the clinic and the reason (e.g. "Annual exam", "Ear infection").
- medications: prescriptions and preventives (heartworm, flea and tick) with dose and how often.
- weights: each weight recorded, with its unit as printed.
- vet: the clinic's name, phone and address from the letterhead.
- petName: the patient's name if shown. If the records cover several pets, only copy the pet named in the request, or the first pet if none is named, and say so in notes.
- unsure: true for any row where the text was blurry, cut off or you had to guess.
- If these aren't pet medical records, return empty lists and say so in notes.`;

const TOOL = {
  name: 'pet_records',
  description: "The pet's records exactly as shown.",
  input_schema: {
    type: 'object',
    properties: {
      petName: { type: 'string' },
      vet: {
        type: 'object',
        properties: { clinic: { type: 'string' }, phone: { type: 'string' }, address: { type: 'string' } }
      },
      vaccines: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string' }, givenOn: { type: 'string' }, dueOn: { type: 'string' },
            notes: { type: 'string' }, unsure: { type: 'boolean' }
          },
          required: ['name']
        }
      },
      vetVisits: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            date: { type: 'string' }, clinic: { type: 'string' }, reason: { type: 'string' },
            notes: { type: 'string' }, unsure: { type: 'boolean' }
          },
          required: ['date']
        }
      },
      medications: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string' }, dose: { type: 'string' }, schedule: { type: 'string' },
            startedOn: { type: 'string' }, endsOn: { type: 'string' }, unsure: { type: 'boolean' }
          },
          required: ['name']
        }
      },
      weights: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            date: { type: 'string' }, value: { type: 'number' }, unit: { type: 'string', description: 'lb or kg' },
            unsure: { type: 'boolean' }
          },
          required: ['value']
        }
      },
      notes: { type: 'string', description: 'Anything the owner should know, e.g. a page that was cut off.' }
    },
    required: ['vaccines', 'vetVisits', 'medications', 'weights']
  }
};

const isConfigured = () => !!process.env.ANTHROPIC_API_KEY;

const text = (v, max) => String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max);

/** "2024-03-07" that is a real calendar date, or null. Pure. */
function isoDate(v) {
  const s = text(v, 10);
  if (!DATE_RE.test(s)) return null;
  const t = Date.parse(`${s}T00:00:00Z`);
  return Number.isFinite(t) && new Date(t).toISOString().slice(0, 10) === s ? s : null;
}

const rows = (list) => (Array.isArray(list) ? list : []).slice(0, MAX_ROWS);

/** The model's tool input → a clean draft. Pure. */
function toDraft(input) {
  const i = input || {};
  const vet = i.vet || {};
  const vaccines = [];
  const seen = new Set();
  for (const v of rows(i.vaccines)) {
    const name = text(v && v.name, 60);
    if (!name) continue;
    const givenOn = isoDate(v.givenOn);
    const key = `${name.toLowerCase()}|${givenOn || ''}`;
    if (seen.has(key)) continue; // the same shot on two pages of one invoice
    seen.add(key);
    vaccines.push({ name, givenOn, dueOn: isoDate(v.dueOn), notes: text(v.notes, 200) || null, unsure: v.unsure === true || (!!text(v.givenOn, 20) && !givenOn) });
  }
  const vetVisits = rows(i.vetVisits).map((v) => ({
    date: isoDate(v && v.date),
    clinic: text(v && v.clinic, 80) || null,
    reason: text(v && v.reason, 120) || null,
    notes: text(v && v.notes, 300) || null,
    unsure: !!(v && v.unsure === true)
  })).filter((v) => v.date);
  const medications = rows(i.medications).map((m) => ({
    name: text(m && m.name, 80),
    dose: text(m && m.dose, 60) || null,
    schedule: text(m && m.schedule, 60) || null,
    startedOn: isoDate(m && m.startedOn),
    endsOn: isoDate(m && m.endsOn),
    unsure: !!(m && m.unsure === true)
  })).filter((m) => m.name);
  const weights = rows(i.weights).map((w) => {
    const value = Number(w && w.value);
    if (!Number.isFinite(value) || value <= 0) return null;
    const kg = /^kg|kilo/i.test(text(w.unit, 10));
    const lbs = Math.round((kg ? value * KG_TO_LBS : value) * 10) / 10;
    if (lbs > 400) return null;
    return { date: isoDate(w.date), lbs, unsure: w.unsure === true };
  }).filter(Boolean);
  return {
    petName: text(i.petName, 40) || null,
    vet: {
      clinic: text(vet.clinic, 80) || null,
      phone: text(vet.phone, 30) || null,
      address: text(vet.address, 200) || null
    },
    vaccines,
    vetVisits,
    medications,
    weights,
    notes: text(i.notes, 300) || null
  };
}

/** A base64 PDF → { base64, pages }, checked. */
function preparePdf(raw) {
  const base64 = typeof raw === 'string' ? (raw.startsWith('data:') ? raw.slice(raw.indexOf(',') + 1) : raw) : '';
  let buf = null;
  try { buf = Buffer.from(base64, 'base64'); } catch (e) { buf = null; }
  if (!buf || !buf.length || buf.slice(0, 5).toString('latin1') !== '%PDF-') {
    throw new ServiceError(400, 'bad_pdf', 'That file isn’t a PDF we can read.');
  }
  if (buf.length > MAX_PDF_BYTES) throw new ServiceError(413, 'pdf_too_large', 'That PDF is too large (10 MB at most).');
  // Page objects (not the /Pages tree): a rough count, enough for a cap
  const pages = (buf.toString('latin1').match(/\/Type\s*\/Page(?!s)/g) || []).length;
  if (pages > MAX_PDF_PAGES) throw new ServiceError(413, 'pdf_too_long', `That PDF has more than ${MAX_PDF_PAGES} pages. Try just the latest records.`);
  return { base64: buf.toString('base64'), pages };
}

/** images: [{ base64, mediaType }] (services/scan/images.prepare) or pdf: { base64 }. */
async function read({ images = [], pdf = null, dogName = null } = {}) {
  if (!isConfigured()) throw new ServiceError(503, 'scan_unavailable', 'Reading records isn’t available right now. You can add them by hand.');
  const named = dogName ? ` The pet is named ${text(dogName, 40)}.` : '';
  const content = pdf
    ? [{ type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: pdf.base64 } }]
    : images.map((img) => ({ type: 'image', source: { type: 'base64', media_type: img.mediaType, data: img.base64 } }));
  content.push({ type: 'text', text: `Copy these pet records into the pet records tool.${named}` });
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let res;
  try {
    res = await fetch(API_URL, {
      method: 'POST',
      headers: { 'x-api-key': process.env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({
        model: MODEL, max_tokens: MAX_OUTPUT_TOKENS, temperature: 0, system: SYSTEM,
        tools: [TOOL], tool_choice: { type: 'tool', name: TOOL.name },
        messages: [{ role: 'user', content }]
      }),
      signal: controller.signal
    });
  } catch (e) {
    throw new ServiceError(503, 'scan_unavailable', 'Reading the records took too long. Try fewer pages at once.');
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    console.error('Vet record scan failed:', res.status, (await res.text().catch(() => '')).slice(0, 300));
    throw new ServiceError(503, 'scan_unavailable', 'Reading records isn’t available right now. You can add them by hand.');
  }
  const data = await res.json();
  const tool = (data.content || []).find((c) => c.type === 'tool_use');
  return {
    draft: toDraft(tool && tool.input),
    usage: {
      engine: 'claude', model: MODEL,
      inputTokens: (data.usage && data.usage.input_tokens) || 0,
      outputTokens: (data.usage && data.usage.output_tokens) || 0,
      truncated: data.stop_reason === 'max_tokens'
    }
  };
}

module.exports = { MODEL, SYSTEM, TOOL, MAX_PDF_BYTES, MAX_PDF_PAGES, isConfigured, isoDate, toDraft, preparePdf, read };
