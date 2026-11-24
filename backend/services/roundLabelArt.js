// Round QR labels with words running round the edge (Wes, 2026-11-24).
//
// The Totem label: a plain white 1½ in circle, "TAP OR SCAN" over the top, the
// code in the middle, the store's name round the bottom; the words in navy, no
// ring (Wes, 2026-11-24: "do the writing in a different color and get rid of
// the red ring"). One drawing, used by the app's
// "Totem QR labels" sheet (printAssetService) and by the Mac scripts
// (Marketing/mascot/favvy-print/make-label.js). The table-sticker mock-ups
// (Marketing/table-sticker/make.js) use arcText from here too.
//
// Everything is in PDF points; MM converts. Nothing here reads the database.
const path = require('path');
const QRCode = require('qrcode');

const MM = 72 / 25.4;

const TOTEM_LABEL = {
  diameter: 38.1 * MM,        // 1½ in, Avery 8293 / Presta 94506
  qr: 19.5 * MM,              // dark modules span this, centred on the label
  // The words live in a band between the code's corners and the cut edge:
  // 15.3 mm to 17.4 mm from the centre (the corners reach 13.8 mm, the cut
  // edge is at 19.05 mm, so a sheet printed 1 mm off still keeps its words).
  bandInner: 15.3 * MM,
  bandOuter: 17.4 * MM,
  font: 'Helvetica-Bold',
  size: 2.9 * MM,             // caps are 2.1 mm tall: the band's depth
  minSize: 2.0 * MM,          // a long name shrinks to this, then is cut short
  spacing: 0.25 * MM,
  top: 'TAP OR SCAN',
  topMaxAngle: 50,            // degrees either side of the top
  nameMaxAngle: 62,           // degrees either side of the bottom
  noName: 'FAVCIRCLES',       // a label that belongs to no store
  words: '#1A365D',           // navy, the Totem's Dark Blue
  ink: '#1d1b22'              // the code stays near-black: it has to scan
};

// The table sticker (Wes, 2026-11-24: "Do the 'Psst, regulars scan this' in the
// cream design"): the same 1½ in circle, cream with a navy ring, "Psst…" over
// the top, the store's window code, "the regulars scan this" round the bottom.
// Proportions from the mock-ups (Marketing/table-sticker/make.js, options A + D)
// with the code a little smaller so the bottom words clear its corners.
const TABLE_STICKER = {
  diameter: 38.1 * MM,
  bleed: 1 * MM,              // cream runs past the cut, so a sheet printed a little off shows no white edge
  qr: 18.5 * MM,
  ringInset: 0.75 * MM,
  ringWidth: 0.6 * MM,
  font: path.join(__dirname, '../assets/fonts/Gelasio-Bold.ttf'),
  top: 'Psst…',
  topRadius: 14.57 * MM,      // baseline; the letters stand outward from it
  topSize: 3.86 * MM,
  topSpacing: 0.075 * MM,
  bottom: 'the regulars scan this',
  bottomRadius: 17.0 * MM,    // baseline; the letters stand inward from it
  bottomSize: 2.8 * MM,
  bottomSpacing: 0.06 * MM,
  cream: '#FFFBF0',
  navy: '#1A365D'
};

const ELLIPSIS = '…';

/** Length of `text` along its baseline, from each glyph's width. */
function arcLength(widths, spacing) {
  if (!widths.length) return 0;
  return widths.reduce((a, b) => a + b, 0) + spacing * (widths.length - 1);
}

/**
 * The largest size (from `size` down to `minSize`) at which `text` fits an arc
 * `maxAngle` degrees either side of centre at `radius`; when even `minSize` is
 * too wide the text is cut short with an ellipsis. `measure(text, size)` gives
 * the glyph widths. Pure: the tests pass their own `measure`.
 */
function fitArcText(text, { measure, radius, maxAngle, size, minSize, spacing = 0 }) {
  const room = 2 * radius * maxAngle * Math.PI / 180;
  const fits = (t, s) => arcLength(measure(t, s), spacing) <= room;
  const clean = String(text || '').replace(/\s+/g, ' ').trim();
  if (!clean) return { text: '', size };
  if (fits(clean, size)) return { text: clean, size };
  // Glyph widths are proportional to size (the gaps are not), so one
  // measurement gives the size that fits
  const widths = measure(clean, size);
  const gaps = spacing * (widths.length - 1);
  const scaled = size * (room - gaps) / arcLength(widths, 0) * 0.995;
  if (scaled >= minSize && fits(clean, scaled)) return { text: clean, size: scaled };
  if (fits(clean, minSize)) return { text: clean, size: minSize };
  const chars = [...clean];
  while (chars.length > 1) {
    chars.pop();
    const kept = chars.join('').trimEnd();
    if (!fits(kept + ELLIPSIS, minSize)) continue;
    // Prefer ending on a whole word when that keeps most of what fits
    const wholeWords = clean[kept.length] === ' ' ? kept : kept.slice(0, kept.lastIndexOf(' ') + 1).trimEnd();
    const text = wholeWords.length >= kept.length * 0.6 ? wholeWords : kept;
    return { text: text + ELLIPSIS, size: minSize };
  }
  return { text: chars.join(''), size: minSize };
}

