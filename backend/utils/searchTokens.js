// backend/utils/searchTokens.js
//
// ONE tokenizer for every indexed text search (venues, people). Documents
// store `searchTokens` = every prefix of every word; a query anchors an
// array-contains on its longest word and checks the rest in memory. Writers
// and readers must split text the same way, which is why this lives in one
// place (the venue and query tokenizers had drifted: neither folded accents,
// so "Café" was stored as c/ca/caf and "cafe" never matched).

const MAX_WORD = 20;

/** Lowercase, accents off ("Café" → "cafe"), apostrophes joined ("Joe's" → "joes"). */
const foldText = (text) => String(text || '')
  .normalize('NFD')
  .replace(/[̀-ͯ]/g, '')
  .toLowerCase()
  .replace(/['’`]/g, '');

/** The words of a text, folded, each capped at MAX_WORD characters. */
const words = (text) => foldText(text)
  .split(/[^a-z0-9]+/)
  .filter(Boolean)
  .map(w => w.slice(0, MAX_WORD));

/**
 * Every prefix of every word across the given texts, de-duplicated. An
 * apostrophe both joins and splits ("Nickyo's" → nickyos… AND nickyo, s),
 * so a query typed either way matches, and so do readers that still split
 * on it (the pre-2026-10-29 tokenizer).
 */
const buildSearchTokens = (...texts) => {
  const tokens = new Set();
  const add = (w) => { for (let i = 1; i <= w.length; i++) tokens.add(w.slice(0, i)); };
  for (const text of texts) {
    for (const w of words(text)) add(w);
    for (const w of words(String(text || '').replace(/['\u2019`]/g, ' '))) add(w);
  }
  return [...tokens];
};

/** A query's words (what each stored token list must contain). */
const queryTokens = (query) => [...new Set(words(query))];

/** The word to anchor the indexed array-contains on: the longest (most selective). */
const anchorToken = (tokens) => tokens.reduce((a, b) => (b.length > a.length ? b : a), '');

/** Does a stored token list contain every query token? */
const hasAllTokens = (stored, tokens) => {
  const set = new Set(stored || []);
  return tokens.every(t => set.has(t));
};

module.exports = { foldText, words, buildSearchTokens, queryTokens, anchorToken, hasAllTokens, MAX_WORD };
