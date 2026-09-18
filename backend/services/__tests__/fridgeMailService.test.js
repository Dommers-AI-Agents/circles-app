// Fridge Mail: the weekly send, the entitlement order (subscription slots
// then pack credits), pack crediting exactly once, the due-day rule across
// timezones/DST, and the card back. Stripe/Lob/push are mocked; Firestore is
// the in-memory fake (namespaced: plans, pack orders and cards are separate).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../stripeClient', () => ({
  isEnabled: () => true,
  createPayment: jest.fn(async ({ orderId }) => ({ id: `pi_${orderId}`, client_secret: `pi_${orderId}_secret` })),
  getPaymentIntent: jest.fn(async (id) => ({ id, status: 'succeeded' })),
  ensureCustomer: jest.fn(async () => ({ id: 'cus_1' })),
  createSetupIntent: jest.fn(async () => ({ id: 'seti_1', client_secret: 'seti_1_secret' })),
  getSetupIntent: jest.fn(async () => ({ id: 'seti_1', status: 'succeeded', customer: 'cus_1', payment_method: 'pm_1' })),
  setDefaultPaymentMethod: jest.fn(async () => ({})),
  priceByLookupKey: jest.fn(async () => ({ id: 'price_1' })),
  createSubscription: jest.fn(async ({ quantity }) => ({
    id: 'sub_1', status: 'active', cancel_at_period_end: false, current_period_end: 1800000000,
    items: { data: [{ id: 'si_1', quantity }] }
  })),
  getSubscription: jest.fn(),
  updateSubscriptionQuantity: jest.fn(async ({ quantity }) => ({ id: 'sub_1', status: 'active', items: { data: [{ id: 'si_1', quantity }] } })),
  cancelSubscriptionAtPeriodEnd: jest.fn(async () => ({ id: 'sub_1', status: 'active', cancel_at_period_end: true, items: { data: [{ id: 'si_1', quantity: 1 }] } })),
  resumeSubscription: jest.fn(),
  refund: jest.fn(), voidAuthorization: jest.fn(), capture: jest.fn(), createAuthorization: jest.fn(),
  publishableKey: () => 'pk_test'
}));
jest.mock('../lobClient', () => ({
  isEnabled: () => true,
  createPostcard: jest.fn(async ({ idempotencyKey }) => ({ id: `psc_${idempotencyKey}`, expectedDeliveryDate: '2026-09-28', previewUrl: null })),
  getPostcard: jest.fn(),
  verifyUSAddress: jest.fn()
}));
jest.mock('../postcardMailService', () => ({
  quote: jest.fn(async (r) => ({ deliverable: true, standardized: { name: r.name, line1: String(r.line1).toUpperCase(), line2: r.line2 || '', city: 'CHARLOTTE', state: 'NC', zip: '28203' } }))
}));
jest.mock('../postcardShareService', () => ({
  isAllowedImageUrl: (u) => typeof u === 'string' && u.startsWith('https://storage.googleapis.com/bucket/')
}));
jest.mock('../notificationService', () => ({ sendToUser: jest.fn(async () => ({ success: true })) }));

const stripeClient = require('../stripeClient');
const lobClient = require('../lobClient');
const notificationService = require('../notificationService');
const service = require('../fridgeMailService');
const { isDue, entitlement, buildFridgeBackHtml } = service;

const USER = 'parent-1';
const IMG = (n) => `https://storage.googleapis.com/bucket/drawing-${n}.jpg`;
const ADDRESS = { line1: '123 Main St', city: 'Charlotte', state: 'nc', zip: '28203' };
const plansOf = () => mockDb.rows('fridgeMailPlans');
const cardsOf = () => mockDb.rows('postcardOrders');
const MONDAY_NOON_ET = new Date('2026-09-21T16:00:00Z'); // Monday 12:00 America/New_York

beforeEach(() => {
  process.env.POSTCARD_MAIL_ENABLED = '1';
  delete process.env.FRIDGEMAIL_DRY_RUN;
  jest.clearAllMocks();
  for (const name of ['fridgeMailPlans', 'fridgeMailPackOrders', 'postcardOrders']) mockDb.rows(name).clear();
});

async function planWith({ recipients = 1, queue = 1, credits = 0, subscription = null, weekday = 1 } = {}) {
  for (let i = 0; i < recipients; i++) {
    await service.addRecipient({ userId: USER, name: `Grandma ${i + 1}`, relation: 'Grandma', address: ADDRESS });
  }
  for (let i = 0; i < queue; i++) {
    await service.enqueue({ userId: USER, imageUrl: IMG(i), childName: 'Maya', ageText: 'age 5', note: `Drawing ${i}` });
  }
  await service.setPlan({ userId: USER, weekday, familyName: 'the Sgrois' });
  const row = plansOf().get(USER);
  plansOf().set(USER, { ...row, cardsRemaining: credits, subscription });
  return plansOf().get(USER);
}

