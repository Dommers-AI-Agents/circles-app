// The postcard order state machine, where the mistakes cost real money:
// a card mailed that nobody paid for, or a customer charged for a card that
// was never printed. Stripe and Lob are mocked; Firestore is a real in-memory
// fake so the compare-and-set transitions are actually exercised.
const { FakeFirestore, FakeFieldValue } = require('../../__fixtures__/fakeFirestore');

// jest.mock factories are hoisted above the file, so anything they close over
// must be named with a `mock` prefix.
const mockDb = new FakeFirestore();
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

jest.mock('../stripeClient', () => ({
  isEnabled: () => true,
  publishableKey: () => 'pk_test_123',
  createAuthorization: jest.fn(async ({ orderId }) => ({
    id: `pi_${orderId}`, client_secret: `pi_${orderId}_secret`, status: 'requires_payment_method'
  })),
  getPaymentIntent: jest.fn(async (id) => ({ id, status: 'requires_capture' })),
  capture: jest.fn(async (id) => ({ id, status: 'succeeded' })),
  voidAuthorization: jest.fn(async (id) => ({ id, status: 'canceled' })),
  refund: jest.fn()
}));

class MockLobError extends Error {
  constructor(status, message, permanent) { super(message); this.status = status; this.permanent = permanent; }
}
const mockLobErrorClass = MockLobError;
jest.mock('../lobClient', () => ({
  LobError: mockLobErrorClass,
  isEnabled: () => true,
  verifyUSAddress: jest.fn(async (a) => ({
    deliverable: true,
    standardized: { ...a, line1: a.line1.toUpperCase() },
    deliverability: 'deliverable'
  })),
  createPostcard: jest.fn(async () => ({
    id: 'psc_1', expectedDeliveryDate: '2026-09-20', previewUrl: 'https://lob.test/p.pdf', sendDate: null
  })),
  getPostcard: jest.fn()
}));

jest.mock('../notificationService', () => ({ sendToUser: jest.fn(async () => ({ success: true })) }));

jest.mock('../postcardShareService', () => ({
  PUBLIC_BASE_URL: 'https://favcircles.com',
  ASSET_BASE_URL: 'https://api.favcircles.com',
  isAllowedImageUrl: (url) => typeof url === 'string' && url.startsWith('https://storage.googleapis.com/bucket/'),
  create: jest.fn(async () => ({ token: 'tok123', url: 'https://favcircles.com/postcard/tok123', senderName: 'Wes' })),
  get: jest.fn(async () => null)
}));

const stripeClient = require('../stripeClient');
const notificationService = require('../notificationService');
const lobClient = require('../lobClient');
const service = require('../postcardMailService');
const { STATUS } = service;

const USER = 'user-1';
const IMAGE = 'https://storage.googleapis.com/bucket/card.jpg';
const RECIPIENT = { name: 'Ana Ruiz', line1: '123 Main St', city: 'Austin', state: 'tx', zip: '78701' };

// Clients send a UUID; the service requires at least 8 characters so two
// users can't collide on a globally-keyed document.
const ID = (name) => `11111111-2222-3333-4444-${name.padStart(12, '0')}`;

function setEnv() {
  process.env.POSTCARD_MAIL_ENABLED = '1';
  process.env.POSTCARD_PRICE_CENTS_US = '399';
  // Deliberately no POSTCARD_RETURN_ADDRESS_*: printed cards go out with no
  // return address, so that is the configuration the suite runs against.
  for (const key of ['NAME', 'LINE1', 'LINE2', 'CITY', 'STATE', 'ZIP']) {
    delete process.env[`POSTCARD_RETURN_ADDRESS_${key}`];
  }
}

async function placeOrder(name = 'o1') {
  const orderId = ID(name);
  await service.createOrder({ userId: USER, orderId, imageUrl: IMAGE, message: 'Wish you were here', templateId: 'classic', recipient: RECIPIENT });
  await service.confirmOrder({ userId: USER, orderId });
  return orderId;
}

const rowOf = (orderId) => mockDb.docs.get(orderId);

/** Makes the cancel window look closed, the way the release job scans for. */
function closeWindow(orderId) {
  const row = rowOf(orderId);
  mockDb.docs.set(orderId, { ...row, cancelableUntil: new Date(Date.now() - 60000).toISOString() });
}