/** PDFKit's glyph widths for `text` in the font and size given. */
function measureWith(doc, font) {
  return (text, size) => {
    doc.font(font).fontSize(size);
    return [...text].map((ch) => doc.widthOfString(ch));
  };
}

/**
 * Text along a circle, centred at the top (or bottom) of it, reading left to
 * right either way. `r` is the baseline's radius: at the top the letters stand
 * outward from it, at the bottom they stand inward (toward the centre).
 */
function arcText(doc, text, cx, cy, r, { font, size, color, bottom = false, spacing = 0 }) {
  doc.font(font).fontSize(size).fillColor(color);
  const asc = doc._font.ascender / 1000 * size;
  const widths = [...text].map((ch) => doc.widthOfString(ch) + spacing);
  const total = widths.reduce((a, b) => a + b, 0) - spacing;
  let at = -total / 2;
  [...text].forEach((ch, i) => {
    const w = widths[i] - spacing;
    const a = (at + w / 2) / r; // radians from the top (or bottom) centre
    at += widths[i];
    doc.save();
    if (bottom) {
      doc.translate(cx + r * Math.sin(a), cy + r * Math.cos(a)).rotate(-a * 180 / Math.PI);
    } else {
      doc.translate(cx + r * Math.sin(a), cy - r * Math.cos(a)).rotate(a * 180 / Math.PI);
    }
    doc.text(ch, -w / 2, -asc, { lineBreak: false });
    doc.restore();
  });
}

/** A QR code's dark modules only, spanning size × size from (x, y). */
function drawModules(doc, modules, x, y, size, color) {
  const n = modules.size;
  const cell = size / n;
  for (let row = 0; row < n; row++) {
    let col = 0;
    while (col < n) {
      if (!modules.get(row, col)) { col += 1; continue; }
      const start = col;
      while (col < n && modules.get(row, col)) col += 1;
      // A hair of overlap so no white seams show between modules when printed
      doc.rect(x + start * cell, y + row * cell, (col - start) * cell + 0.01, cell + 0.01);
    }
  }
  doc.fill(color);
}

/** What the bottom of a Totem label says for `name`: capitals, sized to fit. */
function totemNameLine(doc, name) {
  const L = TOTEM_LABEL;
  const words = String(name || '').replace(/\s+/g, ' ').trim().toUpperCase() || L.noName;
  return fitArcText(words, {
    measure: measureWith(doc, L.font), radius: L.bandOuter, maxAngle: L.nameMaxAngle,
    size: L.size, minSize: L.minSize, spacing: L.spacing
  });
}

/**
 * One Totem label centred on (cx, cy): white circle, "TAP OR SCAN"
 * round the top, the code for `url`, the store's name round the bottom.
 */
function drawTotemLabel(doc, cx, cy, url, name) {
  const L = TOTEM_LABEL;
  const r = L.diameter / 2;
  doc.save();
  doc.circle(cx, cy, r).fill('#FFFFFF');
  const modules = QRCode.create(url, { errorCorrectionLevel: 'M' }).modules;
  drawModules(doc, modules, cx - L.qr / 2, cy - L.qr / 2, L.qr, L.ink);
  const top = fitArcText(L.top, {
    measure: measureWith(doc, L.font), radius: L.bandInner, maxAngle: L.topMaxAngle,
    size: L.size, minSize: L.minSize, spacing: L.spacing
  });
  arcText(doc, top.text, cx, cy, L.bandInner, { font: L.font, size: top.size, color: L.words, spacing: L.spacing });
  const bottom = totemNameLine(doc, name);
  arcText(doc, bottom.text, cx, cy, L.bandOuter, { font: L.font, size: bottom.size, color: L.words, bottom: true, spacing: L.spacing });
  doc.restore();
  return { modules: modules.size, name: bottom.text, nameSize: bottom.size };
}

/** One table sticker centred on (cx, cy), opening `url` (the store's window code). */
function drawTableSticker(doc, cx, cy, url) {
  const T = TABLE_STICKER;
  const r = T.diameter / 2;
  doc.save();
  doc.circle(cx, cy, r + T.bleed).fill(T.cream);
  doc.circle(cx, cy, r - T.ringInset).lineWidth(T.ringWidth).strokeColor(T.navy).stroke();
  const modules = QRCode.create(url, { errorCorrectionLevel: 'M' }).modules;
  drawModules(doc, modules, cx - T.qr / 2, cy - T.qr / 2, T.qr, T.navy);
  arcText(doc, T.top, cx, cy, T.topRadius, { font: T.font, size: T.topSize, color: T.navy, spacing: T.topSpacing });
  arcText(doc, T.bottom, cx, cy, T.bottomRadius, { font: T.font, size: T.bottomSize, color: T.navy, bottom: true, spacing: T.bottomSpacing });
  doc.restore();
  return { modules: modules.size };
}

module.exports = { MM, TOTEM_LABEL, TABLE_STICKER, drawTableSticker, arcLength, fitArcText, measureWith, arcText, drawModules, totemNameLine, drawTotemLabel };
