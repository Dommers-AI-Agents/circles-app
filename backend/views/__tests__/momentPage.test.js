const fs = require('fs');
const path = require('path');
const { momentMeta, renderMoment, DEFAULT_IMAGE } = require('../momentPage');
const { playBadgeSvg, composePreview } = require('../../services/momentPreview');

const template = fs.readFileSync(path.join(__dirname, '..', '..', 'public', 'video-share.html'), 'utf8');

test('the link card names the place, says tap to view, and shows the badged preview for a video', () => {
  const meta = momentMeta({ placeName: 'Bank of America Stadium', thumbnailUrl: 'https://cdn/x.jpg', contentType: 'video' }, { videoId: 'v1' });
  expect(meta.title).toBe('Moment on Circles: Bank of America Stadium');
  expect(meta.description).toBe('Tap to view.');
  expect(meta.image).toBe('https://api.favcircles.com/share/video/v1/preview.jpg');
  expect(meta.url).toBe('https://api.favcircles.com/share/video/v1');
});

test('a photo moment shows its own thumbnail; no thumbnail falls back to the app image; no place, no colon', () => {
  expect(momentMeta({ placeName: 'Pier', thumbnailUrl: 'https://cdn/p.jpg', contentType: 'photo' }, { videoId: 'v2' }).image).toBe('https://cdn/p.jpg');
  expect(momentMeta({ placeName: '', contentType: 'video' }, { videoId: 'v3' }).image).toBe(DEFAULT_IMAGE);
  expect(momentMeta({ contentType: 'video' }, { videoId: 'v3' }).title).toBe('Moment on Circles');
});

test('the page keeps its body and script, and swaps only the head tags, escaped', () => {
  const meta = momentMeta({ placeName: 'Tom & Jerry\'s "Bar"', thumbnailUrl: 'https://cdn/x.jpg' }, { videoId: 'v4' });
  const html = renderMoment(template, meta);
  expect(html).toContain('<title>Moment on Circles: Tom &amp; Jerry&#39;s &quot;Bar&quot;</title>');
  expect(html).toContain('<meta property="og:title" content="Moment on Circles: Tom &amp; Jerry&#39;s &quot;Bar&quot;">');
  expect(html).toContain('<meta property="og:description" content="Tap to view.">');
  expect(html).toContain('<meta property="og:image" content="https://api.favcircles.com/share/video/v4/preview.jpg">');
  expect(html).toContain('<meta property="og:url" content="https://api.favcircles.com/share/video/v4">');
  expect(html).toContain('<meta name="twitter:image" content="https://api.favcircles.com/share/video/v4/preview.jpg">');
  expect(html).toContain('<script src="/public/video-share.js" defer></script>');
  expect(html).not.toContain('Share Your Favorite Places');
  expect(html).not.toContain('circles-preview.png');
});

test('the play badge is a centred disc with a triangle, never tiny', () => {
  const svg = playBadgeSvg(10);
  expect(svg).toContain('width="24"');
  expect(playBadgeSvg(200)).toMatch(/<polygon points="[\d.,\s]+" fill="#ffffff"\/>/);
});

test('a preview is a JPEG no wider than the cap, badged for videos and plain for photos', async () => {
  const sharp = require('sharp');
  const src = await sharp({ create: { width: 1600, height: 900, channels: 3, background: '#204080' } }).png().toBuffer();
  const badged = await composePreview(src, { play: true });
  const plain = await composePreview(src, { play: false });
  const info = await sharp(badged).metadata();
  expect(info.format).toBe('jpeg');
  expect(info.width).toBe(1200);
  // The badge lightens the very centre; the plain one stays the flat blue.
  const centre = async (buf) => (await sharp(buf).extract({ left: 598, top: 335, width: 4, height: 4 }).raw().toBuffer())[0];
  expect(await centre(badged)).toBeGreaterThan(await centre(plain) + 40);
});