/**
 * jest.clearAllMocks() forgets calls but keeps implementations, so a
 * persistent mockRejectedValue in one test would leak into the next and make
 * results depend on file order. Re-establish the happy path every time.
 */
function resetVendorMocks() {
  jest.clearAllMocks();
  stripeClient.createAuthorization.mockImplementation(async ({ orderId }) => ({
    id: `pi_${orderId}`, client_secret: `pi_${orderId}_secret`, status: 'requires_payment_method'
  }));
  stripeClient.getPaymentIntent.mockImplementation(async (id) => ({ id, status: 'requires_capture' }));
  stripeClient.capture.mockImplementation(async (id) => ({ id, status: 'succeeded' }));
  stripeClient.voidAuthorization.mockImplementation(async (id) => ({ id, status: 'canceled' }));
  // clearAllMocks keeps implementations: a test that made Lob report "failed"
  // must not leak into the next reconcile
  lobClient.getPostcard.mockReset();
  lobClient.getPostcard.mockImplementation(async () => null);
  lobClient.verifyUSAddress.mockImplementation(async (a) => ({
    deliverable: true,
    standardized: { ...a, line1: a.line1.toUpperCase() },
    deliverability: 'deliverable'
  }));
  lobClient.createPostcard.mockImplementation(async () => ({
    id: 'psc_1', expectedDeliveryDate: '2026-09-20', previewUrl: 'https://lob.test/p.pdf', sendDate: null
  }));
  require('../postcardShareService').create.mockImplementation(async () => ({
    token: 'tok123', url: 'https://favcircles.com/postcard/tok123', senderName: 'Wes'
  }));
  require('../postcardShareService').get.mockImplementation(async () => null);
  notificationService.sendToUser.mockImplementation(async () => ({ success: true }));
}

beforeEach(() => {
  setEnv();
  mockDb.docs.clear();
  resetVendorMocks();
});

describe('creating and authorizing an order', () => {
  it('holds money instead of charging it', async () => {
    await service.createOrder({ userId: USER, orderId: ID('o1'), imageUrl: IMAGE, message: 'hi', recipient: RECIPIENT });
    // capture_method: manual is the whole design; assert the client is asked
    // for an authorization and nothing is captured at compose time.
    expect(stripeClient.createAuthorization).toHaveBeenCalledWith(expect.objectContaining({ orderId: ID('o1'), amountCents: 399 }));
    expect(stripeClient.capture).not.toHaveBeenCalled();
    expect(rowOf(ID('o1')).status).toBe(STATUS.CREATED);
  });

  it('refuses to trust the client that payment happened', async () => {
    stripeClient.getPaymentIntent.mockResolvedValueOnce({ id: `pi_${ID('o1')}`, status: 'requires_payment_method' });
    await service.createOrder({ userId: USER, orderId: ID('o1'), imageUrl: IMAGE, message: 'hi', recipient: RECIPIENT });
    await expect(service.confirmOrder({ userId: USER, orderId: ID('o1') })).rejects.toMatchObject({ code: 'not_authorized' });
    expect(rowOf(ID('o1')).status).toBe(STATUS.CREATED);
  });

  it('opens a cancel window once the hold is real', async () => {
    await placeOrder('o1');
    const row = rowOf(ID('o1'));
    expect(row.status).toBe(STATUS.AUTHORIZED);
    expect(Date.parse(row.cancelableUntil)).toBeGreaterThan(Date.now());
  });

  it('is idempotent: a second create returns the same authorization', async () => {
    await service.createOrder({ userId: USER, orderId: ID('o1'), imageUrl: IMAGE, message: 'hi', recipient: RECIPIENT });
    const again = await service.createOrder({ userId: USER, orderId: ID('o1'), imageUrl: IMAGE, message: 'hi', recipient: RECIPIENT });
    expect(again.paymentIntentClientSecret).toBe(`pi_${ID('o1')}_secret`);
    expect(stripeClient.createAuthorization).toHaveBeenCalledTimes(1);
  });

  it('rejects an image that did not come from our own upload', async () => {
    await expect(service.createOrder({
      userId: USER, orderId: ID('o1'), imageUrl: 'https://evil.test/x.jpg', message: '', recipient: RECIPIENT
    })).rejects.toMatchObject({ code: 'invalid_image' });
  });

  it('rejects an address that is not a mailable US address', async () => {
    await expect(service.createOrder({
      userId: USER, orderId: ID('o1'), imageUrl: IMAGE, message: '', recipient: { ...RECIPIENT, state: 'XX' }
    })).rejects.toMatchObject({ code: 'invalid_recipient' });
  });

  it('refuses a message longer than the back of the card', async () => {
    await expect(service.createOrder({
      userId: USER, orderId: ID('o1'), imageUrl: IMAGE, message: 'x'.repeat(400), recipient: RECIPIENT
    })).rejects.toMatchObject({ code: 'message_too_long' });
  });
});