describe('isDue — the rolling week', () => {
  it('sends on the plan weekday in the plan timezone, never on other days', () => {
    const plan = { status: 'active', weekday: 1, timezone: 'America/New_York', lastSentAt: null };
    expect(isDue(plan, MONDAY_NOON_ET)).toBe(true);
    expect(isDue(plan, new Date('2026-09-22T16:00:00Z'))).toBe(false); // Tuesday
    expect(isDue({ ...plan, status: 'paused' }, MONDAY_NOON_ET)).toBe(false);
  });
  it('a Sunday plan in Los Angeles is Sunday there even when it is Monday in UTC', () => {
    const plan = { status: 'active', weekday: 0, timezone: 'America/Los_Angeles', lastSentAt: null };
    expect(isDue(plan, new Date('2026-09-21T03:00:00Z'))).toBe(true);  // Sun 20:00 LA
    expect(isDue(plan, new Date('2026-09-21T15:00:00Z'))).toBe(false); // Mon 08:00 LA
  });
  it('waits six days after the last card, so a re-run the same day never double-sends (incl. across DST)', () => {
    const plan = { status: 'active', weekday: 1, timezone: 'America/New_York', lastSentAt: '2026-10-26T15:00:10Z' };
    expect(isDue(plan, new Date('2026-10-26T18:00:00Z'))).toBe(false); // same Monday, later
    // Next Monday 2026-11-02 is after the US DST change (Nov 1): still due
    expect(isDue(plan, new Date('2026-11-02T15:00:00Z'))).toBe(true);
  });
});

describe('entitlement', () => {
  it('subscription slots cover recipients first, credits cover the rest', () => {
    const e = entitlement({ recipients: [1, 2, 3], cardsRemaining: 5, subscription: { status: 'active', quantity: 2 } });
    expect(e).toMatchObject({ recipients: 3, subscribedSlots: 2, credits: 5, covered: 3, creditsNeededPerWeek: 1, weeksOfCredits: 5 });
  });
  it('no subscription, no credits → nobody is covered', () => {
    expect(entitlement({ recipients: [1], cardsRemaining: 0, subscription: null }).covered).toBe(0);
  });
  it('a past_due subscription covers nothing', () => {
    expect(entitlement({ recipients: [1], cardsRemaining: 0, subscription: { status: 'past_due', quantity: 1 } }).covered).toBe(0);
  });
});

