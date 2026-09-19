// The money wrapper: every call must carry the flags the order machine's
// design depends on (manual capture, no redirects, idempotency keys) and the
// SDK must be constructed lazily so a boot without STRIPE_SECRET_KEY works.
const mockSdk = {
  paymentIntents: { create: jest.fn(async (p) => ({ id: 'pi_1', ...p })), retrieve: jest.fn(async (id) => ({ id })), capture: jest.fn(async (id) => ({ id, status: 'succeeded' })), cancel: jest.fn(async (id) => ({ id, status: 'canceled' })) },
  refunds: { create: jest.fn(async (p) => ({ id: 're_1', ...p })) },
  customers: { retrieve: jest.fn(), create: jest.fn(async (p) => ({ id: 'cus_new', ...p })), update: jest.fn(async (id, p) => ({ id, ...p })) },
  setupIntents: { create: jest.fn(async (p) => ({ id: 'seti_1', ...p })), retrieve: jest.fn(async (id) => ({ id })) },
  prices: { list: jest.fn(async () => ({ data: [] })) },
  subscriptions: { create: jest.fn(async (p) => ({ id: 'sub_1', ...p })), retrieve: jest.fn(), update: jest.fn(async (id, p) => ({ id, ...p })) },
  webhooks: { constructEvent: jest.fn((body, sig, secret) => ({ body, sig, secret })) }
};
const mockStripeFactory = jest.fn(() => mockSdk);
jest.mock('stripe', () => mockStripeFactory);

const ENV = { ...process.env };
let stripeClient;

beforeEach(() => {
  jest.resetModules();
  jest.clearAllMocks();
  process.env = { ...ENV, STRIPE_SECRET_KEY: 'sk_test_x', STRIPE_WEBHOOK_SECRET: 'whsec_x' };
  stripeClient = require('../stripeClient');
});
afterAll(() => { process.env = ENV; });

test('disabled without a secret key: no SDK is built and calls throw', async () => {
  delete process.env.STRIPE_SECRET_KEY;
  expect(stripeClient.isEnabled()).toBe(false);
  await expect(stripeClient.getPaymentIntent('pi')).rejects.toThrow('STRIPE_SECRET_KEY');
  expect(mockStripeFactory).not.toHaveBeenCalled();
});

test('the SDK is built once, lazily, with the key', async () => {
  expect(mockStripeFactory).not.toHaveBeenCalled();
  await stripeClient.getPaymentIntent('a');
  await stripeClient.getPaymentIntent('b');
  expect(mockStripeFactory).toHaveBeenCalledTimes(1);
  expect(mockStripeFactory).toHaveBeenCalledWith('sk_test_x');
});

test('postcard authorization is a manual-capture hold with no redirects, keyed on the order', async () => {
  await stripeClient.createAuthorization({ orderId: 'o1', userId: 'u1', amountCents: 299, description: 'Postcard' });
  const [params, options] = mockSdk.paymentIntents.create.mock.calls[0];
  expect(params).toMatchObject({
    amount: 299, currency: 'usd', capture_method: 'manual',
    automatic_payment_methods: { enabled: true, allow_redirects: 'never' },
    metadata: { orderId: 'o1', userId: 'u1' }
  });
  expect(options).toEqual({ idempotencyKey: 'postcard-order-o1' });
});

test('capture is idempotent per intent; void and refund hit the right endpoints', async () => {
  await stripeClient.capture('pi_9');
  expect(mockSdk.paymentIntents.capture).toHaveBeenCalledWith('pi_9', {}, { idempotencyKey: 'postcard-capture-pi_9' });
  await stripeClient.voidAuthorization('pi_9');
  expect(mockSdk.paymentIntents.cancel).toHaveBeenCalledWith('pi_9');
  await stripeClient.refund('pi_9');
  expect(mockSdk.refunds.create).toHaveBeenCalledWith({ payment_intent: 'pi_9' });
});

test('fridge pack payment captures immediately and is keyed on kind + order', async () => {
  await stripeClient.createPayment({ orderId: 'p1', userId: 'u1', amountCents: 1500, description: 'Pack', kind: 'fridgemail_pack' });
  const [params, options] = mockSdk.paymentIntents.create.mock.calls[0];
  expect(params.capture_method).toBeUndefined();
  expect(params.metadata).toEqual({ orderId: 'p1', userId: 'u1', kind: 'fridgemail_pack' });
  expect(options).toEqual({ idempotencyKey: 'fridgemail_pack-p1' });
});

