// backend/services/quoteCard.js — the picture in a shared quote's link card
// (Wes, 2026-10-18: the bubble should carry everything the quote shows in
// the app — the line, who said it, where it's from, its topics). Drawn like
// the in-app quote: black, a serif line, the author in purple, the source in
// grey, topic pills. 1200×630, the size Messages lays out as a link card.
// The server image needs fonts in the container (Dockerfile: font-dejavu).
const sharp = require('sharp');

const WIDTH = 1200;
const HEIGHT = 630;
const PAD_X = 80;
const PURPLE = '#7C6BD6';
const SERIF = "'DejaVu Serif', 'New York', Georgia, serif";
const SANS = "'DejaVu Sans', -apple-system, Helvetica, Arial, sans-serif";

const esc = (s) => String(s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

/** Greedy word wrap by an average glyph width (no font metrics on the server). Pure. */
function wrap(text, fontSize, maxWidth, charWidth = 0.55) {
  const perLine = Math.max(8, Math.floor(maxWidth / (fontSize * charWidth)));
  const words = String(text).split(/\s+/).filter(Boolean);
  const lines = [];
  let line = '';
  for (const word of words) {
    const next = line ? `${line} ${word}` : word;
    if (next.length > perLine && line) {
      lines.push(line);
      line = word;
    } else {
      line = next;
    }
  }
  if (line) lines.push(line);
  return lines;
}

/** The quote's size: as big as fits in five lines. Pure. */
function quoteLayout(text) {
  const quoted = `“${String(text).trim()}”`;
  for (const size of [64, 56, 48, 42, 36, 32]) {
    const lines = wrap(quoted, size, WIDTH - PAD_X * 2, 0.6);
    if (lines.length <= (size >= 48 ? 4 : 5)) return { size, lines };
  }
  const lines = wrap(quoted, 30, WIDTH - PAD_X * 2, 0.6).slice(0, 6);
  if (lines.length === 6) lines[5] = `${lines[5].replace(/[\s.,;:]*$/, '')}…`;
  return { size: 30, lines };
}

/**
 * The card as SVG. `quote` = { text, author, context, categories };
 * `labels` maps a category id to its name ("wisdom" → "Wisdom"). Pure.
 */
function quoteCardSvg(quote, labels = {}) {
  const { size, lines } = quoteLayout(quote.text || '');
  const lineHeight = Math.round(size * 1.22);
  const author = quote.author ? String(quote.author).trim() : '';
  const contextLines = quote.context ? wrap(String(quote.context).trim(), 26, WIDTH - PAD_X * 2, 0.52).slice(0, 2) : [];
  const tags = (quote.categories || []).map((c) => labels[c] || null).filter(Boolean).slice(0, 4);

  // Stack heights, then centre the block a little above the middle
  const blocks = [lines.length * lineHeight];
  if (author) blocks.push(28 + 36);
  if (contextLines.length) blocks.push(18 + contextLines.length * 34);
  if (tags.length) blocks.push(26 + 46);
  const total = blocks.reduce((a, b) => a + b, 0);
  let y = Math.max(56, Math.round((HEIGHT - total) / 2) - 10);

  const parts = [];
  lines.forEach((line, i) => {
    parts.push(`<text x="${PAD_X}" y="${y + size + i * lineHeight - Math.round(size * 0.2)}" font-family="${SERIF}" font-weight="bold" font-size="${size}" fill="#ffffff">${esc(line)}</text>`);
  });
  y += lines.length * lineHeight;
  if (author) {
    y += 28;
    parts.push(`<text x="${PAD_X}" y="${y + 30}" font-family="${SANS}" font-size="32" fill="${PURPLE}">— ${esc(author)}</text>`);
    y += 36;
  }
  if (contextLines.length) {
    y += 18;
    contextLines.forEach((line, i) => {
      parts.push(`<text x="${PAD_X}" y="${y + 26 + i * 34}" font-family="${SANS}" font-size="26" fill="#8e8e93">${esc(line)}</text>`);
    });
    y += contextLines.length * 34;
  }
  if (tags.length) {
    y += 26;
    let x = PAD_X;
    for (const tag of tags) {
      const w = Math.round(tag.length * 24 * 0.6 + 44);
      parts.push(`<rect x="${x}" y="${y}" width="${w}" height="46" rx="23" fill="#1E1A3A"/>`);
      parts.push(`<text x="${x + w / 2}" y="${y + 31}" text-anchor="middle" font-family="${SANS}" font-size="24" fill="${PURPLE}">${esc(tag)}</text>`);
      x += w + 14;
    }
  }
  parts.push(`<text x="${WIDTH - PAD_X}" y="${HEIGHT - 36}" text-anchor="end" font-family="${SANS}" font-weight="bold" font-size="24" fill="#5a5a60">FavCircles</text>`);

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${WIDTH}" height="${HEIGHT}" viewBox="0 0 ${WIDTH} ${HEIGHT}">
<rect width="${WIDTH}" height="${HEIGHT}" fill="#000000"/>
${parts.join('\n')}
</svg>`;
}

const cache = new Map(); // id@updatedAt → PNG
const CACHE_MAX = 300;

/** The card PNG for a quote doc (cached per id and edit). */
async function renderQuoteCard(id, quote, labels) {
  const key = `${id}@${quote.updatedAt || ''}`;
  if (cache.has(key)) return cache.get(key);
  const png = await sharp(Buffer.from(quoteCardSvg(quote, labels))).png({ compressionLevel: 9 }).toBuffer();
  if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value);
  cache.set(key, png);
  return png;
}

module.exports = { WIDTH, HEIGHT, wrap, quoteLayout, quoteCardSvg, renderQuoteCard };
