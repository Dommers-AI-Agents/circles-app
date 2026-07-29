// Advises on circle organization — it does not reorganize anything.
//
// A long-lived account ends up with circles built on several different
// organizing schemes at once: by city ("Charlotte NC"), by type ("Pizza
// Slices"), by who recommended them ("Brittany's Places"), by a particular trip
// ("Rhode Island weekend July 2025"), plus system circles. Each of those is a
// good answer to a different question, so there is no single "correct"
// reorganization to compute — an AI that picked one would have to destroy four
// valid ones.
//
// What an LLM is genuinely good at here is narrower and safer:
//   1. Labelling which scheme each circle uses, so the grid can group itself.
//   2. Spotting circles that overlap enough to be worth merging.
//
// Both are proposals. Nothing is applied without the person approving it, and
// the merge path routes through the normal soft-delete so trash can undo it.
//
// Follows the pattern established by categoryClassifier.js: a direct fetch to
// the Messages API rather than an SDK dependency, flag-gated, and never on a
// hot path.

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = process.env.CIRCLE_ADVISOR_MODEL || 'claude-opus-5';
const MAX_CIRCLES = 60;

const isEnabled = () =>
  process.env.CIRCLE_ADVISOR_ENABLED === 'true' && !!process.env.ANTHROPIC_API_KEY;

/** The organizing schemes a circle can use. */
const SCHEMES = ['place', 'type', 'person', 'trip', 'system', 'unclear'];

const SCHEME_DEFINITIONS = `
- place: organized around a geography — a city, neighborhood, region, or airport ("Charlotte NC", "Jersey Shore", "EWR")
- type: organized around a kind of venue or occasion ("Pizza Slices", "Coffee Spots", "Breakfast & Brunch")
- person: organized around who recommended or is associated with the places ("Brittany's Places", "Margies Recommendations", "Family")
- trip: organized around a specific journey or dated event ("Road trip to NJ from phx!", "Rhode Island weekend July 2025")
- system: created by the app rather than the person ("Check-in Places", "Places I Follow")
- unclear: the name and contents genuinely don't indicate a scheme`;

/**
 * JSON schema for the model's reply. Structured outputs mean we never parse
 * free text, and an unexpected shape fails loudly at the API rather than
 * halfway through the client.
 */
const RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    schemes: {
      type: 'array',
      description: 'One entry per circle supplied, in any order.',
      items: {
        type: 'object',
        properties: {
          circleId: { type: 'string' },
          scheme: { type: 'string', enum: SCHEMES },
          confidence: { type: 'number', description: '0 to 1' }
        },
        required: ['circleId', 'scheme', 'confidence'],
        additionalProperties: false
      }
    },
    merges: {
      type: 'array',
      description:
        'Groups of circles that overlap enough to be worth combining. Empty when nothing overlaps. Never propose merging circles that use different schemes.',
      items: {
        type: 'object',
        properties: {
          circleIds: {
            type: 'array',
            items: { type: 'string' },
            description: 'Two or more circle ids to combine.'
          },
          keepCircleId: {
            type: 'string',
            description: 'Which of those circles should absorb the others.'
          },
          suggestedName: { type: 'string' },
          reason: {
            type: 'string',
            description: 'One sentence, addressed to the owner, naming the concrete overlap.'
          }
        },
        required: ['circleIds', 'keepCircleId', 'suggestedName', 'reason'],
        additionalProperties: false
      }
    }
  },
  required: ['schemes', 'merges'],
  additionalProperties: false
};

const SYSTEM_PROMPT = `You help someone make sense of their saved-places collection.

Their circles are organized several different ways at once, and that is normal — a city circle and a "best pizza" circle answer different questions, and both are worth keeping. You are not reorganizing anything. You are labelling what is already there and pointing out genuine redundancy.

Schemes:${SCHEME_DEFINITIONS}

Rules for merge proposals:
- Only propose a merge when the circles genuinely cover the same ground — the same city or region, or the same venue type in the same area.
- Never merge circles that use different schemes. A person circle and a city circle are not redundant even when their places overlap.
- Never propose merging a system circle into anything.
- A trip circle is a memory of a specific journey. Do not merge it into a place circle even when the geography matches.
- Prefer keeping the circle with the most places as the one that absorbs the others.
- Propose nothing rather than reaching. An empty merges list is a good answer.
- Write each reason in one sentence, addressed to the owner, naming the concrete overlap.`;