describe('canceling', () => {
  it('voids the hold and never refunds, so it costs nothing', async () => {
    await placeOrder('o1');
    await service.cancelOrder({ userId: USER, orderId: ID('o1') });
    expect(rowOf(ID('o1')).status).toBe(STATUS.CANCELED);
    expect(stripeClient.voidAuthorization).toHaveBeenCalledWith(`pi_${ID('o1')}`);
    expect(stripeClient.refund).not.toHaveBeenCalled();
    expect(stripeClient.capture).not.toHaveBeenCalled();
  });

  it('refuses once the release job has claimed the order', async () => {
    // The race that would otherwise mail a card nobody paid for: the user
    // cancels while the Lob call is already in flight.
    await placeOrder('o1');
    mockDb.docs.set(ID('o1'), { ...rowOf(ID('o1')), status: STATUS.SUBMITTING });
    await expect(service.cancelOrder({ userId: USER, orderId: ID('o1') })).rejects.toMatchObject({ code: 'too_late' });
    expect(stripeClient.voidAuthorization).not.toHaveBeenCalled();
  });

  it('will not let one user cancel another user\'s order', async () => {
    await placeOrder('o1');
    await expect(service.cancelOrder({ userId: 'someone-else', orderId: ID('o1') })).rejects.toMatchObject({ code: 'not_your_order' });
  });
});

/** Lob's "rendered" webhook — the moment the money is allowed to move. */
const rendered = (lobId = 'psc_1') => service.handleLobEvent({ event_type: { id: 'postcard.rendered_pdf' }, body: { id: lobId } });

describe('release: print first, then take the money', () => {
  it('prints on release and leaves the hold in place until Lob has rendered the card', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    const summary = await service.releaseDue();

    expect(summary.released).toBe(1);
    expect(lobClient.createPostcard).toHaveBeenCalledTimes(1);
    expect(stripeClient.capture).not.toHaveBeenCalled(); // a render failure must still be a free void
    const row = rowOf(ID('o1'));
    expect(row.status).toBe(STATUS.SUBMITTED);
    expect(row.lobPostcardId).toBe('psc_1');
    expect(row.capturedAt).toBeNull();
    expect(row.awaitingRenderSince).toBeTruthy();
  });

  it('captures when Lob says the card rendered, and only once', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();

    await rendered();
    expect(stripeClient.capture).toHaveBeenCalledWith(`pi_${ID('o1')}`);
    expect(rowOf(ID('o1')).capturedAt).toBeTruthy();

    // Stripe already reports the intent captured on a redelivery
    stripeClient.getPaymentIntent.mockImplementation(async (id) => ({ id, status: 'succeeded' }));
    await rendered();
    expect(stripeClient.capture).toHaveBeenCalledTimes(1);
  });

  it('sends the QR image from the API host, not the redirect-only friendly host', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    const backHtml = lobClient.createPostcard.mock.calls[0][0].backHtml;
    expect(backHtml).toContain('src="https://api.favcircles.com/postcard/tok123/qr.png"');
    expect(backHtml).toContain('favcircles.com/postcard/tok123'); // the printed link stays friendly
  });

  it('leaves an order alone while its cancel window is still open', async () => {
    await placeOrder('o1');
    const summary = await service.releaseDue();
    expect(summary.released).toBe(0);
    expect(lobClient.createPostcard).not.toHaveBeenCalled();
  });

  it('prints once even if the job runs twice', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    await service.releaseDue();
    expect(lobClient.createPostcard).toHaveBeenCalledTimes(1);
    expect(stripeClient.capture).not.toHaveBeenCalled();
  });

  it('passes the order id to Lob as the idempotency key', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    expect(lobClient.createPostcard).toHaveBeenCalledWith(expect.objectContaining({ idempotencyKey: ID('o1') }));
  });

  it('mints the public page server-side, only after the window closed', async () => {
    const shareService = require('../postcardShareService');
    await placeOrder('o1');
    expect(shareService.create).not.toHaveBeenCalled(); // an unmailed order has no page
    closeWindow(ID('o1'));
    await service.releaseDue();
    expect(shareService.create).toHaveBeenCalledTimes(1);
    expect(rowOf(ID('o1')).publicPageToken).toBe('tok123');
  });
});

