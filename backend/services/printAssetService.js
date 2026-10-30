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

const path = require('path');
const rewardProgress = require('./rewardProgress');
const { coverJPEG } = require('./storeCoverPhoto');

// The FavCircles palette (the App Clip card's): navy and blue, the yellow
// call-to-action pill, warm white
const BRAND = '#3182CE';
const NAVY = '#1A365D';
const YELLOW = '#F6C945';
const GREEN = '#38A169';
const CREAM = '#FFFBF0';
const INK = '#1A202C';
const INK_SOFT = '#4A5568';
const GUIDE = '#CBD5E0';
const GUIDE_TEXT = '#A0AEC0';
const IN = 72;
const APP_ICON = path.join(__dirname, '..', 'assets', 'brand', 'app-icon-256.png');

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

// Copy per kind (Wes, 2026-10-30: signs owners love to put out and customers
// find attractive). The window code never promises points; the register code
// names the store's first reward when it has one.
function copyFor(kind, venue) {
  if (kind === 'register') {
    const earnRate = rewardService.effectiveEarnRate(venue);
    const first = rewardProgress.firstReward(venue.offers);
    return {
      pill: `Earn ${earnRate} points every visit`,
      scan: 'Scan at the register',
      reward: first ? `${first.pointsCost} points = ${first.title}` : 'Collect points, redeem them right here',
      steps: null,
      foot: 'Free to join · favcircles.com'
    };
  }
  return {
    pill: 'Love it here? Save us!',
    scan: 'Point your phone camera here',
    reward: null,
    steps: ['Scan', 'Save us', 'Share us'],
    foot: 'Your map of favorite places · favcircles.com'
  };
}

function codeFor(kind, venue) {
  const code = kind === 'register' ? venue.registerCode : venue.windowCode;
  if (!code) throw new ServiceError(404, 'NO_CODE', `This store has no ${kind} code yet`);
  return code;
}

