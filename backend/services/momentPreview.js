// backend/services/momentPreview.js
// The image behind a shared moment's link card: the thumbnail, resized for
// a link preview, with a play badge in the middle when the moment is a
// video — a still of a video looks like a photo, and the recipient should
// know it moves before they tap.
const sharp = require('sharp');

const MAX_WIDTH = 1200;
/** Badge diameter as a share of the shorter side. */
const BADGE_RATIO = 0.22;

/** A white play triangle on a translucent dark disc, `size` px across. Pure. */
function playBadgeSvg(size) {
  const s = Math.max(24, Math.round(size));
  const r = s / 2;
  // Triangle: a little right of centre so it reads as centred.
  const tri = [[r * 0.78, r * 0.56], [r * 0.78, r * 1.44], [r * 1.5, r]].map((p) => p.map((n) => n.toFixed(1)).join(',')).join(' ');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}" viewBox="0 0 ${s} ${s}">
  <circle cx="${r}" cy="${r}" r="${(r * 0.96).toFixed(1)}" fill="rgba(0,0,0,0.55)" stroke="rgba(255,255,255,0.9)" stroke-width="${(s * 0.03).toFixed(1)}"/>
  <polygon points="${tri}" fill="#ffffff"/>
</svg>`;
}

/**
 * The preview JPEG for a thumbnail. `play` composites the badge. Returns a
 * Buffer; throws if the input isn't an image sharp can read.
 */
async function composePreview(input, { play = true } = {}) {
  const base = sharp(input).rotate().resize({ width: MAX_WIDTH, withoutEnlargement: true });
  const { width, height } = await base.clone().toBuffer({ resolveWithObject: true }).then((r) => r.info);
  if (!play) return base.jpeg({ quality: 82 }).toBuffer();
  const size = Math.round(Math.min(width, height) * BADGE_RATIO);
  const badge = Buffer.from(playBadgeSvg(size));
  return base
    .composite([{ input: badge, left: Math.round((width - size) / 2), top: Math.round((height - size) / 2) }])
    .jpeg({ quality: 82 })
    .toBuffer();
}

/** Fetches the thumbnail bytes. Global fetch on Node 18+, node-fetch otherwise. */
async function fetchImage(url) {
  const doFetch = typeof fetch === 'function' ? fetch : require('node-fetch');
  const res = await doFetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`thumbnail ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

module.exports = { BADGE_RATIO, MAX_WIDTH, composePreview, fetchImage, playBadgeSvg };
