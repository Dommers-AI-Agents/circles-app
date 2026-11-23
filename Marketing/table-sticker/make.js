// Table sticker mock-ups (Wes, 2026-11-23): a half-dollar-size round sticker
// with a store's Window code and a few words. usage: node make.js <url> <store name> <outDir>
const B = require('path').join(__dirname, '../../backend');
const PDFDocument = require(B + '/node_modules/pdfkit');
const QRCode = require(B + '/node_modules/qrcode');
const fs = require('fs');
const path = require('path');
const [url, storeName, outDir] = process.argv.slice(2);

const IN = 72, MM = IN / 25.4;
const SERIF = B + '/assets/fonts/Gelasio-Bold.ttf';
const NAVY = '#1A365D', CREAM = '#FFFBF0', PINK = '#f4567f', INK = '#1d1b22', YELLOW = '#F6C945';
const HALF_DOLLAR = 30.61 * MM;

const modules = QRCode.create(url, { errorCorrectionLevel: 'M' }).modules;

/** Dark modules only, spanning size × size from (x, y). */
function drawQR(doc, x, y, size, dark) {
  const n = modules.size, cell = size / n;
  for (let row = 0; row < n; row++) {
    let col = 0;
    while (col < n) {
      if (!modules.get(row, col)) { col += 1; continue; }
      const start = col;
      while (col < n && modules.get(row, col)) col += 1;
      doc.rect(x + start * cell, y + row * cell, (col - start) * cell + 0.01, cell + 0.01);
    }
  }
  doc.fill(dark);
}

/** Text along a circle, centred at the top (or bottom) of it. `r` is the baseline's radius. */
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

/** A heart `w` wide centred on (cx, cy). */
function heart(doc, cx, cy, w, color) {
  const s = w / 24;
  doc.save().translate(cx - 12 * s, cy - 11 * s).scale(s);
  doc.path('M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z').fill(color);
  doc.restore();
}

const VARIANTS = [
  { key: 'A', name: 'Cream', words: 'Love it here?', bg: CREAM, ring: NAVY, text: NAVY, qr: NAVY, heart: PINK },
  { key: 'B', name: 'Night', words: 'Love it here?', bg: NAVY, text: CREAM, qr: INK, tile: '#FFFFFF', heart: PINK },
  { key: 'C', name: 'Pink ring', words: 'Found a favorite?', bg: '#FFFFFF', ring: PINK, text: INK, qr: INK, heart: PINK },
  { key: 'D', name: 'Psst', words: 'Psst…', under: 'the regulars scan this', bg: CREAM, ring: YELLOW, text: NAVY, qr: NAVY }
];

/** One sticker of `diameter` centred on (cx, cy). Everything scales from the diameter. */
function drawSticker(doc, cx, cy, diameter, v) {
  const r = diameter / 2;
  const u = diameter / HALF_DOLLAR * MM; // 1 mm on the half-dollar version
  doc.save();
  doc.circle(cx, cy, r).fill(v.bg);
  if (v.ring) doc.circle(cx, cy, r - 0.55 * u).lineWidth(0.5 * u).strokeColor(v.ring).stroke();
  // The code: 16 mm of dots on the half dollar (0.55 mm each), a touch below centre
  const q = (v.tile ? 15.4 : 16) * u;
  const qy = cy + (v.under ? 0 : 1.1 * u);
  if (v.tile) {
    const pad = 1.3 * u; // more than two modules of white round the dots
    doc.roundedRect(cx - q / 2 - pad, qy - q / 2 - pad, q + pad * 2, q + pad * 2, 1.1 * u).fill(v.tile);
  }
  drawQR(doc, cx - q / 2, qy - q / 2, q, v.qr);
  const size = (v.words.length > 14 ? 2.55 : 3.1) * u;
  arcText(doc, v.words, cx, cy, r - (v.tile ? 3.5 : 3.6) * u, { font: SERIF, size, color: v.text, spacing: 0.06 * u });
  if (v.under) {
    arcText(doc, v.under, cx, cy, r - 1.55 * u, { font: SERIF, size: 2.25 * u, color: v.text, bottom: true, spacing: 0.05 * u });
  } else {
    heart(doc, cx, cy + r - (v.tile ? 2.35 : 2.55) * u, 2.9 * u, v.heart);
  }
  doc.restore();
}

