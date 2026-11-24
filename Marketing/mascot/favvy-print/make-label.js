#!/usr/bin/env node
// The round QR label that goes over the NFC sticker on a Totem's base (or in a
// Favvy figure's recess): "TAP OR SCAN" round the top, the code, the store's
// name round the bottom, FavCircles pink ring (Wes, 2026-11-24). The drawing is
// backend/services/roundLabelArt.js, the same one the app's "Totem QR labels"
// sheet prints. Writes:
//   <out>/label.pdf   one label, exact size (for Sticker Mule: 1.5 in circle)
//   <out>/label.png   the same at 1200 px
//   <out>/sheet.pdf   Avery 8293 / Presta 94506 (1.5 in round, 20 per Letter
//                     sheet): print at 100% / Actual size
// usage: node make-label.js <url> <outDir> ["Store Name"]
//   Without a name the bottom of the label says FAVCIRCLES.
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const B = path.join(__dirname, '../../../backend');
const PDFDocument = require(B + '/node_modules/pdfkit');
const { TOTEM_LABEL, drawTotemLabel } = require(B + '/services/roundLabelArt');

const [url, outDir, name = ''] = process.argv.slice(2);
if (!url || !outDir) { console.error('usage: node make-label.js <url> <outDir> ["Store Name"]'); process.exit(1); }
fs.mkdirSync(outDir, { recursive: true });

const IN = 72;
const D = TOTEM_LABEL.diameter;
const save = (doc, file) => new Promise((resolve) => {
  const out = fs.createWriteStream(path.join(outDir, file));
  doc.pipe(out); out.on('finish', resolve); doc.end();
});

(async () => {
  const one = new PDFDocument({ size: [D, D], margin: 0 });
  const drawn = drawTotemLabel(one, D / 2, D / 2, url, name);
  await save(one, 'label.pdf');
  execFileSync('sips', ['-s', 'format', 'png', '-Z', '1200', path.join(outDir, 'label.pdf'), '--out', path.join(outDir, 'label.png')], { stdio: 'ignore' });

  // 4 across, 5 down, 2 in pitch, centred on Letter
  // (label centres at 1.25/3.25/5.25/7.25 in across, 1.5 to 9.5 in down)
  const sheet = new PDFDocument({ size: 'LETTER', margin: 0 });
  for (let row = 0; row < 5; row++) {
    for (let col = 0; col < 4; col++) drawTotemLabel(sheet, (1.25 + col * 2) * IN, (1.5 + row * 2) * IN, url, name);
  }
  sheet.font('Helvetica').fontSize(7).fillColor('#999999')
    .text(`${url} · Avery 8293 or Presta 94506 · print at Actual size (100%, no scaling)`, 0, 11 * IN - 26, { width: 8.5 * IN, align: 'center', lineBreak: false });
  await save(sheet, 'sheet.pdf');
  const dot = (TOTEM_LABEL.qr / drawn.modules / IN * 25.4).toFixed(2);
  console.log(`Label: ${url} (${drawn.modules}x${drawn.modules} QR, ${dot} mm modules), bottom "${drawn.name}" → ${outDir}`);
})();
