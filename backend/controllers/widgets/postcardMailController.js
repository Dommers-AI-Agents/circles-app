// backend/controllers/widgets/postcardMailController.js
// Physical postcards: print-resolution upload, orders, payment, print.
// Step 1 here is the upload path only — the regular /api/upload/image route
// caps at 1MB base64 and the iOS pipeline downsizes to 1280px, both of which
// would silently destroy print resolution, so print art needs its own door.
const sizeOf = require('image-size');
const { uploadImage } = require('../../services/storage');

// 4x6 card at 300 DPI with full bleed: 6.25in x 4.25in.
const PRINT_WIDTH = 1875;
const PRINT_HEIGHT = 1275;
// A rendering pass can land a pixel off; anything further out is a bug or a
// hand-rolled payload, not a rounding artifact.
const DIMENSION_TOLERANCE_PX = 2;
const ASPECT_TOLERANCE = 0.01;

// Print art is ~700KB-1.5MB of JPEG, so ~2MB of base64. 6MB leaves room for
// a denser card without letting an arbitrary upload through.
const MAX_BASE64_BYTES = 6 * 1024 * 1024;

const mailEnabled = () => process.env.POSTCARD_MAIL_ENABLED === '1';

const fail = (res, status, code, message) =>
  res.status(status).json({ success: false, code, message });

/**
 * Measures a decoded image buffer and says whether it can be printed.
 * Exported for tests: this is the only thing standing between a soft,
 * pixelated card and a customer's mailbox.
 */
function checkPrintDimensions(buffer) {
  let meta;
  try {
    meta = sizeOf(buffer);
  } catch (err) {
    return { ok: false, code: 'unreadable_image', message: 'That image couldn\'t be read.' };
  }
  const { width, height, type } = meta || {};
  if (!width || !height) {
    return { ok: false, code: 'unreadable_image', message: 'That image couldn\'t be read.' };
  }
  if (type !== 'jpg' && type !== 'jpeg') {
    return { ok: false, code: 'invalid_format', message: 'Printed postcards must be JPEG.' };
  }
  if (width + DIMENSION_TOLERANCE_PX < PRINT_WIDTH || height + DIMENSION_TOLERANCE_PX < PRINT_HEIGHT) {
    return {
      ok: false,
      code: 'below_print_resolution',
      message: `Printed postcards need at least ${PRINT_WIDTH}x${PRINT_HEIGHT} pixels; that image is ${width}x${height}.`
    };
  }
  const targetAspect = PRINT_WIDTH / PRINT_HEIGHT;
  const aspect = width / height;
  if (Math.abs(aspect - targetAspect) / targetAspect > ASPECT_TOLERANCE) {
    return {
      ok: false,
      code: 'wrong_aspect',
      message: 'A printed postcard must be 6.25 x 4.25 inches (a 1.47 aspect ratio).'
    };
  }
  return { ok: true, width, height };
}

// @desc    Upload a print-resolution postcard image (no resizing, larger cap)
// @route   POST /api/widgets/postcard/mail/upload
// @access  Private
exports.uploadPrintImage = async (req, res) => {
  try {
    if (!mailEnabled()) {
      return fail(res, 503, 'mail_disabled', 'Mailing printed postcards isn\'t available yet.');
    }

    const { image, filename } = req.body || {};
    if (typeof image !== 'string' || !image) {
      return fail(res, 400, 'missing_image', 'image (base64) is required');
    }
    if (image.length > MAX_BASE64_BYTES) {
      return fail(res, 413, 'image_too_large',
        `Image too large: ${(image.length / (1024 * 1024)).toFixed(2)} MB. The limit is ${MAX_BASE64_BYTES / (1024 * 1024)} MB.`);
    }

    const base64 = image.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(base64, 'base64');
    const check = checkPrintDimensions(buffer);
    if (!check.ok) return fail(res, 400, check.code, check.message);

    const imageUrl = await uploadImage(image, filename || 'postcard-print.jpg');
    console.log(`Postcard print image uploaded: ${check.width}x${check.height}, ${(buffer.length / 1024).toFixed(0)} KB`);

    return res.json({
      success: true,
      imageUrl,
      width: check.width,
      height: check.height
    });
  } catch (error) {
    console.error('uploadPrintImage error:', error);
    return fail(res, 500, 'upload_failed', 'The print image couldn\'t be uploaded.');
  }
};

exports.checkPrintDimensions = checkPrintDimensions;
exports.PRINT_WIDTH = PRINT_WIDTH;
exports.PRINT_HEIGHT = PRINT_HEIGHT;
exports.MAX_BASE64_BYTES = MAX_BASE64_BYTES;
