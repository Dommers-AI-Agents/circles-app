// One webhook, two features: the router is the only thing keeping Fridge Mail
// payments out of the postcard handler (and vice versa).
jest.mock('../postcardMailService', () => ({ handleStripeEvent: jest.fn(async () => 'postcard') }));
jest.mock('../fridgeMailService', () => ({ PACK_KIND: 'fridgemail_pack', handleStripeEvent: jest.fn(async () => 'fridge') }));
const postcard = require('../postcardMailService');
const fridge = require('../fridgeMailService');
const { route } = require('../stripeEventRouter');

const event = (object, metadata) => ({ type: 'x', data: { object: { object, metadata } } });

beforeEach(() => jest.clearAllMocks());

test.each([
  ['payment_intent', { orderId: 'o1' }, 'postcard'],
  ['payment_intent', { orderId: 'p1', kind: 'fridgemail_pack' }, 'fridge'],
  ['payment_intent', { kind: 'something_else' }, 'postcard'],
  ['charge', { orderId: 'o1' }, 'postcard'],
  ['invoice', undefined, 'fridge'],
  ['subscription', { kind: 'fridgemail' }, 'fridge']
])('%s with metadata %j goes to %s', async (object, metadata, owner) => {
  const e = event(object, metadata);
  expect(await route(e)).toBe(owner);
  const handler = owner === 'fridge' ? fridge.handleStripeEvent : postcard.handleStripeEvent;
  const other = owner === 'fridge' ? postcard.handleStripeEvent : fridge.handleStripeEvent;
  expect(handler).toHaveBeenCalledWith(e);
  expect(other).not.toHaveBeenCalled();
});

test('unknown objects and malformed events are ignored, never dispatched', async () => {
  expect(await route(event('customer', {}))).toEqual({ ignored: true });
  expect(await route({})).toEqual({ ignored: true });
  expect(await route(null)).toEqual({ ignored: true });
  expect(postcard.handleStripeEvent).not.toHaveBeenCalled();
  expect(fridge.handleStripeEvent).not.toHaveBeenCalled();
});