describe('ensureCustomer', () => {
  test('reuses a live existing customer', async () => {
    mockSdk.customers.retrieve.mockResolvedValueOnce({ id: 'cus_old' });
    expect(await stripeClient.ensureCustomer({ existingId: 'cus_old', userId: 'u1' })).toEqual({ id: 'cus_old' });
    expect(mockSdk.customers.create).not.toHaveBeenCalled();
  });
  test('mints a new one when the stored id is deleted or unknown', async () => {
    mockSdk.customers.retrieve.mockResolvedValueOnce({ id: 'cus_old', deleted: true });
    expect((await stripeClient.ensureCustomer({ existingId: 'cus_old', userId: 'u1', email: 'a@b.c' })).id).toBe('cus_new');
    mockSdk.customers.retrieve.mockRejectedValueOnce(new Error('No such customer'));
    expect((await stripeClient.ensureCustomer({ existingId: 'cus_gone', userId: 'u1' })).id).toBe('cus_new');
    expect(mockSdk.customers.create).toHaveBeenLastCalledWith({ email: undefined, name: undefined, metadata: { userId: 'u1' } });
  });
});

test('subscriptions: setup intent is off-session, first charge must succeed, quantity change has no proration', async () => {
  await stripeClient.createSetupIntent({ customerId: 'cus_1', userId: 'u1', kind: 'fridgemail' });
  expect(mockSdk.setupIntents.create.mock.calls[0][0]).toMatchObject({ customer: 'cus_1', usage: 'off_session', automatic_payment_methods: { allow_redirects: 'never' } });

  await stripeClient.createSubscription({ customerId: 'cus_1', priceId: 'price_1', quantity: 2, paymentMethodId: 'pm_1', userId: 'u1', kind: 'fridgemail' });
  const [subParams, subOptions] = mockSdk.subscriptions.create.mock.calls[0];
  expect(subParams).toMatchObject({ customer: 'cus_1', items: [{ price: 'price_1', quantity: 2 }], default_payment_method: 'pm_1', payment_behavior: 'error_if_incomplete' });
  expect(subOptions.idempotencyKey).toMatch(/^fridgemail-sub-u1-\d+$/);

  mockSdk.subscriptions.retrieve.mockResolvedValueOnce({ id: 'sub_1', items: { data: [{ id: 'si_1' }] } });
  await stripeClient.updateSubscriptionQuantity({ subscriptionId: 'sub_1', quantity: 3 });
  expect(mockSdk.subscriptions.update).toHaveBeenCalledWith('sub_1', { items: [{ id: 'si_1', quantity: 3 }], proration_behavior: 'none' });

  mockSdk.subscriptions.retrieve.mockResolvedValueOnce({ id: 'sub_2', items: { data: [] } });
  await expect(stripeClient.updateSubscriptionQuantity({ subscriptionId: 'sub_2', quantity: 1 })).rejects.toThrow('no items');

  await stripeClient.cancelSubscriptionAtPeriodEnd('sub_1');
  expect(mockSdk.subscriptions.update).toHaveBeenLastCalledWith('sub_1', { cancel_at_period_end: true });
  await stripeClient.resumeSubscription('sub_1');
  expect(mockSdk.subscriptions.update).toHaveBeenLastCalledWith('sub_1', { cancel_at_period_end: false });
});

test('priceByLookupKey returns the first active price or null', async () => {
  expect(await stripeClient.priceByLookupKey('fm_monthly')).toBeNull();
  mockSdk.prices.list.mockResolvedValueOnce({ data: [{ id: 'price_9' }] });
  expect(await stripeClient.priceByLookupKey('fm_monthly')).toEqual({ id: 'price_9' });
  expect(mockSdk.prices.list).toHaveBeenCalledWith({ lookup_keys: ['fm_monthly'], active: true, limit: 1 });
});

test('constructEvent verifies against the configured secret and refuses without one', () => {
  expect(stripeClient.constructEvent('raw', 'sig')).toEqual({ body: 'raw', sig: 'sig', secret: 'whsec_x' });
  delete process.env.STRIPE_WEBHOOK_SECRET;
  expect(() => stripeClient.constructEvent('raw', 'sig')).toThrow('STRIPE_WEBHOOK_SECRET');
});