const save = (doc, file) => new Promise((resolve) => {
  const out = fs.createWriteStream(path.join(outDir, file));
  doc.pipe(out); out.on('finish', resolve); doc.end();
});
const label = (doc, text, x, y, w, size = 9, color = '#4A5568', font = 'Helvetica') =>
  doc.font(font).fontSize(size).fillColor(color).text(text, x, y, { width: w, align: 'center', lineBreak: false });

(async () => {
  fs.mkdirSync(outDir, { recursive: true });

  // 1. The options, enlarged, then at the two sizes on a table-coloured strip
  const W = 7.2 * IN, H = 10.3 * IN;
  const show = new PDFDocument({ size: [W, H], margin: 0 });
  show.rect(0, 0, W, H).fill('#F4F1EC');
  label(show, 'Table sticker options', 0, 0.3 * IN, W, 17, INK, 'Helvetica-Bold');
  label(show, `Shown with ${storeName}'s Window code · enlarged about 2.4×`, 0, 0.62 * IN, W, 9.5);
  const big = 2.9 * IN;
  VARIANTS.forEach((v, i) => {
    const cx = W / 4 + (i % 2) * W / 2, cy = 2.55 * IN + Math.floor(i / 2) * 3.55 * IN;
    show.circle(cx + 2, cy + 3, big / 2).fill('#DDD6CB');
    drawSticker(show, cx, cy, big, v);
    label(show, `${v.key} · ${v.name}`, cx - big / 2, cy + big / 2 + 0.14 * IN, big, 11, INK, 'Helvetica-Bold');
  });
  const stripY = 8.05 * IN, stripH = 2.25 * IN;
  show.rect(0, stripY, W, stripH).fill('#5B4636');
  label(show, 'Next to a half dollar (print the PDF at 100% for true size)', 0, stripY + 0.12 * IN, W, 9, '#E8DFD3');
  const xs = [0.75, 2.2, 3.65, 5.1, 6.5].map((x) => x * IN);
  show.circle(xs[0], stripY + 1.15 * IN, HALF_DOLLAR / 2).fill('#B9BDC2');
  label(show, '50¢', xs[0] - 30, stripY + 1.15 * IN - 5, 60, 10, '#6B7076', 'Helvetica-Bold');
  VARIANTS.forEach((v, i) => drawSticker(show, xs[i + 1], stripY + 1.15 * IN, HALF_DOLLAR, v));
  label(show, 'half dollar', xs[0] - 50, stripY + 1.85 * IN, 100, 8, '#E8DFD3');
  VARIANTS.forEach((v, i) => label(show, v.key, xs[i + 1] - 50, stripY + 1.85 * IN, 100, 8, '#E8DFD3'));
  await save(show, 'options.pdf');

  // 2. A test print on plain paper: every option at half-dollar size and at 1½ in
  const test = new PDFDocument({ size: 'LETTER', margin: 0 });
  label(test, `Table sticker test print · ${storeName} · print at 100% / Actual size, cut out, set on a table and scan from your seat`,
    0, 0.45 * IN, 8.5 * IN, 8.5);
  const cut = (cx, cy, d) => test.circle(cx, cy, d / 2 + 0.6).lineWidth(0.3).dash(2, { space: 2 }).strokeColor('#A0AEC0').stroke().undash();
  [[HALF_DOLLAR, 'Half-dollar size (1.2 in / 30.6 mm)', 1.75], [1.5 * IN, '1½ in (38 mm), the Totem label size', 5.35]].forEach(([d, title, top]) => {
    label(test, title, 0, (top - 0.95) * IN, 8.5 * IN, 11, INK, 'Helvetica-Bold');
    VARIANTS.forEach((v, i) => {
      const cx = (1.3 + i * 1.97) * IN;
      for (let row = 0; row < 2; row++) {
        const cy = (top + row * 1.75) * IN;
        cut(cx, cy, d);
        drawSticker(test, cx, cy, d, v);
      }
      label(test, `${v.key} · ${v.name}`, cx - IN, (top + 2.62) * IN, 2 * IN, 8);
    });
  });
  cut(4.25 * IN, 9.75 * IN, HALF_DOLLAR);
  label(test, 'a half dollar', 4.25 * IN - IN, 9.75 * IN - 4, 2 * IN, 8);
  label(test, url, 0, 10.55 * IN, 8.5 * IN, 7, '#A0AEC0');
  await save(test, 'test-print.pdf');

  const n = modules.size;
  console.log(`${url}: ${n}×${n} code; dots ${(16 / n).toFixed(2)} mm on the half dollar, ${(16 * 38.1 / 30.61 / n).toFixed(2)} mm at 1½ in`);
})();