describe('release failures', () => {
  it('voids the hold when Lob permanently refuses — no charge, no refund', async () => {
    lobClient.createPostcard.mockRejectedValueOnce(new MockLobError(422, 'Address is undeliverable', true));
    await placeOrder('o1');
    closeWindow(ID('o1'));
    const summary = await service.releaseDue();

    expect(summary.rejected).toBe(1);
    expect(rowOf(ID('o1')).status).toBe(STATUS.REJECTED);
    expect(stripeClient.voidAuthorization).toHaveBeenCalledWith(`pi_${ID('o1')}`);
    expect(stripeClient.capture).not.toHaveBeenCalled();
    expect(stripeClient.refund).not.toHaveBeenCalled();
  });

  it('retries a transient Lob failure with the hold untouched', async () => {
    lobClient.createPostcard.mockRejectedValueOnce(new MockLobError(503, 'Service unavailable', false));
    await placeOrder('o1');
    closeWindow(ID('o1'));
    const summary = await service.releaseDue();

    expect(summary.retried).toBe(1);
    expect(rowOf(ID('o1')).status).toBe(STATUS.AUTHORIZED);
    expect(stripeClient.voidAuthorization).not.toHaveBeenCalled();
  });

  it('gives up after three transient failures rather than retrying forever', async () => {
    lobClient.createPostcard.mockRejectedValue(new MockLobError(503, 'Service unavailable', false));
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    closeWindow(ID('o1'));
    await service.releaseDue();
    closeWindow(ID('o1'));
    await service.releaseDue();

    expect(rowOf(ID('o1')).status).toBe(STATUS.REJECTED);
    expect(stripeClient.voidAuthorization).toHaveBeenCalledWith(`pi_${ID('o1')}`);
  });

  it('keeps the card when capture fails after Lob rendered it', async () => {
    // The one path that can cost us money. Unwinding here would mail a card
    // and cancel the payment, so the order stands and the reconciler retries.
    stripeClient.capture.mockRejectedValueOnce(new Error('card_declined'));
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    await rendered();

    const row = rowOf(ID('o1'));
    expect(row.status).toBe(STATUS.SUBMITTED);
    expect(row.capturedAt).toBeNull();
    expect(row.error).toBe('capture_pending');
  });
});

