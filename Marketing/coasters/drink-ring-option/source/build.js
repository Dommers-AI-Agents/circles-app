// Drink-ring coaster option (2026-11-16). Builds both faces as HTML+SVG and
// renders them with headless Chrome.   node build.js
// 1000 units = 4.25 in (4 in coaster + 1/8 in bleed all round).
const path = require('path');
const fs = require('fs');
const { execFileSync } = require('child_process');
const B = path.resolve(__dirname, '../../../../backend');
const QRCode = require(path.join(B, 'node_modules/qrcode'));
const sharp = require(path.join(B, 'node_modules/sharp'));
const rewardService = require(path.join(B, 'services/rewardService'));
const rewardConfig = require(path.join(B, 'config/rewardConfig'));

const PX = 2550;                       // 4.25 in at 600 dpi
const TRIM = 500 * 4 / 4.25;           // cut line radius, units
const SAFE = 500 * 3.7 / 4.25;         // keep words and the code inside this
const INK = '#111317', GOLD = '#F6C945', BLUE = '#3F8FDB', GREEN = '#7CC464', MIST = '#C9D3DF';
const serif = fs.readFileSync(path.join(B, 'assets/fonts/Gelasio-Bold.ttf')).toString('base64');
const url = rewardService.stickerUrl(rewardConfig.GENERIC_JOIN_CODE);

/** White rounded tile with the code, centred on (cx, cy). */
function qrTile(cx, cy, size) {
  const m = QRCode.create(url, { errorCorrectionLevel: 'M' }).modules, n = m.size, quiet = 3;
  const cell = size / (n + quiet * 2); let d = '';
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (m.get(r, c)) {
    let e = c; while (e + 1 < n && m.get(r, e + 1)) e++;
    d += `M${((c + quiet) * cell).toFixed(3)},${((r + quiet) * cell).toFixed(3)}h${((e - c + 1) * cell).toFixed(3)}v${cell.toFixed(3)}h-${((e - c + 1) * cell).toFixed(3)}z`; c = e;
  }
  return `<g transform="translate(${cx - size / 2},${cy - size / 2})"><rect width="${size}" height="${size}" rx="${size * 0.085}" fill="#fff"/><path d="${d}" fill="#000" shape-rendering="crispEdges"/></g>`;
}
/** Map pin with its tip at (x, y). */
const pin = (x, y, s, fill, hole = INK) => `<g transform="translate(${x},${y}) scale(${s})"><path d="M0 0C-13-19-25-33-25-48A25 25 0 1 1 25-48C25-33 13-19 0 0Z" fill="${fill}"/><circle cy="-48" r="9.5" fill="${hole}"/></g>`;
/** The mark a cold glass leaves: a rough bright rim, a thin inner tide line, a faint wash. */
function ring(cx, cy, r, color, { seed = 1, weight = 1, gap = 0 } = {}) {
  const c = 2 * Math.PI * r, dash = gap ? `stroke-dasharray="${(c * (1 - gap)).toFixed(1)} ${(c * gap).toFixed(1)}"` : '';
  return `<g filter="url(#wet${seed})" transform="rotate(${seed * 67} ${cx} ${cy})">
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="${color}" fill-opacity="0.045"/>
    <circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${color}" stroke-width="${7 * weight}" stroke-opacity="0.92" stroke-linecap="round" ${dash}/>
    <circle cx="${cx + 2}" cy="${cy - 1}" r="${r - 11 * weight}" fill="none" stroke="${color}" stroke-width="${1.6 * weight}" stroke-opacity="0.38" stroke-dasharray="${(c * 0.55).toFixed(1)} ${(c * 0.09).toFixed(1)} ${(c * 0.2).toFixed(1)} ${(c * 0.16).toFixed(1)}"/>
    <circle cx="${cx - 3}" cy="${cy + 2}" r="${r + 9 * weight}" fill="none" stroke="${color}" stroke-width="${1.1 * weight}" stroke-opacity="0.22" stroke-dasharray="${(c * 0.3).toFixed(1)} ${(c * 0.7).toFixed(1)}"/>
  </g>`;
}
const wetFilters = [1, 2, 3, 4, 5].map((s) => `<filter id="wet${s}" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.018" numOctaves="2" seed="${s * 7}" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="9" xChannelSelector="R" yChannelSelector="G"/></filter>`).join('');
/** Charcoal bar top with the brand's street grid, faint. */
function ground() {
  let streets = '';
  for (let i = -6; i <= 16; i++) streets += `<line x1="${i * 95 - 300}" y1="-100" x2="${i * 95 + 250}" y2="1100"/><line x1="-100" y1="${i * 120 - 80}" x2="1100" y2="${i * 120 - 330}"/>`;
  return `<rect width="1000" height="1000" fill="${INK}"/>
  <g stroke="#fff" stroke-opacity="0.045" stroke-width="2.2">${streets}</g>
  <g stroke="#fff" stroke-opacity="0.06" stroke-width="5"><line x1="-100" y1="640" x2="1100" y2="300"/><line x1="230" y1="-100" x2="620" y2="1100"/></g>
  <rect width="1000" height="1000" fill="url(#vignette)"/>`;
}
const wordmark = (cx, y, size) => `${pin(cx - size * 2.72, y + size * 0.1, size / 62, BLUE)}<text x="${cx + size * 0.38}" y="${y}" text-anchor="middle" font-family="'Avenir Next', Avenir, sans-serif" font-weight="600" font-size="${size}" fill="#fff" letter-spacing="-0.3">FavCircles</text>`;
const sans = (x, y, size, text, { fill = '#fff', weight = 500, spacing = 0, anchor = 'middle', opacity = 1 } = {}) => `<text x="${x}" y="${y}" text-anchor="${anchor}" font-family="'Avenir Next', Avenir, sans-serif" font-weight="${weight}" font-size="${size}" letter-spacing="${spacing}" fill="${fill}" fill-opacity="${opacity}">${text}</text>`;
const head = (x, y, size, text, fill = '#fff') => `<text x="${x}" y="${y}" text-anchor="middle" font-family="Gelasio" font-weight="700" font-size="${size}" fill="${fill}">${text}</text>`;