describe('weekly send', () => {
  it('mails one card per recipient, marks the drawing sent, spends credits after subscription slots', async () => {
    await planWith({ recipients: 2, queue: 2, credits: 3, subscription: { id: 'sub_1', status: 'active', quantity: 1 } });
    const summary = await service.runWeekly({ now: MONDAY_NOON_ET });
    expect(summary).toMatchObject({ plans: 1, sent: 2, failed: 0 });
    expect(lobClient.createPostcard).toHaveBeenCalledTimes(2);
    const plan = plansOf().get(USER);
    expect(plan.cardsRemaining).toBe(2); // one slot subscribed, one credit spent
    expect(plan.queue.filter((q) => q.sentAt).length).toBe(1);
    expect(plan.lastSentAt).toBe(MONDAY_NOON_ET.toISOString());
    const cards = [...cardsOf().values()];
    expect(cards.every((c) => c.kind === 'fridgemail' && c.prepaid === true && c.capturedAt === null && c.status === 'submitted')).toBe(true);
    expect(cards.filter((c) => c.usesCredit).length).toBe(1);
    // The Lob back carries who/when/note/from and no QR
    const back = lobClient.createPostcard.mock.calls[0][0].backHtml;
    expect(back).toContain('Maya, age 5');
    expect(back).toContain('Drawing 0');
    expect(back).toContain('From the Sgrois');
    expect(back).not.toContain('qr');
    expect(notificationService.sendToUser).toHaveBeenCalledWith(USER, expect.objectContaining({ type: 'fridgemail', title: 'Fridge Mail is on its way' }));
  });

  it('does not send twice in the same week, and sends the next drawing the following week', async () => {
    await planWith({ recipients: 1, queue: 2, credits: 5 });
    await service.runWeekly({ now: MONDAY_NOON_ET });
    await service.runWeekly({ now: new Date('2026-09-21T18:00:00Z') });
    expect(lobClient.createPostcard).toHaveBeenCalledTimes(1);
    await service.runWeekly({ now: new Date('2026-09-28T16:00:00Z') });
    expect(lobClient.createPostcard).toHaveBeenCalledTimes(2);
    expect(plansOf().get(USER).cardsRemaining).toBe(3);
    expect(plansOf().get(USER).queue.every((q) => q.sentAt)).toBe(true);
  });

  it('with no credit it nudges once and mails nothing; a pack purchase unblocks it', async () => {
    await planWith({ recipients: 1, queue: 1, credits: 0 });
    let summary = await service.runWeekly({ now: MONDAY_NOON_ET });
    expect(summary.skippedNoCredit).toBe(1);
    expect(lobClient.createPostcard).not.toHaveBeenCalled();
    expect(notificationService.sendToUser).toHaveBeenCalledWith(USER, expect.objectContaining({ title: 'Fridge Mail is out of cards' }));

    await service.createPackOrder({ userId: USER, orderId: 'ORDER-0001', packId: 'pack5' });
    await service.confirmPackOrder({ userId: USER, orderId: 'ORDER-0001' });
    expect(plansOf().get(USER).cardsRemaining).toBe(5);
    summary = await service.runWeekly({ now: MONDAY_NOON_ET });
    expect(summary.sent).toBe(1);
    expect(plansOf().get(USER).cardsRemaining).toBe(4);
  });

  it('nudges for an empty queue without spending anything', async () => {
    await planWith({ recipients: 1, queue: 0, credits: 5 });
    const summary = await service.runWeekly({ now: MONDAY_NOON_ET });
    expect(summary.skippedNoQueue).toBe(1);
    expect(plansOf().get(USER).cardsRemaining).toBe(5);
    expect(notificationService.sendToUser).toHaveBeenCalledWith(USER, expect.objectContaining({ title: 'Fridge Mail needs a drawing' }));
  });

  it('a Lob refusal marks the card rejected for review and keeps the credit', async () => {
    lobClient.createPostcard.mockRejectedValueOnce(new Error('undeliverable'));
    await planWith({ recipients: 1, queue: 1, credits: 2 });
    const summary = await service.runWeekly({ now: MONDAY_NOON_ET });
    expect(summary).toMatchObject({ sent: 0, failed: 1 });
    expect(plansOf().get(USER).cardsRemaining).toBe(2);
    expect(plansOf().get(USER).queue[0].sentAt).toBeNull(); // will retry next week
    expect([...cardsOf().values()][0]).toMatchObject({ status: 'rejected', needsReview: true });
  });

  it('refuses to run when printed mail is switched off', async () => {
    await planWith({ recipients: 1, queue: 1, credits: 2 });
    process.env.POSTCARD_MAIL_ENABLED = '0';
    const summary = await service.runWeekly({ now: MONDAY_NOON_ET });
    expect(summary.disabled).toBe(true);
    expect(lobClient.createPostcard).not.toHaveBeenCalled();
  });

  it('dry run writes the rows but never calls Lob', async () => {
    process.env.FRIDGEMAIL_DRY_RUN = '1';
    await planWith({ recipients: 1, queue: 1, credits: 2 });
    await service.runWeekly({ now: MONDAY_NOON_ET });
    expect(lobClient.createPostcard).not.toHaveBeenCalled();
    expect([...cardsOf().values()][0].lobPostcardId).toMatch(/^dryrun_/);
  });
});

describe('packs credit exactly once', () => {
  it('confirm and the webhook both crediting the same order adds the pack once', async () => {
    await planWith({ recipients: 1, queue: 0 });
    await service.createPackOrder({ userId: USER, orderId: 'ORDER-0002', packId: 'pack12' });
    await service.confirmPackOrder({ userId: USER, orderId: 'ORDER-0002' });
    await service.handleStripeEvent({ type: 'payment_intent.succeeded', data: { object: { object: 'payment_intent', metadata: { kind: 'fridgemail_pack', orderId: 'ORDER-0002' } } } });
    expect(plansOf().get(USER).cardsRemaining).toBe(12);
  });
  it('the webhook alone credits a pack whose confirm never arrived', async () => {
    await planWith({ recipients: 1, queue: 0 });
    await service.createPackOrder({ userId: USER, orderId: 'ORDER-0003', packId: 'pack5' });
    await service.handleStripeEvent({ type: 'payment_intent.succeeded', data: { object: { object: 'payment_intent', metadata: { kind: 'fridgemail_pack', orderId: 'ORDER-0003' } } } });
    expect(plansOf().get(USER).cardsRemaining).toBe(5);
  });
  it('a pack whose payment has not succeeded is not credited', async () => {
    stripeClient.getPaymentIntent.mockResolvedValueOnce({ id: 'pi', status: 'requires_payment_method' });
    await planWith({ recipients: 1, queue: 0 });
    await service.createPackOrder({ userId: USER, orderId: 'ORDER-0004', packId: 'pack5' });
    await expect(service.confirmPackOrder({ userId: USER, orderId: 'ORDER-0004' })).rejects.toMatchObject({ code: 'not_paid' });
  });
});

