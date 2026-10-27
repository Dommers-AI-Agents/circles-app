// Builds one App Store screenshot page (HTML) per slide; render.sh screenshots them.
// usage: node compose.js slides.json outdir
const fs = require('fs');
const path = require('path');
const [, , slidesFile, outDir] = process.argv;
const { device, slides } = JSON.parse(fs.readFileSync(slidesFile, 'utf8'));

const SIZES = {
  iphone: { w: 1320, h: 2868, shotW: 1030, radius: 118, bezel: 26, top: 700, head: 104, sub: 46 },
  ipad: { w: 2064, h: 2752, shotW: 1560, radius: 64, bezel: 30, top: 640, head: 118, sub: 52 },
  // iPhone Duo folded (outer display, 1398x2034). The left corners are the hinge side
  // (8 pt), the right corners the outer edge (59 pt), as in the device profile.
  duoOuter: { w: 1398, h: 2034, shotW: 1010, radius: 128, radiusLeft: 18, bezel: 26, top: 520, head: 96, sub: 44 },
  // iPhone Duo unfolded (inner display, captured landscape 2853x2007; 55 pt corners).
  // Copy sits on the left, the device on the right.
  duoInner: { w: 2853, h: 2007, shotW: 1480, radius: 118, bezel: 30, head: 112, sub: 50, side: true, copyW: 0.34 }
};
const S = SIZES[device];

const page = (s) => `<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@500;700;800&display=swap" rel="stylesheet">
<style>
  html,body{margin:0;padding:0}
  body{width:${S.w}px;height:${S.h}px;overflow:hidden;position:relative;font-family:Inter,-apple-system,Helvetica,Arial,sans-serif;
    background:${s.bg || 'linear-gradient(165deg,#1E3A70 0%,#0F1E3A 55%,#0A1428 100%)'}}
  .glow{position:absolute;width:${S.w * 1.1}px;height:${S.w * 1.1}px;left:${-S.w * 0.05}px;top:${S.h * 0.28}px;border-radius:50%;
    background:radial-gradient(circle,rgba(79,209,197,.22) 0%,rgba(79,209,197,0) 62%)}
  .copy{position:absolute;left:0;right:0;top:${Math.round((S.top || 0) * 0.2)}px;text-align:center;padding:0 ${Math.round(S.w * 0.07)}px}
  ${S.side ? `.copy{right:auto;width:${Math.round(S.w * S.copyW)}px;top:50%;transform:translateY(-50%);text-align:left;padding:0 ${Math.round(S.w * 0.035)}px 0 ${Math.round(S.w * 0.045)}px}` : ''}
  h1{text-wrap:balance;margin:0;color:#fff;font-weight:800;font-size:${S.head}px;line-height:1.08;letter-spacing:-2px}
  h1 em{font-style:normal;color:#4FD1C5}
  p{text-wrap:balance;margin:${Math.round(S.head * 0.3)}px 0 0;color:rgba(255,255,255,.78);font-weight:500;font-size:${S.sub}px;line-height:1.3}
  .device{position:absolute;left:50%;top:${S.top}px;transform:translateX(-50%);width:${S.shotW}px;padding:${S.bezel}px;
    background:#05080F;border-radius:${S.radius + S.bezel}px;box-shadow:0 40px 90px rgba(0,0,0,.55),0 0 0 3px #2A3448 inset}
  .device img{display:block;width:100%;border-radius:${S.radius}px}
  ${S.side ? `.device{left:auto;right:${Math.round(S.w * 0.045)}px;top:50%;transform:translateY(-50%)}` : ''}
  ${S.radiusLeft ? `.device{border-radius:${S.radiusLeft + S.bezel}px ${S.radius + S.bezel}px ${S.radius + S.bezel}px ${S.radiusLeft + S.bezel}px}
  .device img{border-radius:${S.radiusLeft}px ${S.radius}px ${S.radius}px ${S.radiusLeft}px}` : ''}
</style></head><body>
  <div class="glow"></div>
  <div class="copy"><h1>${s.headline}</h1>${s.sub ? `<p>${s.sub}</p>` : ''}</div>
  <div class="device"><img src="file://${path.resolve(s.image)}"></div>
</body></html>`;

fs.mkdirSync(outDir, { recursive: true });
slides.forEach((s, i) => {
  const name = `${String(i + 1).padStart(2, '0')}-${s.slug}`;
  fs.writeFileSync(path.join(outDir, `${name}.html`), page(s));
  console.log(name);
});
