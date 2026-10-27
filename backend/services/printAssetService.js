// Print-ready PDFs for a venue's QR codes: a letter-size window sign (the
// store's own scan-to-save code), and for the register a 4x6 counter card and
// a letter-size fold-in-half table tent where customers scan to earn points
// each visit. All print at home on plain paper.

const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');
const rewardService = require('./rewardService');

const BRAND = '#3182CE';
const INK = '#1A202C';
const INK_SOFT = '#4A5568';

const pdfToBuffer = (doc) => new Promise((resolve, reject) => {
  const chunks = [];
  doc.on('data', (c) => chunks.push(c));
  doc.on('end', () => resolve(Buffer.concat(chunks)));
  doc.on('error', reject);
  doc.end();
});

const codeQRBuffer = (code, sizePx) => QRCode.toBuffer(
  rewardService.stickerUrl(code),
  { width: sizePx, margin: 1, errorCorrectionLevel: 'M' }
);
const registerQRBuffer = (venue, sizePx) => codeQRBuffer(venue.registerCode, sizePx);

// Draw one card face into a width x height box whose top-left is at (0,0)
// of the current transform. Shared by the counter card and each tent panel.
function drawFace(doc, venue, qrBuffer, W, H) {
  const earnRate = rewardService.effectiveEarnRate(venue);

  // Brand band
  doc.rect(0, 0, W, 8).fill(BRAND);

  doc.fillColor(BRAND).font('Helvetica-Bold').fontSize(15)
    .text('FavCircles', 0, 26, { width: W, align: 'center' });

  doc.fillColor(INK).font('Helvetica-Bold').fontSize(21)
    .text(venue.venueName, 18, 50, { width: W - 36, align: 'center' });

  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(13)
    .text('Scan to earn points every visit', 0, doc.y + 6, { width: W, align: 'center' });

  // QR centered, sized for counter distance
  const qrSize = Math.min(W - 110, H - 210);
  const qrX = (W - qrSize) / 2;
  const qrY = doc.y + 12;
  doc.image(qrBuffer, qrX, qrY, { width: qrSize, height: qrSize });

  doc.fillColor(INK).font('Helvetica-Bold').fontSize(13)
    .text(`Earn ${earnRate} points per visit`, 0, qrY + qrSize + 14, { width: W, align: 'center' });
  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(11)
    .text('Redeem your points for rewards right here', 0, doc.y + 3, { width: W, align: 'center' });

  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(9)
    .text('New here? Get the free app at favcircles.com', 0, H - 26, { width: W, align: 'center' });
}

// 4x6in portrait counter card (fits a standard photo frame / acrylic stand)
async function registerCardPDF(venue) {
  const W = 288; // 4in
  const H = 432; // 6in
  const qr = await registerQRBuffer(venue, 600);
  const doc = new PDFDocument({ size: [W, H], margin: 0 });
  drawFace(doc, venue, qr, W, H);
  return pdfToBuffer(doc);
}

// Letter landscape, fold along the horizontal center: the top half is drawn
// rotated 180° so both faces stand upright when the sheet is tented.
async function tableTentPDF(venue) {
  const W = 792; // 11in
  const H = 612; // 8.5in
  const faceW = W;
  const faceH = H / 2;
  const qr = await registerQRBuffer(venue, 600);
  const doc = new PDFDocument({ size: [W, H], layout: 'portrait', margin: 0 });

  // Bottom face (upright)
  doc.save();
  doc.translate(0, faceH);
  drawFace(doc, venue, qr, faceW, faceH);
  doc.restore();

  // Top face (rotated 180° around the sheet's center point of the top half)
  doc.save();
  doc.rotate(180, { origin: [faceW / 2, faceH / 2] });
  drawFace(doc, venue, qr, faceW, faceH);
  doc.restore();

  // Fold guide (caption sits below the brand band, not on it)
  doc.moveTo(0, faceH).lineTo(W, faceH)
    .dash(6, { space: 6 }).strokeColor('#CBD5E0').lineWidth(0.5).stroke().undash();
  doc.fillColor('#A0AEC0').font('Helvetica').fontSize(7)
    .text('fold here — stands as a tent', 0, faceH + 11, { width: W, align: 'center' });

  return pdfToBuffer(doc);
}

// Letter portrait sign for the front window: the same scan-to-save code the
// app's Window QR screen shows. No points promise — the sign works the same
// on the free plan and on Business.
async function windowSignPDF(venue) {
  const W = 612; // 8.5in
  const H = 792; // 11in
  const qr = await codeQRBuffer(venue.windowCode, 1200);
  const doc = new PDFDocument({ size: [W, H], margin: 0 });

  doc.rect(0, 0, W, 14).fill(BRAND);
  doc.fillColor(BRAND).font('Helvetica-Bold').fontSize(26)
    .text('FavCircles', 0, 56, { width: W, align: 'center' });
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(40)
    .text(venue.venueName, 48, 100, { width: W - 96, align: 'center' });
  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(22)
    .text('Love it here? Save us.', 0, doc.y + 10, { width: W, align: 'center' });

  const qrSize = 340;
  const qrY = doc.y + 36;
  doc.image(qr, (W - qrSize) / 2, qrY, { width: qrSize, height: qrSize });

  doc.fillColor(INK).font('Helvetica-Bold').fontSize(20)
    .text('Scan with your phone camera', 0, qrY + qrSize + 26, { width: W, align: 'center' });
  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(15)
    .text('Save us to your map and share us with friends', 0, doc.y + 6, { width: W, align: 'center' });

  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(11)
    .text('Free app at favcircles.com', 0, H - 44, { width: W, align: 'center' });
  doc.rect(0, H - 14, W, 14).fill(BRAND);
  return pdfToBuffer(doc);
}

module.exports = { windowSignPDF, registerCardPDF, tableTentPDF };