describe('subscription', () => {
  it('saves the card, starts billing for one slot per recipient, and follows recipient changes', async () => {
    await planWith({ recipients: 2, queue: 0 });
    const setup = await service.setupSubscription({ userId: USER, email: 'p@x.com', name: 'Parent' });
    expect(setup.setupIntentClientSecret).toBe('seti_1_secret');
    const plan = await service.startSubscription({ userId: USER, setupIntentId: 'seti_1' });
    expect(stripeClient.createSubscription).toHaveBeenCalledWith(expect.objectContaining({ quantity: 2, priceId: 'price_1', paymentMethodId: 'pm_1' }));
    expect(plan.subscription).toMatchObject({ status: 'active', quantity: 2, cancelAtPeriodEnd: false });
    expect(plan.entitlement.covered).toBe(2);

    await service.addRecipient({ userId: USER, name: 'Grandpa', relation: 'Grandpa', address: ADDRESS });
    expect(stripeClient.updateSubscriptionQuantity).toHaveBeenCalledWith({ subscriptionId: 'sub_1', quantity: 3 });
  });
  it('cancels at period end and reads back as still active until then', async () => {
    await planWith({ recipients: 1, queue: 0 });
    await service.setupSubscription({ userId: USER });
    await service.startSubscription({ userId: USER, setupIntentId: 'seti_1' });
    const plan = await service.cancelSubscription({ userId: USER });
    expect(plan.subscription).toMatchObject({ status: 'active', cancelAtPeriodEnd: true });
  });
  it('a failed invoice mirrors the status and tells the parent', async () => {
    await planWith({ recipients: 1, queue: 0 });
    await service.setupSubscription({ userId: USER });
    await service.startSubscription({ userId: USER, setupIntentId: 'seti_1' });
    stripeClient.getSubscription.mockResolvedValueOnce({ id: 'sub_1', status: 'past_due', items: { data: [{ id: 'si_1', quantity: 1 }] } });
    await service.handleStripeEvent({ type: 'invoice.payment_failed', data: { object: { object: 'invoice', customer: 'cus_1', subscription: 'sub_1' } } });
    expect(plansOf().get(USER).subscription.status).toBe('past_due');
    expect(notificationService.sendToUser).toHaveBeenCalledWith(USER, expect.objectContaining({ title: expect.stringContaining("didn't go through") }));
  });
});

describe('recipients and queue', () => {
  it('verifies the address and caps recipients at three', async () => {
    await planWith({ recipients: 3, queue: 0 });
    await expect(service.addRecipient({ userId: USER, name: 'One more', address: ADDRESS })).rejects.toMatchObject({ code: 'too_many_recipients' });
    const plan = plansOf().get(USER);
    expect(plan.recipients[0].address).toMatchObject({ line1: '123 MAIN ST', state: 'NC', zip: '28203' });
  });
  it('refuses an image that did not come from our upload, and keeps sent drawings out of reorder', async () => {
    await planWith({ recipients: 1, queue: 2, credits: 5 });
    await expect(service.enqueue({ userId: USER, imageUrl: 'https://evil.example/x.jpg', childName: 'M' })).rejects.toMatchObject({ code: 'bad_image' });
    await service.runWeekly({ now: MONDAY_NOON_ET });
    const pendingId = plansOf().get(USER).queue.find((q) => !q.sentAt).id;
    const plan = await service.reorderQueue({ userId: USER, ids: [pendingId] });
    expect(plan.queue[0].sentAt).toBeTruthy();
    expect(plan.queue[1].id).toBe(pendingId);
  });
});

describe('the card back', () => {
  it('reads who, when, the note and the family, escaped', () => {
    const html = buildFridgeBackHtml({ childName: 'Maya <3', ageText: 'age 5', dateText: 'September 21, 2026', note: 'Love & hugs', familyName: 'the Sgrois' });
    expect(html).toContain('Maya &lt;3, age 5');
    expect(html).toContain('September 21, 2026');
    expect(html).toContain('Love &amp; hugs');
    expect(html).toContain('From the Sgrois');
    expect(html).toContain('6.25in 4.25in');
    expect(html.length).toBeLessThan(10000);
  });
});
