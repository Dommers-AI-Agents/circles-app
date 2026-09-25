// backend/views/momentPage.js
//
// The share page for one moment (api.favcircles.com/share/video/<id>). The
// page body is the static public/video-share.html (its script loads the
// moment); what changes per moment is the <head>: the title and the Open
// Graph image that Messages, WhatsApp and the rest turn into the link card.
//
// The card is the whole message now — the app sends the link alone — so the
// title names the place ("Moment on Circles: Bank of America Stadium") and
// the image is the moment's own thumbnail, with a play badge composited on
// for videos (services/momentPreview.js) so the recipient knows it moves.
const { escapeHtml: esc } = require('../utils/text');

const DEFAULT_IMAGE = 'https://api.favcircles.com/images/circles-preview.png';

/** What the link card says and shows for one moment. Pure. */
function momentMeta(video, { videoId, base = 'https://api.favcircles.com' } = {}) {
  const place = (video && video.placeName ? String(video.placeName) : '').trim();
  const title = place ? `Moment on Circles: ${place}` : 'Moment on Circles';
  const isVideo = !video || (video.contentType || 'video') !== 'photo';
  const hasThumb = !!(video && video.thumbnailUrl);
  return {
    title,
    description: 'Tap to view.',
    url: `${base}/share/video/${encodeURIComponent(videoId)}`,
    // A video's preview carries the play badge; a photo's is the thumbnail itself.
    image: hasThumb ? (isVideo ? `${base}/share/video/${encodeURIComponent(videoId)}/preview.jpg` : video.thumbnailUrl) : DEFAULT_IMAGE,
    isVideo
  };
}

/**
 * The static page with its <title> and share tags replaced. Everything in
 * the template stays as it is; only these tags are rewritten, so the script
 * and layout in public/video-share.html remain the single body.
 */
function renderMoment(template, meta) {
  const tag = (attr, name, content) => `<meta ${attr}="${name}" content="${esc(content)}">`;
  let html = String(template);
  html = html.replace(/<title>[^<]*<\/title>/, `<title>${esc(meta.title)}</title>`);
  html = html.replace(/<meta property="og:title" content="[^"]*">/, tag('property', 'og:title', meta.title));
  html = html.replace(/<meta property="og:description" content="[^"]*">/, tag('property', 'og:description', meta.description));
  html = html.replace(/<meta property="og:image" content="[^"]*">/, tag('property', 'og:image', meta.image) + '\n    ' + tag('property', 'og:url', meta.url) + '\n    ' + tag('property', 'og:site_name', 'Circles'));
  html = html.replace(/<meta name="twitter:title" content="[^"]*">/, tag('name', 'twitter:title', meta.title));
  html = html.replace(/<meta name="twitter:description" content="[^"]*">/, tag('name', 'twitter:description', meta.description) + '\n    ' + tag('name', 'twitter:image', meta.image));
  return html;
}

module.exports = { DEFAULT_IMAGE, momentMeta, renderMoment };