describe('reconciler', () => {
  it('retries a capture for a card Lob has rendered', async () => {
    stripeClient.capture.mockRejectedValueOnce(new Error('temporary'));
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    await rendered();
    expect(rowOf(ID('o1')).capturedAt).toBeNull();

    lobClient.getPostcard.mockResolvedValue({ id: 'psc_1', status: 'processed', thumbnails: [{ small: 'x' }] });
    const summary = await service.reconcile();
    expect(summary.captured).toBe(1);
    expect(rowOf(ID('o1')).capturedAt).toBeTruthy();
  });

  it('leaves a just-submitted card alone until the render grace passes, then captures', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    lobClient.getPostcard.mockResolvedValue({ id: 'psc_1', status: 'processed', thumbnails: [] });

    expect((await service.reconcile()).captured).toBe(0); // rendered_pdf may still arrive
    expect(stripeClient.capture).not.toHaveBeenCalled();

    const row = rowOf(ID('o1'));
    mockDb.docs.set(ID('o1'), { ...row, awaitingRenderSince: new Date(Date.now() - 45 * 60000).toISOString() });
    expect((await service.reconcile()).captured).toBe(1);
    expect(rowOf(ID('o1')).capturedAt).toBeTruthy();
  });

  it('voids, never captures, a card Lob reports as failed — even after the grace', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    const row = rowOf(ID('o1'));
    mockDb.docs.set(ID('o1'), { ...row, awaitingRenderSince: new Date(Date.now() - 45 * 60000).toISOString() });
    lobClient.getPostcard.mockResolvedValue({ id: 'psc_1', status: 'failed', thumbnails: [] });

    const summary = await service.reconcile();
    // The tracking sweep (step 0) sees the failure first; the capture step
    // then has nothing left to void. Either way: voided, never captured.
    expect(summary.tracking.failed + (summary.voided || 0)).toBe(1);
    expect(stripeClient.voidAuthorization).toHaveBeenCalledWith(`pi_${ID('o1')}`);
    expect(stripeClient.capture).not.toHaveBeenCalled();
    expect(stripeClient.refund).not.toHaveBeenCalled();
    expect(rowOf(ID('o1')).status).toBe(STATUS.REJECTED);
  });

  it('returns a claim stranded by a dead job to authorized', async () => {
    await placeOrder('o1');
    mockDb.docs.set(ID('o1'), {
      ...rowOf(ID('o1')),
      status: STATUS.SUBMITTING,
      updatedAt: new Date(Date.now() - 30 * 60000).toISOString()
    });
    const summary = await service.reconcile();
    expect(summary.unstuck).toBe(1);
    expect(rowOf(ID('o1')).status).toBe(STATUS.AUTHORIZED);
  });

  it('expires an order that never got a hold', async () => {
    await service.createOrder({ userId: USER, orderId: ID('o1'), imageUrl: IMAGE, message: 'hi', recipient: RECIPIENT });
    mockDb.docs.set(ID('o1'), { ...rowOf(ID('o1')), createdAt: new Date(Date.now() - 48 * 3600000).toISOString() });
    const summary = await service.reconcile();
    expect(summary.expired).toBe(1);
    expect(rowOf(ID('o1')).status).toBe(STATUS.EXPIRED);
  });
});

describe('stripe webhook', () => {
  it('authorizes when the client died right after Apple Pay', async () => {
    await service.createOrder({ userId: USER, orderId: ID('o1'), imageUrl: IMAGE, message: 'hi', recipient: RECIPIENT });
    await service.handleStripeEvent({
      type: 'payment_intent.amount_capturable_updated',
      data: { object: { metadata: { orderId: ID('o1') } } }
    });
    expect(rowOf(ID('o1')).status).toBe(STATUS.AUTHORIZED);
  });

  it('is a no-op when the client already confirmed', async () => {
    await placeOrder('o1');
    const before = rowOf(ID('o1')).cancelableUntil;
    await service.handleStripeEvent({
      type: 'payment_intent.amount_capturable_updated',
      data: { object: { metadata: { orderId: ID('o1') } } }
    });
    expect(rowOf(ID('o1')).cancelableUntil).toBe(before); // window not restarted
  });

  it('never resurrects a released order', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    await service.handleStripeEvent({
      type: 'payment_intent.amount_capturable_updated',
      data: { object: { metadata: { orderId: ID('o1') } } }
    });
    expect(rowOf(ID('o1')).status).toBe(STATUS.SUBMITTED);
  });
});

describe('config and quote', () => {
  it('hides the feature when the flag is off', () => {
    process.env.POSTCARD_MAIL_ENABLED = '0';
    expect(service.config().enabled).toBe(false);
  });

  it('serves the price from config so the app never hardcodes it', () => {
    process.env.POSTCARD_PRICE_CENTS_US = '499';
    expect(service.config().priceCents).toBe(499);
  });

  it('returns the standardized address so the user sees what gets printed', async () => {
    const quote = await service.quote(RECIPIENT);
    expect(quote.deliverable).toBe(true);
    expect(quote.standardized.line1).toBe('123 MAIN ST');
    expect(quote.standardized.state).toBe('TX'); // normalized before verification
  });
});

