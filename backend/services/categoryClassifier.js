// backend/services/categoryClassifier.js
//
// Tier 3 of category derivation: an LLM classifier for the residual `other`
// tail that the free deterministic + text tiers can't resolve. Kept behind a
// flag and invoked ONLY by the backfill script / an async post-save hook —
// never on the request hot path.
//
// Cost controls baked in:
//   - Off unless CATEGORY_LLM_ENABLED=true and ANTHROPIC_API_KEY is set.
//   - Batched (many places per call) to amortize the system prompt.
//   - Cheap model (Haiku) by default; overridable via CATEGORY_LLM_MODEL.
//   - Forced tool output constrained to the enum → no free-text parsing.
//   - Returns token usage so callers can log real spend.
//
// No SDK dependency: a direct fetch to the Messages API (Node 18+ global fetch).

const { AUTO_CATEGORIES } = require('./placeCategoryDerivation');

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = process.env.CATEGORY_LLM_MODEL || 'claude-haiku-4-5';
const CONFIDENCE_FLOOR = parseFloat(process.env.CATEGORY_LLM_CONFIDENCE_FLOOR || '0.5');

function isEnabled() {
  return process.env.CATEGORY_LLM_ENABLED === 'true' && !!process.env.ANTHROPIC_API_KEY;
}

const CATEGORY_DEFINITIONS = `
- restaurant: places whose primary purpose is a sit-down or takeout meal
- cafe: coffee/tea shops, bakeries, dessert/ice-cream spots
- bar: bars, pubs, breweries, wineries, nightclubs, lounges
- hotel: lodging of any kind (hotel, motel, inn, B&B, resort)
- retail: stores and shops selling goods (clothing, grocery, books, malls)
- service: personal/auto/home services (salon, spa, laundry, repair, post office)
- attraction: museums, galleries, landmarks, monuments, zoos, aquariums, places of worship
- entertainment: cinemas, theaters, arcades, bowling, casinos, stadiums, amusement parks
- healthcare: hospitals, doctors, dentists, pharmacies, clinics, veterinary
- fitness: gyms, studios (yoga/pilates/crossfit), climbing, sports clubs
- education: schools, universities, libraries
- outdoor: parks, trails, beaches, campgrounds, gardens, natural features
- transport: airports, transit stations, parking, gas/EV, car rental
- finance: banks, ATMs, credit unions
- other: only when none of the above genuinely fits`;

const TOOL = {
  name: 'classify_places',
  description: 'Assign exactly one category to each place, in the same order as the input.',
  input_schema: {
    type: 'object',
    properties: {
      results: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            id: { type: 'string', description: 'The place id, copied verbatim from the input' },
            category: { type: 'string', enum: AUTO_CATEGORIES },
            confidence: { type: 'number', description: '0 to 1; how confident you are' }
          },
          required: ['id', 'category', 'confidence']
        }
      }
    },
    required: ['results']
  }
};

const SYSTEM_PROMPT =
  'You categorize real-world places into exactly one category from a fixed list. ' +
  'Use the name, description, address, and any type hints provided. ' +
  'Choose the single best fit. If genuinely ambiguous or none fit, use "other". ' +
  'Never invent categories outside the list.\n\nCategories:' + CATEGORY_DEFINITIONS;

// places: [{ id, name, description?, address?, googleTypes?, applePoiCategory? }]
// Returns { results: [{id, category, confidence}], usage: {input_tokens, output_tokens} }
async function classifyOneBatch(places) {
  const payload = places.map(p => ({
    id: p.id,
    name: p.name || '',
    description: p.description || '',
    address: p.address || '',
    typeHints: [p.applePoiCategory, ...(p.googleTypes || [])].filter(Boolean)
  }));

  const res = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json'
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 2048,
      temperature: 0,
      system: SYSTEM_PROMPT,
      tools: [TOOL],
      tool_choice: { type: 'tool', name: 'classify_places' },
      messages: [{ role: 'user', content: JSON.stringify(payload) }]
    })
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Anthropic API ${res.status}: ${body.slice(0, 300)}`);
  }

  const data = await res.json();
  const toolUse = (data.content || []).find(c => c.type === 'tool_use');
  const rawResults = (toolUse && toolUse.input && toolUse.input.results) || [];

  // Validate defensively: enum membership + confidence floor. Anything that
  // fails stays 'other' (it remains in the tail for a future run).
  const allowed = new Set(AUTO_CATEGORIES);
  const results = rawResults.map(r => {
    const ok = allowed.has(r.category) && typeof r.confidence === 'number' && r.confidence >= CONFIDENCE_FLOOR;
    return {
      id: r.id,
      category: ok ? r.category : 'other',
      confidence: typeof r.confidence === 'number' ? r.confidence : 0
    };
  });

  return {
    results,
    usage: {
      input_tokens: (data.usage && data.usage.input_tokens) || 0,
      output_tokens: (data.usage && data.usage.output_tokens) || 0
    }
  };
}

// Classify many places, chunked. Returns { byId: Map, usage, calls }.
async function classifyPlaces(places, { batchSize = 20 } = {}) {
  if (!isEnabled()) {
    throw new Error('LLM tier disabled (set CATEGORY_LLM_ENABLED=true and ANTHROPIC_API_KEY)');
  }
  const byId = new Map();
  const usage = { input_tokens: 0, output_tokens: 0 };
  let calls = 0;

  for (let i = 0; i < places.length; i += batchSize) {
    const chunk = places.slice(i, i + batchSize);
    const { results, usage: u } = await classifyOneBatch(chunk);
    calls++;
    usage.input_tokens += u.input_tokens;
    usage.output_tokens += u.output_tokens;
    results.forEach(r => byId.set(r.id, r));
  }

  return { byId, usage, calls };
}

// Rough USD estimate for logging (Haiku-class defaults; override via env).
// Verify current pricing — these are only for the backfill's spend log.
function estimateCostUSD(usage) {
  const inPer1M = parseFloat(process.env.CATEGORY_LLM_USD_PER_MTOK_IN || '1.0');
  const outPer1M = parseFloat(process.env.CATEGORY_LLM_USD_PER_MTOK_OUT || '5.0');
  return (usage.input_tokens / 1e6) * inPer1M + (usage.output_tokens / 1e6) * outPer1M;
}

module.exports = { isEnabled, classifyPlaces, classifyOneBatch, estimateCostUSD, MODEL };
