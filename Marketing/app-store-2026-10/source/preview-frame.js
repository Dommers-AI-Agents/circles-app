// Renders the two static layers an App Preview needs for the iPhone Duo:
//   bg-<kind>.png   brand background (opaque)
//   ring-<kind>.png device bezel ring with a transparent middle (overlaid on the footage)
// usage: node preview-frame.js outer|inner outdir   (then render both HTML files with Chrome, see build-preview-duo.sh)
const fs = require('fs'); const path = require('path');
const [, , kind, outDir] = process.argv;
const G = {
  // 886x1920 portrait canvas; folded footage 1398x2034 scaled to 760 wide (hinge corners 8 pt left, 59 pt right)
  outer: { w: 886, h: 1920, fx: 63, fy: 560, fw: 760, fh: 1106, bezel: 20, rl: 10, rr: 70 },
  // 1920x886 landscape canvas; unfolded footage 2853x2007 scaled to 995 wide (55 pt corners)
  inner: { w: 1920, h: 886, fx: 860, fy: 93, fw: 995, fh: 700, bezel: 20, rl: 58, rr: 58 }
}[kind];
const bg = `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0}
body{width:${G.w}px;height:${G.h}px;overflow:hidden;position:relative;background:linear-gradient(165deg,#1E3A70 0%,#0F1E3A 55%,#0A1428 100%)}
.glow{position:absolute;width:${G.w*1.1}px;height:${G.w*1.1}px;left:${-G.w*0.05}px;top:${G.h*0.28}px;border-radius:50%;background:radial-gradient(circle,rgba(79,209,197,.22) 0%,rgba(79,209,197,0) 62%)}
</style></head><body><div class="glow"></div></body></html>`;
const ring = `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;background:transparent}
body{width:${G.w}px;height:${G.h}px;overflow:hidden;position:relative}
.ring{position:absolute;left:${G.fx-G.bezel}px;top:${G.fy-G.bezel}px;width:${G.fw}px;height:${G.fh}px;border:${G.bezel}px solid #05080F;
 border-radius:${G.rl+G.bezel}px ${G.rr+G.bezel}px ${G.rr+G.bezel}px ${G.rl+G.bezel}px;box-shadow:0 30px 70px rgba(0,0,0,.55),0 0 0 2px #2A3448 inset;background:transparent}
</style></head><body><div class="ring"></div></body></html>`;
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, `bg-${kind}.html`), bg);
fs.writeFileSync(path.join(outDir, `ring-${kind}.html`), ring);
console.log(JSON.stringify(G));
