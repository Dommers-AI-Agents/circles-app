// Print-ready PDFs for a venue's two QR codes, in the shapes a store actually
// puts up. Everything is drawn at real size (72 pt = 1 in), so a "3 in" QR
// prints at 3 in on plain paper at 100% — the fix for "the code fills a whole
// letter page".
//
//   kind    'window'   scan-to-save code (free owner tier; no points promise)
//           'register' earn-points-every-visit code (Business tier)
//   format  'sign'     letter portrait sign
//           'tent'     letter sheet folded in half the long way (faces 11 × 4¼ in)
//           'smallTent' 4 × 5½ in two-face tent cut from a letter sheet
//           'card'     4 × 6 in counter card (photo frame / acrylic stand)
//   qr      'small' | 'medium' | 'large' → 2 / 3 / 4 in, clamped to the face
//
// The email flows keep calling the old three names; they map onto this.

const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');
const rewardService = require('./rewardService');
const { ServiceError } = require('../utils/serviceError');

const BRAND = '#3182CE';
const INK = '#1A202C';
const INK_SOFT = '#4A5568';
const GUIDE = '#CBD5E0';
const GUIDE_TEXT = '#A0AEC0';
const IN = 72;

const KINDS = ['window', 'register'];
const FORMATS = ['sign', 'tent', 'smallTent', 'card'];
const QR_INCHES = { small: 2, medium: 3, large: 4 };

// Page / face geometry per format, in points
const GEOMETRY = {
  sign: { page: [8.5 * IN, 11 * IN] },
  tent: { page: [11 * IN, 8.5 * IN], face: [11 * IN, 4.25 * IN] },
  smallTent: { page: [8.5 * IN, 11 * IN], face: [4 * IN, 5.5 * IN] },
  card: { page: [4 * IN, 6 * IN] }
};

// Copy per kind. The window code works the same on the free plan and on
// Business, so it never promises points.
function copyFor(kind, venue) {
  if (kind === 'register') {
    const earnRate = rewardService.effectiveEarnRate(venue);
    return {
      lead: 'Scan to earn points every visit',
      after: `Earn ${earnRate} points per visit`,
      afterSoft: 'Redeem your points for rewards right here',
      foot: 'New here? Get the free app at favcircles.com'
    };
  }
  return {
    lead: 'Love it here? Save us.',
    after: 'Scan with your phone camera',
    afterSoft: 'Save us to your map and share us with friends',
    foot: 'Free app at favcircles.com'
  };
}

function codeFor(kind, venue) {
  const code = kind === 'register' ? venue.registerCode : venue.windowCode;
  if (!code) throw new ServiceError(404, 'NO_CODE', `This store has no ${kind} code yet`);
  return code;
}

// Validates and normalises the options the endpoint and the emails pass in.
function printOptions({ kind = 'window', format = 'sign', qr = 'medium' } = {}) {
  if (!KINDS.includes(kind)) throw new ServiceError(400, 'BAD_KIND', 'kind must be window or register');
  if (!FORMATS.includes(format)) throw new ServiceError(400, 'BAD_FORMAT', 'format must be sign, tent, smallTent or card');
  if (!QR_INCHES[qr]) throw new ServiceError(400, 'BAD_QR_SIZE', 'qr must be small, medium or large');
  return { kind, format, qr, qrInches: QR_INCHES[qr] };
}

const pdfToBuffer = (doc) => new Promise((resolve, reject) => {
  const chunks = [];
  doc.on('data', (c) => chunks.push(c));
  doc.on('end', () => resolve(Buffer.concat(chunks)));
  doc.on('error', reject);
  doc.end();
});

const qrBuffer = (code, sizePx) => QRCode.toBuffer(
  rewardService.stickerUrl(code),
  { width: sizePx, margin: 1, errorCorrectionLevel: 'M' }
);

// Type scales with the face: `s` is 1 on a 4 in wide face, smaller on a
// short one, so headings never crowd the code out. A wide, low face (the
// letter tent's 11 × 4¼ in) puts the words beside the code instead of above it.
function drawFace(doc, { venue, kind, qr, qrPt, W, H, bandPt = 8 }) {
  const copy = copyFor(kind, venue);
  const s = Math.min(Math.max(Math.min(W / (4 * IN), H / (6 * IN)), 0.8), 1.9);
  const pad = 18 * s;
  doc.rect(0, 0, W, bandPt).fill(BRAND);

  if (W / H > 1.6) return drawWideFace(doc, { venue, copy, qr, qrPt, W, H, bandPt, s, pad });

  doc.fillColor(BRAND).font('Helvetica-Bold').fontSize(15 * s)
    .text('FavCircles', 0, bandPt + 16 * s, { width: W, align: 'center' });
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(21 * s)
    .text(venue.venueName, pad, doc.y + 6 * s, { width: W - pad * 2, align: 'center' });
  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(13 * s)
    .text(copy.lead, 0, doc.y + 6 * s, { width: W, align: 'center' });

  // The code at the asked size, never past the face
  const afterBlock = 60 * s;
  const maxQr = Math.min(W - pad * 2, H - doc.y - 12 * s - afterBlock - 30 * s);
  const qrSize = Math.max(Math.min(qrPt, maxQr), IN);
  const qrY = doc.y + 12 * s;
  doc.image(qr, (W - qrSize) / 2, qrY, { width: qrSize, height: qrSize });

  doc.fillColor(INK).font('Helvetica-Bold').fontSize(13 * s)
    .text(copy.after, 0, qrY + qrSize + 12 * s, { width: W, align: 'center' });
  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(11 * s)
    .text(copy.afterSoft, pad, doc.y + 3 * s, { width: W - pad * 2, align: 'center' });
  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(9 * s)
    .text(copy.foot, 0, H - 26 * s, { width: W, align: 'center' });
  return qrSize;
}

