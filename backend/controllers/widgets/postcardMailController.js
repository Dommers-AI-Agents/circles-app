// backend/controllers/widgets/postcardMailController.js
// Physical postcards: print-resolution upload, orders, payment, print.
// Step 1 here is the upload path only — the regular /api/upload/image route
// caps at 1MB base64 and the iOS pipeline downsizes to 1280px, both of which
// would silently destroy print resolution, so print art needs its own door.
const sizeOf = require('image-size');
const { uploadImage } = require('../../services/storage');
const mailService = require('../../services/postcardMailService');
const stripeClient = require('../../services/stripeClient');
const lobClient = require('../../services/lobClient');

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

const { sendServiceError } = require('../../utils/serviceError');
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

// ---------------------------------------------------------------- orders

// Turns a MailError into its own status/code and anything else into a 500,
// so an unexpected Stripe or Lob failure never leaks its internals to a user.
function sendError(res, error, context) {
  return sendServiceError(res, error, {
    log: `${context} error`, fallbackCode: 'mail_failed', fallbackMessage: 'Something went wrong. Your card wasn\'t charged.'
  });
}

// @desc    What the app needs to show (and hide) the mail option
// @route   GET /api/widgets/postcard/mail/config
exports.getConfig = async (req, res) => {
  try {
    return res.json({ success: true, ...mailService.config() });
  } catch (error) {
    return sendError(res, error, 'postcard mail config');
  }
};

// @desc    Verify a US address and price the card, before anyone pays
// @route   POST /api/widgets/postcard/mail/quote
exports.quote = async (req, res) => {
  try {
    return res.json({ success: true, ...(await mailService.quote(req.body?.recipient)) });
  } catch (error) {
    return sendError(res, error, 'postcard mail quote');
  }
};

// @desc    Create the order and its authorization (a hold, not a charge)
// @route   POST /api/widgets/postcard/mail/orders
exports.createOrder = async (req, res) => {
  try {
    const result = await mailService.createOrder({ userId: req.user.uid, ...(req.body || {}) });
    return res.json({ success: true, ...result });
  } catch (error) {
    return sendError(res, error, 'postcard mail order');
  }
};

// @desc    Record that Apple Pay authorized; opens the free cancel window
// @route   POST /api/widgets/postcard/mail/orders/:id/confirm
exports.confirmOrder = async (req, res) => {
  try {
    const order = await mailService.confirmOrder({ userId: req.user.uid, orderId: req.params.id });
    return res.json({ success: true, order });
  } catch (error) {
    return sendError(res, error, 'postcard mail confirm');
  }
};

// @desc    Cancel before print. Voids the hold; costs the user nothing.
// @route   POST /api/widgets/postcard/mail/orders/:id/cancel
exports.cancelOrder = async (req, res) => {
  try {
    const order = await mailService.cancelOrder({ userId: req.user.uid, orderId: req.params.id });
    return res.json({ success: true, order });
  } catch (error) {
    return sendError(res, error, 'postcard mail cancel');
  }
};

// @route   GET /api/widgets/postcard/mail/orders
exports.listOrders = async (req, res) => {
  try {
    return res.json({ success: true, orders: await mailService.listOrders(req.user.uid) });
  } catch (error) {
    return sendError(res, error, 'postcard mail list');
  }
};

// @route   GET /api/widgets/postcard/mail/orders/:id
exports.getOrder = async (req, res) => {
  try {
    const order = await mailService.getOrder({ userId: req.user.uid, orderId: req.params.id });
    return res.json({ success: true, order });
  } catch (error) {
    return sendError(res, error, 'postcard mail get');
  }
};

// ---------------------------------------------------------------- webhooks
//
// Both of these are called by a vendor with no JWT and verify an HMAC over
// the RAW body, so they are mounted in server.js above the global JSON
// parser — not on the widget router, which is entirely behind `protect`.

// @route POST /api/widgets/postcard/mail/stripe-webhook  (public, raw body)
exports.stripeWebhook = async (req, res) => {
  let event;
  try {
    event = stripeClient.constructEvent(req.body, req.headers['stripe-signature']);
  } catch (error) {
    console.error('Stripe webhook signature rejected:', error.message);
    return res.status(400).send(`Webhook Error: ${error.message}`);
  }
  try {
    // One endpoint, one secret: the router attributes the event to printed
    // postcards or Fridge Mail by object type and metadata.kind
    await require('../../services/stripeEventRouter').route(event);
  } catch (error) {
    // Acknowledge anyway: Stripe retries on non-2xx, and the reconciler
    // already covers everything a missed event would have fixed.
    console.error('Stripe webhook handling failed:', error.message);
  }
  return res.json({ received: true });
};

// @route POST /api/widgets/postcard/mail/lob-webhook  (public, raw body)
exports.lobWebhook = async (req, res) => {
  try {
    const valid = lobClient.verifyWebhook(
      req.body,
      req.headers['lob-signature'],
      req.headers['lob-signature-timestamp']
    );
    if (!valid) return res.status(400).send('Invalid signature');
  } catch (error) {
    console.error('Lob webhook verification failed:', error.message);
    return res.status(400).send('Invalid signature');
  }
  try {
    const event = JSON.parse(req.body.toString('utf8'));
    await mailService.handleLobEvent(event);
  } catch (error) {
    console.error('Lob webhook handling failed:', error.message);
  }
  return res.json({ received: true });
};

// ------------------------------------------------------------ scheduled

// @route POST /api/tasks/postcard-orders-release   (Cloud Scheduler, 10 min)
exports.releaseDue = async (req, res) => {
  try {
    const summary = await mailService.releaseDue();
    console.log('[postcard-mail] release run:', summary);
    return res.json({ success: true, ...summary });
  } catch (error) {
    console.error('postcard release job failed:', error);
    return res.status(500).json({ success: false, error: error.message });
  }
};

// @route POST /api/tasks/postcard-orders-reconcile  (Cloud Scheduler, hourly)
exports.reconcile = async (req, res) => {
  try {
    const summary = await mailService.reconcile();
    console.log('[postcard-mail] reconcile run:', summary);
    return res.json({ success: true, ...summary });
  } catch (error) {
    console.error('postcard reconcile job failed:', error);
    return res.status(500).json({ success: false, error: error.message });
  }
};