// Validates and normalises the options the endpoint and the emails pass in.
// Defaults: the small table tent with a 2 in code (Wes, 2026-10-30)
function printOptions({ kind = 'window', format = 'smallTent', qr = 'small' } = {}) {
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

// --- drawing helpers ------------------------------------------------------

/** The largest font size (≤ max, ≥ min) at which `text` fits `maxLines` lines of `width`. */
function fitSize(doc, text, font, max, min, width, maxLines) {
  let size = max;
  for (; size > min; size -= 0.5) {
    const h = doc.font(font).fontSize(size).heightOfString(text, { width });
    if (h <= size * 1.25 * maxLines) break;
  }
  return size;
}

/** The hero: the store's photo under a dark fade (or the brand gradient with
 *  soft circles), the FavCircles mark, and the store's name. */
function drawHero(doc, { venue, cover, x, y, w, h, s }) {
  doc.save();
  doc.rect(x, y, w, h).clip();
  if (cover) {
    doc.image(cover, x, y, { cover: [w, h], align: 'center', valign: 'center' });
    const fade = doc.linearGradient(x, y, x, y + h);
    fade.stop(0, NAVY, 0.35).stop(0.45, NAVY, 0.05).stop(1, NAVY, 0.88);
    doc.rect(x, y, w, h).fill(fade);
  } else {
    const grad = doc.linearGradient(x, y, x + w, y + h);
    grad.stop(0, NAVY).stop(1, BRAND);
    doc.rect(x, y, w, h).fill(grad);
    doc.fillOpacity(0.09).fillColor('#FFFFFF');
    doc.circle(x + w * 0.88, y + h * 0.18, h * 0.55).fill();
    doc.circle(x + w * 0.08, y + h * 1.05, h * 0.5).fill();
    doc.fillOpacity(1);
  }
  doc.restore();

  // FavCircles mark, top left
  const pad = 14 * s;
  const icon = 20 * s;
  doc.save();
  doc.roundedRect(x + pad, y + pad, icon, icon, icon * 0.24).clip();
  doc.image(APP_ICON, x + pad, y + pad, { width: icon, height: icon });
  doc.restore();
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(11 * s)
    .text('FavCircles', x + pad + icon + 6 * s, y + pad + (icon - 11 * s) / 2 + 1, { lineBreak: false });

  // The store's name, bottom left, up to two lines, never up into the mark
  const nameW = w - pad * 2;
  const room = h - (pad + icon + 10 * s) - pad * 1.6;
  let size = fitSize(doc, venue.venueName, 'Helvetica-Bold', 28 * s, 13 * s, nameW, 2);
  let nameH = doc.font('Helvetica-Bold').fontSize(size).heightOfString(venue.venueName, { width: nameW });
  while (nameH > room && size > 13 * s) {
    size -= 0.5;
    nameH = doc.font('Helvetica-Bold').fontSize(size).heightOfString(venue.venueName, { width: nameW });
  }
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(size)
    .text(venue.venueName, x + pad, y + h - pad * 1.6 - nameH, { width: nameW, lineGap: -size * 0.05 });
}

/** The yellow call-to-action pill, centred on (cx, cy). */
function drawPill(doc, text, cx, cy, s, maxW) {
  const size = fitSize(doc, text, 'Helvetica-Bold', 15 * s, 9 * s, maxW - 36 * s, 1);
  const textW = doc.font('Helvetica-Bold').fontSize(size).widthOfString(text);
  const w = Math.min(maxW, textW + 36 * s);
  const h = size + 16 * s;
  doc.roundedRect(cx - w / 2, cy - h / 2 + 1.5 * s, w, h, h / 2).fill('#00000022');
  doc.roundedRect(cx - w / 2, cy - h / 2, w, h, h / 2).fill(YELLOW);
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(size)
    .text(text, cx - w / 2, cy - size / 2 + 0.5, { width: w, align: 'center', lineBreak: false });
  return h;
}

/** The QR on a white card with a blue frame and corner accents. */
function drawQRCard(doc, qr, x, y, size, s) {
  const pad = 10 * s;
  const outer = size + pad * 2;
  const r = 14 * s;
  doc.roundedRect(x, y, outer, outer, r).fill('#FFFFFF');
  doc.roundedRect(x, y, outer, outer, r).lineWidth(2.2 * s).strokeColor(BRAND).stroke();
  doc.image(qr, x + pad, y + pad, { width: size, height: size });
  // Yellow corner ticks just outside the frame: the eye goes to the code
  const t = 16 * s;
  const o = 5 * s;
  doc.lineWidth(3 * s).strokeColor(YELLOW).lineCap('round');
  for (const [cx, cy, dx, dy] of [[x - o, y - o, 1, 1], [x + outer + o, y - o, -1, 1],
    [x - o, y + outer + o, 1, -1], [x + outer + o, y + outer + o, -1, -1]]) {
    doc.moveTo(cx, cy + dy * t).lineTo(cx, cy).lineTo(cx + dx * t, cy).stroke();
  }
  doc.lineCap('butt');
  return outer;
}

/** Scan → Save → Share, as numbered dots; or the store's first reward as a chip. */
function drawPerks(doc, copy, x, y, w, s) {
  if (copy.steps) {
    const colors = [BRAND, YELLOW, GREEN];
    const colW = w / copy.steps.length;
    const dot = 9 * s;
    let maxH = 0;
    copy.steps.forEach((label, i) => {
      const cx = x + colW * i + colW / 2;
      doc.circle(cx, y + dot, dot).fill(colors[i]);
      doc.fillColor(i === 1 ? INK : '#FFFFFF').font('Helvetica-Bold').fontSize(10 * s)
        .text(String(i + 1), cx - dot, y + dot - 5 * s, { width: dot * 2, align: 'center', lineBreak: false });
      doc.fillColor(INK_SOFT).font('Helvetica').fontSize(9.5 * s)
        .text(label, x + colW * i + 2 * s, y + dot * 2 + 4 * s, { width: colW - 4 * s, align: 'center' });
      maxH = Math.max(maxH, doc.y - y);
    });
    return maxH;
  }
  const size = fitSize(doc, copy.reward, 'Helvetica-Bold', 12 * s, 8 * s, w - 28 * s, 1);
  const textW = doc.font('Helvetica-Bold').fontSize(size).widthOfString(copy.reward);
  const chipW = Math.min(w, textW + 40 * s);
  const chipH = size + 14 * s;
  const cx = x + (w - chipW) / 2;
  doc.roundedRect(cx, y, chipW, chipH, chipH / 2).fill('#FEF5D7');
  doc.circle(cx + 12 * s, y + chipH / 2, 4 * s).fill(YELLOW);
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(size)
    .text(copy.reward, cx + 20 * s, y + (chipH - size) / 2 + 0.5, { width: chipW - 26 * s, align: 'center', lineBreak: false });
  return chipH;
}

function drawFooter(doc, text, x, y, w, h, s) {
  doc.rect(x, y, w, h).fill(NAVY);
  doc.fillColor('#FFFFFF').font('Helvetica-Bold').fontSize(Math.min(9.5 * s, h * 0.42))
    .text(text, x, y + h / 2 - Math.min(9.5 * s, h * 0.42) / 2, { width: w, align: 'center', lineBreak: false });
}

// --- the faces ---------------------------------------------------------------

// One portrait face: photo hero with the store's name, the pill on its edge,
// the framed code, what to do, the perks, the brand footer. `s` is 1 on a
// 4 in wide face and grows on a bigger one. A wide, low face (the letter
// tent's 11 × 4¼ in) gets drawWideFace instead.
function drawFace(doc, { venue, kind, qr, qrPt, W, H, cover }) {
  const copy = copyFor(kind, venue);
  const s = Math.min(Math.max(Math.min(W / (4 * IN), H / (6 * IN)), 0.8), 1.9);
  if (W / H > 1.6) return drawWideFace(doc, { venue, copy, qr, qrPt, W, H, cover, s });

  doc.rect(0, 0, W, H).fill(CREAM);
  const heroH = H * 0.3;
  drawHero(doc, { venue, cover, x: 0, y: 0, w: W, h: heroH, s });
  const pillH = drawPill(doc, copy.pill, W / 2, heroH, s, W - 36 * s);

  const footH = 24 * s;
  const scanSize = 12 * s;
  const perksH = copy.steps ? 38 * s : 26 * s;
  const top = heroH + pillH / 2 + 16 * s;
  const bottom = H - footH - 14 * s;
  // The code at the asked size, within what's left between pill and perks
  const room = bottom - top - (scanSize + 10 * s) - perksH - 14 * s - 20 * s - 20 * s;
  const qrSize = Math.max(Math.min(qrPt, W - 80 * s, room), IN);
  const cardSize = qrSize + 20 * s;
  const block = cardSize + 12 * s + scanSize + 14 * s + perksH;
  let y = top + Math.max(0, (bottom - top - block) / 2);

  drawQRCard(doc, qr, (W - cardSize) / 2, y, qrSize, s);
  y += cardSize + 12 * s;
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(scanSize)
    .text(copy.scan, 0, y, { width: W, align: 'center', lineBreak: false });
  y += scanSize + 14 * s;
  drawPerks(doc, copy, 22 * s, y, W - 44 * s, s);
  drawFooter(doc, copy.foot, 0, H - footH, W, footH, s);
  return qrSize;
}

// Photo hero on the left, the words in the middle, the code on the right.
function drawWideFace(doc, { venue, copy, qr, qrPt, W, H, cover, s: faceScale }) {
  // A low face's scale comes from its height, and the middle column carries
  // the words at a size that reads across a table
  const s = Math.max(faceScale, (H / (4.25 * IN)) * 1.35);
  doc.rect(0, 0, W, H).fill(CREAM);
  const footH = 16 * s;
  const heroW = W * 0.33;
  drawHero(doc, { venue, cover, x: 0, y: 0, w: heroW, h: H - footH, s: s * 0.75 });

  const qrSize = Math.max(Math.min(qrPt, H - footH - 56 * s), IN);
  const cardSize = qrSize + 20 * s;
  const cardX = W - cardSize - 28 * s;
  const cardY = (H - footH - cardSize) / 2;
  drawQRCard(doc, qr, cardX, cardY, qrSize, s);

  const midX = heroW + 22 * s;
  const midW = cardX - midX - 26 * s;
  const pillH = 15 * s + 16 * s;
  const scanH = 13 * s;
  const perksH = copy.steps ? 38 * s : 26 * s;
  const block = pillH + 16 * s + scanH + 18 * s + perksH;
  let y = (H - footH - block) / 2;
  drawPill(doc, copy.pill, midX + midW / 2, y + pillH / 2, s, midW);
  y += pillH + 16 * s;
  doc.fillColor(INK).font('Helvetica-Bold').fontSize(scanH)
    .text(copy.scan, midX, y, { width: midW, align: 'center', lineBreak: false });
  y += scanH + 18 * s;
  drawPerks(doc, copy, midX, y, midW, s);
  drawFooter(doc, copy.foot, 0, H - footH, W, footH, s);
  return qrSize;
}

// The fold line only: a label on the face printed over the store's photo
// (Wes, 2026-10-30). Where the sheet has a margin, the label goes there.
function foldGuide(doc, x1, y, x2) {
  doc.moveTo(x1, y).lineTo(x2, y)
    .dash(6, { space: 6 }).strokeColor(GUIDE).lineWidth(0.5).stroke().undash();
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
  foldGuide(doc, originX, faceH, originX + faceW);
}

async function renderPDF(venue, rawOptions) {
  const { kind, format, qrInches } = printOptions(rawOptions);
  const code = codeFor(kind, venue);
  const qr = await qrBuffer(code, Math.max(600, Math.round(qrInches * 300)));
  const qrPt = qrInches * IN;
  const geo = GEOMETRY[format];
  const [faceW, faceH] = geo.face || geo.page;
  // The hero's shape on this format's face, fetched at ~300 dpi
  const wide = faceW / faceH > 1.6;
  const heroPt = wide ? [faceW * 0.33, faceH] : [faceW, faceH * 0.3];
  const cover = await coverJPEG(venue, Math.min(2400, heroPt[0] / IN * 300), Math.min(2400, heroPt[1] / IN * 300));
  const doc = new PDFDocument({ size: geo.page, margin: 0 });
  const args = { venue, kind, qr, qrPt, cover };

  if (format === 'sign') {
    const [W, H] = geo.page;
    drawFace(doc, { ...args, W, H });
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
    // The fold, labelled in the margin beside it rather than on the face
    doc.moveTo(x - 14, pageH / 2).lineTo(x - 4, pageH / 2).strokeColor(GUIDE).lineWidth(0.5).stroke();
    doc.fillColor(GUIDE_TEXT).font('Helvetica').fontSize(7)
      .text('fold here', 4, pageH / 2 - 3.5, { width: x - 22, align: 'right' });
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