// Words on the left, code on the right, both centred on the face's height.
function drawWideFace(doc, { venue, copy, qr, qrPt, W, H, bandPt, s, pad }) {
  const qrSize = Math.max(Math.min(qrPt, H - bandPt - pad * 2 - 16 * s), IN);
  const qrX = W - pad * 2 - qrSize;
  const qrY = bandPt + (H - bandPt - qrSize) / 2 - 4 * s;
  doc.image(qr, qrX, qrY, { width: qrSize, height: qrSize });

  const textW = qrX - pad * 2.5;
  const textX = pad * 1.5;
  // Measure the block first so it sits on the face's centre line
  const lines = [
    ['Helvetica-Bold', 14 * s, BRAND, 'FavCircles', 0],
    ['Helvetica-Bold', 22 * s, INK, venue.venueName, 6 * s],
    ['Helvetica', 13 * s, INK_SOFT, copy.lead, 8 * s],
    ['Helvetica-Bold', 14 * s, INK, copy.after, 14 * s],
    ['Helvetica', 11 * s, INK_SOFT, copy.afterSoft, 3 * s]
  ];
  const total = lines.reduce((sum, [font, size, , text, gap]) =>
    sum + gap + doc.font(font).fontSize(size).heightOfString(text, { width: textW }), 0);
  let y = bandPt + (H - bandPt - total) / 2 - 6 * s;
  for (const [font, size, color, text, gap] of lines) {
    y += gap;
    doc.fillColor(color).font(font).fontSize(size).text(text, textX, y, { width: textW, align: 'center' });
    y = doc.y;
  }
  doc.fillColor(INK_SOFT).font('Helvetica').fontSize(9 * s)
    .text(copy.foot, textX, H - 22 * s, { width: textW, align: 'center' });
  return qrSize;
}

function foldGuide(doc, x1, y, x2, labelW, labelX = 0) {
  doc.moveTo(x1, y).lineTo(x2, y)
    .dash(6, { space: 6 }).strokeColor(GUIDE).lineWidth(0.5).stroke().undash();
  doc.fillColor(GUIDE_TEXT).font('Helvetica').fontSize(7)
    .text('fold here — stands as a tent', labelX, y + 11, { width: labelW, align: 'center' });
}

function cutGuide(doc, x1, y1, x2, y2) {
  doc.moveTo(x1, y1).lineTo(x2, y2)
    .dash(2, { space: 3 }).strokeColor(GUIDE).lineWidth(0.5).stroke().undash();
}

// Two identical faces, the top one drawn upside down so both stand upright
// once the sheet is folded along the line between them.
function drawTent(doc, args, faceW, faceH, originX = 0) {
  doc.save(); doc.translate(originX, faceH); drawFace(doc, { ...args, W: faceW, H: faceH }); doc.restore();
  doc.save(); doc.rotate(180, { origin: [originX + faceW / 2, faceH / 2] });
  doc.translate(originX, 0); drawFace(doc, { ...args, W: faceW, H: faceH }); doc.restore();
  foldGuide(doc, originX, faceH, originX + faceW, faceW, originX);
}

async function renderPDF(venue, rawOptions) {
  const { kind, format, qrInches } = printOptions(rawOptions);
  const code = codeFor(kind, venue);
  const qr = await qrBuffer(code, Math.max(600, Math.round(qrInches * 300)));
  const qrPt = qrInches * IN;
  const geo = GEOMETRY[format];
  const doc = new PDFDocument({ size: geo.page, margin: 0 });
  const args = { venue, kind, qr, qrPt };

  if (format === 'sign') {
    const [W, H] = geo.page;
    drawFace(doc, { ...args, W, H, bandPt: 14 });
    doc.rect(0, H - 14, W, 14).fill(BRAND);
  } else if (format === 'card') {
    const [W, H] = geo.page;
    drawFace(doc, { ...args, W, H });
  } else if (format === 'tent') {
    const [faceW, faceH] = geo.face;
    drawTent(doc, args, faceW, faceH);
  } else { // smallTent: a 4 × 11 in strip centred on the sheet, cut out, fold in the middle
    const [pageW, pageH] = geo.page;
    const [faceW, faceH] = geo.face;
    const x = (pageW - faceW) / 2;
    drawTent(doc, args, faceW, faceH, x);
    cutGuide(doc, x, 0, x, pageH); cutGuide(doc, x + faceW, 0, x + faceW, pageH);
    doc.fillColor(GUIDE_TEXT).font('Helvetica').fontSize(7)
      .text('cut along the dotted lines', x + faceW + 6, pageH / 2 - 4, { width: pageW - x - faceW - 8 });
  }
  return pdfToBuffer(doc);
}

const formatLabel = { sign: 'sign', tent: 'table tent', smallTent: 'small table tent', card: 'counter card 4x6' };
const fileName = (venue, options) => {
  const { kind, format, qr } = printOptions(options);
  const safeName = String(venue.venueName || 'store').replace(/[^\w -]/g, '').trim() || 'store';
  return `${safeName} - ${kind} ${formatLabel[format]} - ${QR_INCHES[qr]}in QR.pdf`;
};

// The email flows' names, unchanged
const windowSignPDF = (venue) => renderPDF(venue, { kind: 'window', format: 'sign', qr: 'large' });
const registerCardPDF = (venue) => renderPDF(venue, { kind: 'register', format: 'card', qr: 'medium' });
const tableTentPDF = (venue) => renderPDF(venue, { kind: 'register', format: 'tent', qr: 'medium' });

module.exports = {
  renderPDF, printOptions, fileName, KINDS, FORMATS, QR_INCHES,
  windowSignPDF, registerCardPDF, tableTentPDF
};