/** Compact description of one circle for the model. */
const describeCircle = (circle) => {
  const parts = [`id=${circle.id}`, `name=${JSON.stringify(circle.name || 'Untitled')}`];
  parts.push(`places=${circle.placesCount || 0}`);
  if (circle.topCategories?.length) parts.push(`categories=${circle.topCategories.join('/')}`);
  if (circle.topCities?.length) parts.push(`cities=${circle.topCities.join('/')}`);
  if (circle.isSystem) parts.push('system=true');
  return parts.join(' ');
};

/** The user-turn text. Exported for testing without a network call. */
const buildPrompt = (circles) =>
  `Here are the circles, one per line:\n\n${circles.map(describeCircle).join('\n')}\n\n` +
  'Label every circle with its scheme, and propose merges only where circles genuinely overlap.';

/**
 * Drops anything the model got wrong before it reaches the client: unknown
 * circle ids, merges of fewer than two circles, a keeper outside its own group,
 * merges that span schemes, and anything touching a system circle.
 *
 * The model is well-behaved on this task, but a merge proposal is one tap away
 * from moving somebody's saved places — so the rules are enforced here rather
 * than trusted to the prompt.
 */
const sanitize = (result, circles) => {
  const byId = new Map(circles.map((c) => [c.id, c]));

  const schemes = (result.schemes || []).filter((s) => byId.has(s.circleId));
  const schemeFor = new Map(schemes.map((s) => [s.circleId, s.scheme]));

  const merges = (result.merges || []).filter((merge) => {
    const ids = [...new Set(merge.circleIds || [])].filter((id) => byId.has(id));
    if (ids.length < 2) return false;
    if (!ids.includes(merge.keepCircleId)) return false;
    // A system circle is app-managed; never fold one into anything.
    if (ids.some((id) => byId.get(id).isSystem || schemeFor.get(id) === 'system')) return false;
    // Cross-scheme merges destroy a distinction the owner deliberately made.
    const distinct = new Set(ids.map((id) => schemeFor.get(id)).filter(Boolean));
    if (distinct.size > 1) return false;
    if (distinct.has('trip')) return false;
    merge.circleIds = ids;
    return true;
  });

  return { schemes, merges };
};

/**
 * Asks the model to label schemes and propose merges.
 * Returns `null` when the feature is off, so callers can fall back silently.
 */
const advise = async (circles) => {
  if (!isEnabled()) return null;
  if (!Array.isArray(circles) || circles.length === 0) return { schemes: [], merges: [] };

  // Bound the request. Someone with hundreds of circles is a different problem
  // than the one this solves, and an unbounded prompt is an unbounded bill.
  const subset = circles.slice(0, MAX_CIRCLES);

  const response = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01'
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 8000,
      system: SYSTEM_PROMPT,
      output_config: {
        effort: 'medium',
        format: { type: 'json_schema', schema: RESPONSE_SCHEMA }
      },
      messages: [{ role: 'user', content: buildPrompt(subset) }]
    })
  });

  if (!response.ok) {
    const detail = await response.text().catch(() => '');
    throw new Error(`Circle advisor request failed (${response.status}): ${detail.slice(0, 300)}`);
  }

  const payload = await response.json();

  // Safety classifiers can decline with a 200; content is empty or partial.
  if (payload.stop_reason === 'refusal') {
    throw new Error('Circle advisor request was declined by safety classifiers');
  }

  const text = (payload.content || []).find((block) => block.type === 'text')?.text;
  if (!text) throw new Error('Circle advisor returned no text content');

  const parsed = JSON.parse(text);
  return {
    ...sanitize(parsed, subset),
    usage: payload.usage
  };
};

module.exports = { advise, buildPrompt, sanitize, isEnabled, SCHEMES, MAX_CIRCLES };