// Face A, the hook: the coaster talks about where you are right now
const faceA = `${ground()}
  ${ring(500, 392, 326, GOLD, { seed: 1, weight: 1.15, gap: 0.035 })}
  ${sans(500, 196, 21, 'P S S T .', { fill: GOLD, weight: 600, spacing: 3, opacity: 0.9 })}
  ${head(500, 302, 60, 'You’re sitting in')}
  ${head(500, 392, 76, 'someone’s', GOLD)}
  ${head(500, 478, 76, 'favorite place.', GOLD)}
  ${sans(500, 556, 30, 'Is it one of yours?', { fill: '#fff', opacity: 0.88 })}
  ${qrTile(500, 768, 178)}
  ${sans(382, 760, 25, 'Scan to', { anchor: 'end', weight: 600 })}${sans(382, 792, 25, 'save it.', { anchor: 'end', weight: 600 })}
  ${sans(618, 760, 25, 'Free on', { anchor: 'start', opacity: 0.8 })}${sans(618, 792, 25, 'iPhone.', { anchor: 'start', opacity: 0.8 })}
  ${wordmark(500, 912, 34)}`;

// Face B, the payoff: rings on a bar are circles on your map
const spots = [
  { x: 372, y: 300, r: 128, c: BLUE, seed: 2, label: 'DATE NIGHT' },
  { x: 592, y: 258, r: 112, c: GOLD, seed: 3, label: 'BEST TACOS' },
  { x: 648, y: 432, r: 100, c: GREEN, seed: 4, label: 'COFFEE' },
  { x: 470, y: 462, r: 92, c: MIST, seed: 5, label: 'WANT TO TRY' },
];
const faceB = `${ground()}<g transform="translate(0,-35)">
  <path d="M372 274 C430 186 540 186 592 232 C690 236 742 330 648 406 C600 446 520 396 470 436" fill="none" stroke="#fff" stroke-opacity="0.5" stroke-width="2.6" stroke-dasharray="9 9" stroke-linecap="round"/>
  ${spots.map((s) => ring(s.x, s.y, s.r, s.c, { seed: s.seed, weight: 0.8, gap: 0.03 })).join('')}
  ${spots.map((s) => `${pin(s.x, s.y + 4, 0.62, s.c)}${sans(s.x, s.y + 34, 15.5, s.label, { fill: '#fff', weight: 600, spacing: 2.2, opacity: 0.92 })}`).join('')}
  <text x="500" y="640" text-anchor="middle" font-family="Gelasio" font-weight="700" font-size="88" fill="#fff">Leave your <tspan fill="${GOLD}">mark.</tspan></text>
  ${sans(500, 690, 27, 'Save the places you love into circles.', { opacity: 0.88 })}
  ${sans(500, 726, 27, 'Share them with your people.', { opacity: 0.88 })}
  ${qrTile(500, 836, 150)}
  ${sans(398, 830, 23, 'Scan to start', { anchor: 'end', weight: 600 })}${sans(398, 860, 23, 'your map.', { anchor: 'end', weight: 600 })}
  <g transform="translate(100,0)">${wordmark(590, 852, 27)}</g></g>`;