describe('the printed back of the card', () => {
  it('references the QR by URL, not an inline data URI', () => {
    // Lob caps rendered HTML at roughly 10k characters, which an embedded
    // PNG blows straight past.
    const html = service.buildBackHtml({
      message: 'Hello', senderName: 'Wes',
      pageUrl: 'https://favcircles.com/postcard/tok123',
      qrUrl: 'https://favcircles.com/postcard/tok123/qr.png'
    });
    expect(html).toContain('src="https://favcircles.com/postcard/tok123/qr.png"');
    expect(html).not.toContain('data:image');
    expect(html.length).toBeLessThan(10000);
  });

  it('escapes a message that contains markup', () => {
    const html = service.buildBackHtml({ message: '<script>x</script>', senderName: 'Wes', pageUrl: '', qrUrl: '' });
    expect(html).not.toContain('<script>x</script>');
    expect(html).toContain('&lt;script&gt;');
  });
});


describe('telling the customer what happened', () => {
  it('says plainly that nobody was charged when printing fails', async () => {
    // Without this the sender assumes the card is in the mail and only finds
    // out when it never arrives.
    lobClient.createPostcard.mockRejectedValueOnce(new MockLobError(422, 'undeliverable', true));
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();

    expect(notificationService.sendToUser).toHaveBeenCalledWith(USER, expect.objectContaining({
      body: expect.stringContaining("weren't charged")
    }));
  });

  it('confirms the card is printing, with the typical delivery window rather than Lob\'s outer date', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    expect(notificationService.sendToUser).toHaveBeenCalledWith(USER, expect.objectContaining({
      body: expect.stringContaining('Typically arrives in 4 to 6 business days')
    }));
    const body = notificationService.sendToUser.mock.calls[0][1].body;
    expect(body).not.toContain('Sep 20');
  });

  it('never lets a failed push fail the order it describes', async () => {
    notificationService.sendToUser.mockRejectedValue(new Error('APNs down'));
    await placeOrder('o1');
    closeWindow(ID('o1'));
    const summary = await service.releaseDue();
    expect(summary.released).toBe(1);
    expect(rowOf(ID('o1')).status).toBe(STATUS.SUBMITTED);
  });
});

describe('Lob tracking events', () => {
  async function submitted() {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    return ID('o1');
  }

  it('pushes once when the card is delivered, and not again on a redelivered webhook', async () => {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    notificationService.sendToUser.mockClear();
    await service.handleLobEvent({ event_type: { id: 'postcard.in_transit' }, body: { id: 'psc_1' } });
    expect(notificationService.sendToUser).not.toHaveBeenCalled(); // transit stays silent
    await service.handleLobEvent({ event_type: { id: 'postcard.processed_for_delivery' }, body: { id: 'psc_1' } });
    await service.handleLobEvent({ event_type: { id: 'postcard.processed_for_delivery' }, body: { id: 'psc_1' } });
    expect(notificationService.sendToUser).toHaveBeenCalledTimes(1);
    expect(notificationService.sendToUser).toHaveBeenCalledWith(USER, expect.objectContaining({
      title: 'Your postcard was delivered',
      body: expect.stringContaining('Ana Ruiz')
    }));
  });

  it('treats processed_for_delivery as the end of the line', async () => {
    // USPS does not scan First Class postcards on delivery, so waiting for a
    // `delivered` event would leave every order in transit forever.
    const id = await submitted();
    await service.handleLobEvent({ event_type: { id: 'postcard.processed_for_delivery' }, body: { id: 'psc_1' } });
    expect(rowOf(id).status).toBe(STATUS.DELIVERED);
  });

  it('tracks the intermediate stops', async () => {
    const id = await submitted();
    await service.handleLobEvent({ event_type: { id: 'postcard.in_local_area' }, body: { id: 'psc_1' } });
    expect(rowOf(id).status).toBe(STATUS.IN_TRANSIT);
  });

  it('flags a returned card for a human instead of swallowing it', async () => {
    const id = await submitted();
    await service.handleLobEvent({ event_type: { id: 'postcard.returned_to_sender' }, body: { id: 'psc_1' } });
    expect(rowOf(id).status).toBe(STATUS.RETURNED);
    expect(rowOf(id).needsReview).toBe(true);
  });

  it('ignores an event for a postcard we don\'t know', async () => {
    await submitted();
    const result = await service.handleLobEvent({ event_type: { id: 'postcard.in_transit' }, body: { id: 'psc_other' } });
    expect(result.ignored).toBe(true);
  });
});

