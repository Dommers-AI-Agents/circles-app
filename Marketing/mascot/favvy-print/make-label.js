// Favvy's QR label (Wes, 2026-11-20): a 1.5 in (38 mm) round sticker that goes
// over the NFC sticker in the figure's recess. Black QR on white (scans well),
// "TAP OR SCAN" under it, FavCircles pink ring. Writes:
//   <out>/label.svg   one label, exact size (for Sticker Mule: 1.5 in circle)
//   <out>/label.png   the same at 1200 px
//   <out>/sheet.pdf   Avery 8293 / Presta 94506 (1.5 in round, 20 per Letter
//                     sheet, 4 x 5 on a 2 in pitch). Print at Actual size.
// usage: node make-label.js <url> <outDir>
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const QRCode = require(path.join(__dirname, '../../../backend/node_modules/qrcode'));

const [url, outDir] = process.argv.slice(2);
if (!url || !outDir) { console.error('usage: node make-label.js <url> <outDir>'); process.exit(1); }
fs.mkdirSync(outDir, { recursive: true });

const D = 38.1;          // label diameter, mm (1.5 in)
const R = D / 2;
const QR_MM = 21;        // QR side, mm; the white label gives ~3 modules of quiet zone at the corners
const PINK = '#f4567f';
const INK = '#1d1b22';

const qr = QRCode.create(url, { errorCorrectionLevel: 'M' });
const n = qr.modules.size;
const m = QR_MM / n;

/// One label's drawing, centred on (cx, cy), in mm
function label(cx, cy) {
  const x0 = cx - QR_MM / 2;
  const y0 = cy - QR_MM / 2 - 1.8;
  let cells = '';
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (qr.modules.data[r * n + c]) cells += `M${(x0 + c * m).toFixed(3)} ${(y0 + r * m).toFixed(3)}h${m.toFixed(3)}v${m.toFixed(3)}h-${m.toFixed(3)}z`;
    }
  }
  return `<g>
  <circle cx="${cx}" cy="${cy}" r="${R}" fill="#ffffff"/>
  <circle cx="${cx}" cy="${cy}" r="${R - 0.5}" fill="none" stroke="${PINK}" stroke-width="0.8"/>
  <path d="${cells}" fill="${INK}" shape-rendering="crispEdges"/>
  <text x="${cx}" y="${cy + 13.6}" text-anchor="middle" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="800" font-size="2.7" letter-spacing="0.2" fill="${INK}">TAP OR SCAN</text>
</g>`;
}

const single = `<svg xmlns="http://www.w3.org/2000/svg" width="${D}mm" height="${D}mm" viewBox="0 0 ${D} ${D}">${label(R, R)}</svg>\n`;
fs.writeFileSync(path.join(outDir, 'label.svg'), single);
execFileSync('rsvg-convert', ['-w', '1200', '-h', '1200', '-o', path.join(outDir, 'label.png'), path.join(outDir, 'label.svg')]);

// Avery 8293 / Presta 94506: 4 across, 5 down, 2 in pitch, centred on Letter
// (label centres at 1.25/3.25/5.25/7.25 in across, 1.5 to 9.5 in down)
const W = 215.9, H = 279.4, cols = 4, rows = 5, pitch = 50.8;
const left = (W - (cols - 1) * pitch) / 2, top = (H - (rows - 1) * pitch) / 2;
let sheet = '';
for (let r = 0; r < rows; r++) {
  for (let c = 0; c < cols; c++) {
    const cx = left + c * pitch, cy = top + r * pitch;
    sheet += label(cx, cy);
  }
}
const footer = `<text x="${W / 2}" y="${H - 8}" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="2.6" fill="#999">${url.replace(/&/g, '&amp;')} · Avery 8293 or Presta 94506 · print at Actual size (100%, no scaling)</text>`;
fs.writeFileSync(path.join(outDir, 'sheet.svg'),
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}mm" height="${H}mm" viewBox="0 0 ${W} ${H}">${sheet}${footer}</svg>\n`);
execFileSync('rsvg-convert', ['-f', 'pdf', '-o', path.join(outDir, 'sheet.pdf'), path.join(outDir, 'sheet.svg')]);
fs.unlinkSync(path.join(outDir, 'sheet.svg'));
console.log(`Label: ${url} (${n}x${n} QR, ${m.toFixed(2)} mm modules) → ${outDir}`);
