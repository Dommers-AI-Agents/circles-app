// backend/services/scan/images.js — the photos an owner scans, made ready
// for a model: decoded, upright, at most 2,000 px on the long edge (dense
// menus need the detail; more is just cost), re-encoded as JPEG.
const sharp = require('sharp');
const { ServiceError } = require('../../utils/serviceError');

const MAX_IMAGES = 4;
const MAX_TOTAL_BYTES = 8 * 1024 * 1024;
const LONG_EDGE = 2000;

/** base64 (optionally a data: URL) → Buffer, or null. Pure. */
function decode(input) {
  if (typeof input !== 'string' || !input) return null;
  const base64 = input.startsWith('data:') ? input.slice(input.indexOf(',') + 1) : input;
  try {
    const buf = Buffer.from(base64, 'base64');
    return buf.length ? buf : null;
  } catch (e) { return null; }
}

/** [{ base64, mediaType: 'image/jpeg' }] from the request's images. */
async function prepare(images) {
  const list = Array.isArray(images) ? images : [];
  if (!list.length) throw new ServiceError(400, 'no_images', 'Add a photo to scan.');
  if (list.length > MAX_IMAGES) throw new ServiceError(400, 'too_many_images', `Up to ${MAX_IMAGES} photos at a time.`);
  const buffers = list.map(decode);
  if (buffers.some((b) => !b)) throw new ServiceError(400, 'bad_image', 'One of the photos couldn’t be read.');
  if (buffers.reduce((n, b) => n + b.length, 0) > MAX_TOTAL_BYTES) {
    throw new ServiceError(413, 'images_too_large', 'Those photos are too large. Try fewer pages at once.');
  }
  const out = [];
  for (const buf of buffers) {
    try {
      const jpeg = await sharp(buf).rotate()
        .resize({ width: LONG_EDGE, height: LONG_EDGE, fit: 'inside', withoutEnlargement: true })
        .jpeg({ quality: 85 }).toBuffer();
      out.push({ base64: jpeg.toString('base64'), mediaType: 'image/jpeg' });
    } catch (e) {
      throw new ServiceError(400, 'bad_image', 'One of the photos couldn’t be read.');
    }
  }
  return out;
}

module.exports = { MAX_IMAGES, MAX_TOTAL_BYTES, LONG_EDGE, decode, prepare };