describe('the reconciler respects the same status rules', () => {
  it('will not drag a released order back into the cancel window', async () => {
    // A slow release tick that finished between the scan and the write. A
    // plain update here would show Cancel on a card already in the mail.
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    mockDb.docs.set(ID('o1'), { ...rowOf(ID('o1')), updatedAt: new Date(Date.now() - 30 * 60000).toISOString() });

    await service.reconcile();
    expect(rowOf(ID('o1')).status).toBe(STATUS.SUBMITTED);
  });
});


describe('the return address', () => {
  it('is omitted entirely, not sent as null', async () => {
    // Lob treats a null `from` differently from an absent one, so the key has
    // to be gone rather than empty.
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();

    const sent = lobClient.createPostcard.mock.calls[0][0];
    expect(sent.from).toBeUndefined();
    expect(Object.keys(sent)).not.toContain('from');
  });

  it('still prints one when a full address is configured', async () => {
    // Turning it back on must stay an env change, never a code change.
    process.env.POSTCARD_RETURN_ADDRESS_NAME = 'FavCircles';
    process.env.POSTCARD_RETURN_ADDRESS_LINE1 = 'PO Box 1';
    process.env.POSTCARD_RETURN_ADDRESS_CITY = 'Charlotte';
    process.env.POSTCARD_RETURN_ADDRESS_STATE = 'NC';
    process.env.POSTCARD_RETURN_ADDRESS_ZIP = '28202';

    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();

    expect(lobClient.createPostcard.mock.calls[0][0].from).toMatchObject({
      name: 'FavCircles', address_city: 'Charlotte', address_country: 'US'
    });
  });

  it('ignores a half-filled address rather than printing part of one', async () => {
    process.env.POSTCARD_RETURN_ADDRESS_NAME = 'FavCircles';
    process.env.POSTCARD_RETURN_ADDRESS_LINE1 = 'PO Box 1';
    // city/state/zip missing

    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();

    expect(lobClient.createPostcard.mock.calls[0][0].from).toBeUndefined();
  });

  it('keeps the sender signature on the back', () => {
    // The signature is not the return address. With no return address it is
    // the only thing telling the recipient who sent the card.
    const html = service.buildBackHtml({ message: 'Hello', senderName: 'Wes', pageUrl: '', qrUrl: '' });
    expect(html).toContain('Wes');
  });
});


describe('Lob refuses the card after accepting it', () => {
  async function mailedOrder() {
    await placeOrder('o1');
    closeWindow(ID('o1'));
    await service.releaseDue();
    return ID('o1');
  }

  it('refunds when the money was already captured', async () => {
    // A refusal after rendered_pdf (rare — the print line, not the render)
    // arrives after capture. There is no hold left to void — only a refund
    // stops us keeping money for a card that will never exist.
    const id = await mailedOrder();
    await rendered();
    expect(rowOf(id).capturedAt).toBeTruthy();

    await service.handleLobEvent({ event_type: { id: 'postcard.rejected' }, body: { id: 'psc_1' } });

    expect(stripeClient.refund).toHaveBeenCalledWith(`pi_${id}`);
    expect(rowOf(id).status).toBe(STATUS.REFUNDED);
  });

  it('voids instead of refunding when the render itself fails — the 2026-09-17 case', async () => {
    const id = await mailedOrder();
    expect(rowOf(id).capturedAt).toBeNull();

    await service.handleLobEvent({ event_type: { id: 'postcard.failed' }, body: { id: 'psc_1' } });

    expect(stripeClient.voidAuthorization).toHaveBeenCalledWith(`pi_${id}`);
    expect(stripeClient.refund).not.toHaveBeenCalled();
    expect(rowOf(id).status).toBe(STATUS.REJECTED);
  });

  it('tells the sender, and says whether they were charged', async () => {
    const id = await mailedOrder();
    await service.handleLobEvent({ event_type: { id: 'postcard.failed' }, body: { id: 'psc_1' } });
    expect(notificationService.sendToUser).toHaveBeenCalledWith(USER, expect.objectContaining({
      body: expect.stringContaining("weren't charged")
    }));
  });

  it('does not refund twice when the webhook is redelivered', async () => {
    const id = await mailedOrder();
    await rendered();
    await service.handleLobEvent({ event_type: { id: 'postcard.rejected' }, body: { id: 'psc_1' } });
    await service.handleLobEvent({ event_type: { id: 'postcard.rejected' }, body: { id: 'psc_1' } });
    expect(stripeClient.refund).toHaveBeenCalledTimes(1);
  });

  it('flags for review rather than looking fine when the refund itself fails', async () => {
    stripeClient.refund.mockRejectedValueOnce(new Error('refund unavailable'));
    const id = await mailedOrder();
    await rendered();
    await service.handleLobEvent({ event_type: { id: 'postcard.rejected' }, body: { id: 'psc_1' } });

    const row = rowOf(id);
    expect(row.needsReview).toBe(true);
    expect(row.error).toContain('refund_failed');
  });
});

