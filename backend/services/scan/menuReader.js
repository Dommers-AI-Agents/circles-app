// backend/services/scan/menuReader.js — photos of a menu → a draft full
// menu: sections, and every item's name, price and description. Claude
// Haiku reads it (Clairic returns flat fields, not item records). The
// owner checks the draft in the menu editor before anything is published.
const { ServiceError } = require('../../utils/serviceError');

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = process.env.SCAN_MENU_MODEL || 'claude-haiku-4-5';
const MAX_OUTPUT_TOKENS = 16000;   // a long menu is ~400 items
const TIMEOUT_MS = 90000;

const SYSTEM = `You read photos of a business's menu (food, drinks, services, products or price list) and copy it exactly into the menu tool.
- Keep the menu's own sections, in order, and its own item names and descriptions. Don't invent, translate or embellish anything.
- price: copy it as printed ("12", "$12.50", "8 / 14", "MP", "Market price"). Leave it empty when there's none.
- Put add-ons and sizes in the item's description unless the menu lists them as items.
- tags: only dietary or style marks the menu shows (vegetarian, vegan, gluten-free, spicy, new). Leave empty otherwise.
- unsure: true when the photo is blurry, cut off, or you had to guess at that item.
- Several photos are pages of the same menu: continue sections across them and don't repeat items.
- If the photos aren't a menu or price list, return no sections and say so in notes.`;

const TOOL = {
  name: 'menu',
  description: 'The menu exactly as shown in the photos.',
  input_schema: {
    type: 'object',
    properties: {
      sections: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string', description: 'Section heading as printed, e.g. "Starters". Use "Menu" if there are no headings.' },
            items: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string' },
                  price: { type: 'string' },
                  description: { type: 'string' },
                  tags: { type: 'array', items: { type: 'string' } },
                  unsure: { type: 'boolean' }
                },
                required: ['name']
              }
            }
          },
          required: ['name', 'items']
        }
      },
      notes: { type: 'string', description: 'Anything the owner should know, e.g. a page that was cut off.' }
    },
    required: ['sections']
  }
};

const isConfigured = () => !!process.env.ANTHROPIC_API_KEY;

/** The model's tool input → a draft menu: trimmed, limits applied, ids. Pure. */
function toDraft(input, { now = Date.now() } = {}) {
  const { MAX_MENU_SECTIONS, MAX_MENU_ITEMS } = require('../venueStorefront');
  const clean = (v, max) => String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max);
  let itemCount = 0;
  const sections = [];
  for (const [si, s] of (Array.isArray(input && input.sections) ? input.sections : []).entries()) {
    if (sections.length >= MAX_MENU_SECTIONS) break;
    const items = [];
    for (const [ii, it] of (Array.isArray(s && s.items) ? s.items : []).entries()) {
      if (itemCount >= MAX_MENU_ITEMS) break;
      const name = clean(it && it.name, 80);
      if (!name) continue;
      items.push({
        id: `i_${now.toString(36)}_${si}_${ii}`,
        name,
        price: clean(it.price, 20) || null,
        description: clean(it.description, 300) || null,
        tags: (Array.isArray(it.tags) ? it.tags : []).map((t) => clean(t, 24)).filter(Boolean).slice(0, 3),
        unsure: it.unsure === true
      });
      itemCount += 1;
    }
    if (items.length) sections.push({ id: `s_${now.toString(36)}_${si}`, name: clean(s.name, 60) || 'Menu', items });
  }
  return { sections, notes: clean(input && input.notes, 300) || null, itemCount };
}

async function read(images) {
  if (!isConfigured()) throw new ServiceError(503, 'scan_unavailable', 'Menu scanning isn’t available right now. You can add items by hand.');
  const content = [
    ...images.map((img) => ({ type: 'image', source: { type: 'base64', media_type: img.mediaType, data: img.base64 } })),
    { type: 'text', text: images.length > 1 ? `These ${images.length} photos are pages of one menu. Copy it into the menu tool.` : 'Copy this menu into the menu tool.' }
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
        tools: [TOOL], tool_choice: { type: 'tool', name: 'menu' },
        messages: [{ role: 'user', content }]
      }),
      signal: controller.signal
    });
  } catch (e) {
    throw new ServiceError(503, 'scan_unavailable', 'Menu scanning took too long. Try fewer pages at once.');
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    console.error('Menu scan failed:', res.status, (await res.text().catch(() => '')).slice(0, 300));
    throw new ServiceError(503, 'scan_unavailable', 'Menu scanning isn’t available right now. You can add items by hand.');
  }
  const data = await res.json();
  const tool = (data.content || []).find((c) => c.type === 'tool_use');
  const draft = toDraft(tool && tool.input);
  return {
    draft,
    usage: { engine: 'claude', model: MODEL, inputTokens: (data.usage && data.usage.input_tokens) || 0, outputTokens: (data.usage && data.usage.output_tokens) || 0, truncated: data.stop_reason === 'max_tokens' }
  };
}

module.exports = { MODEL, SYSTEM, TOOL, isConfigured, toDraft, read };