const page = (body, guides) => `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:Gelasio;font-weight:700;src:url(data:font/ttf;base64,${serif})}
html,body{margin:0;background:${INK}}svg{display:block;width:${PX}px;height:${PX}px}</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000"><defs>${wetFilters}
<radialGradient id="vignette" cx="0.5" cy="0.42" r="0.62"><stop offset="0" stop-color="#2A3038" stop-opacity="0.55"/><stop offset="0.7" stop-color="${INK}" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.35"/></radialGradient></defs>
${body}${guides ? `<circle cx="500" cy="500" r="${TRIM}" fill="none" stroke="#f0f" stroke-width="1.5"/><circle cx="500" cy="500" r="${SAFE}" fill="none" stroke="#0ff" stroke-width="1" stroke-dasharray="6 6"/>` : ''}</svg></body></html>`;

const out = path.resolve(__dirname, '..');
const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
(async () => {
  for (const [name, body] of [['A-hook', faceA], ['B-map', faceB]]) {
    for (const guides of [false, true]) {
      const html = path.join(__dirname, `face-${name}${guides ? '-guides' : ''}.html`);
      fs.writeFileSync(html, page(body, guides));
      const png = guides ? path.join(__dirname, `face-${name}-guides.png`) : path.join(out, `FavCircles-coaster-drink-ring-${name}-print-4.25in-600dpi.png`);
      execFileSync(chrome, ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1', `--window-size=${PX},${PX}`, `--screenshot=${png}`, `file://${html}`], { stdio: 'ignore' });
      if (guides) { fs.unlinkSync(html); continue; }
      // what it looks like cut: the 4 in circle on white
      const r = Math.round(PX * TRIM / 1000), mask = Buffer.from(`<svg width="${PX}" height="${PX}"><circle cx="${PX / 2}" cy="${PX / 2}" r="${r}"/></svg>`);
      const cut = await sharp(png).composite([{ input: mask, blend: 'dest-in' }]).png().toBuffer();
      await sharp(cut).flatten({ background: '#ffffff' }).extract({ left: PX / 2 - r - 20, top: PX / 2 - r - 20, width: r * 2 + 40, height: r * 2 + 40 }).resize(1254).png().toFile(path.join(out, `FavCircles-coaster-drink-ring-${name}-preview.png`));
    }
  }
  console.log('built', url);
})();