describe('pulling the truth from Lob', () => {
  // The first real orders: three cards sat at "rendered" under a funding
  // hold and one had failed at render after capture — and every webhook
  // that would have said so was missing. The reconciler asks Lob directly.
  async function paidSubmittedOrder(name = 'o1') {
    await placeOrder(name);
    closeWindow(ID(name));
    await service.releaseDue();
    await rendered();                      // captured
    expect(rowOf(ID(name)).capturedAt).toBeTruthy();
    expect(rowOf(ID(name)).status).toBe(STATUS.SUBMITTED);
  }

  it('records a funding hold and says so, without touching the status', async () => {
    await paidSubmittedOrder();
    lobClient.getPostcard.mockResolvedValue({ id: 'psc_1', status: 'rendered', lob_credits_funding_status: 'funding_hold', tracking_events: [], send_date: '2026-09-18T18:30:06Z' });
    const summary = await service.reconcile();
    expect(summary.tracking).toMatchObject({ synced: 1, holds: 1 });
    const row = rowOf(ID('o1'));
    expect(row.status).toBe(STATUS.SUBMITTED);
    expect(row.lobFundingStatus).toBe('funding_hold');
    expect(service.present(ID('o1'), row)).toMatchObject({ printerHold: true, printerStatus: 'rendered' });
  });

  it('refunds a captured card Lob failed after the fact', async () => {
    await paidSubmittedOrder();
    lobClient.getPostcard.mockResolvedValue({ id: 'psc_1', status: 'failed', failure_reason: { errors: [{ code: '404' }] }, tracking_events: [] });
    await service.reconcile();
    expect(stripeClient.refund).toHaveBeenCalledWith(`pi_${ID('o1')}`);
    expect(rowOf(ID('o1')).status).toBe(STATUS.REFUNDED);
  });

  it('moves a card along from carrier scans, delivered push included', async () => {
    await paidSubmittedOrder();
    lobClient.getPostcard.mockResolvedValue({ id: 'psc_1', status: 'mailed', tracking_events: [
      { name: 'Mailed', time: '2026-09-19T10:00:00Z' },
      { name: 'Processed for Delivery', time: '2026-09-22T10:00:00Z' },
      { name: 'In Transit', time: '2026-09-20T10:00:00Z' }
    ] });
    await service.reconcile();
    const row = rowOf(ID('o1'));
    expect(row.status).toBe(STATUS.DELIVERED);
    expect(row.lobLastTrackingEvent).toBe('processed_for_delivery');
    expect(notificationService.sendToUser).toHaveBeenCalledWith(row.userId, expect.objectContaining({ title: 'Your postcard was delivered' }));
  });

  it('a list read answers at once and asks Lob about stale rows afterwards', async () => {
    await paidSubmittedOrder();
    lobClient.getPostcard.mockResolvedValue({ id: 'psc_1', status: 'rendered', tracking_events: [] });
    const orders = await service.listOrders(rowOf(ID('o1')).userId);
    expect(orders).toHaveLength(1);
    expect(orders[0].printerHold).toBe(false);
    await new Promise((r) => setImmediate(r));
    expect(lobClient.getPostcard).toHaveBeenCalledWith('psc_1');
    // Freshly synced: the next read does not ask again
    lobClient.getPostcard.mockClear();
    await service.listOrders(rowOf(ID('o1')).userId);
    await new Promise((r) => setImmediate(r));
    expect(lobClient.getPostcard).not.toHaveBeenCalled();
  });
});
