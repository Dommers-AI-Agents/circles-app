// In-App Event images: a real app screen on a holiday-lights photo, no text or logos
// (Apple: the App Store adds the event name, crops and gradients itself).
// usage: node compose.js outdir   → card.html (1920x1080), details.html (1080x1920)
const fs = require('fs');
const path = require('path');
const outDir = process.argv[2];
const here = (f) => `file://${path.resolve(__dirname, f)}`;
const screen = here('raw/holiday-circle.png');

// bgPos: which part of the photo stays in frame; phone: width, left (center x), top
const pages = {
  card: { w: 1920, h: 1080, bg: here('photos/unsplash-Le_ZQt7q7ao.jpg'), bgPos: '50% 70%', phone: { w: 470, cx: 1390, top: 90 } },
  details: { w: 1080, h: 1920, bg: here('photos/unsplash-nbBymbb5jTc.jpg'), bgPos: '50% 50%', phone: { w: 560, cx: 540, top: 170 } }
};

const page = (p) => {
  const bezel = Math.round(p.phone.w * 0.022);
  const radius = Math.round(p.phone.w * 0.115);
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  html,body{margin:0;padding:0}
  body{width:${p.w}px;height:${p.h}px;overflow:hidden;position:relative;background:#0A0F1C url('${p.bg}') ${p.bgPos}/cover no-repeat}
  .dim{position:absolute;inset:0;background:rgba(5,8,15,.28)}
  .device{position:absolute;left:${p.phone.cx - p.phone.w / 2}px;top:${p.phone.top}px;width:${p.phone.w}px;padding:${bezel}px;
    background:#05080F;border-radius:${radius + bezel}px;box-shadow:0 30px 80px rgba(0,0,0,.6),0 0 0 2px #2A3448 inset}
  .device img{display:block;width:100%;border-radius:${radius}px}
</style></head><body><div class="dim"></div><div class="device"><img src="${screen}"></div></body></html>`;
};

fs.mkdirSync(outDir, { recursive: true });
for (const [name, p] of Object.entries(pages)) {
  fs.writeFileSync(path.join(outDir, `${name}.html`), page(p));
  console.log(name, `${p.w}x${p.h}`);
}
