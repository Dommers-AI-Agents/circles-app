// Order ahead from a store's full menu, pay at pickup (2026-10-20).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
const mockLive = { value: true };
jest.mock('../ownerSubscriptionService', () => ({ isVenueBusinessLive: async () => mockLive.value }));
const mockPushes = [];
jest.mock('../notifyQuiet', () => ({ sendInBackground: (uid, n) => mockPushes.push({ uid, ...n }) }));
jest.mock('../emailService', () => ({ sendEmail: async () => ({}) }));

const rules = require('../orders/orderRules');
const orders = require('../orders/orderService');

const MENU = { sections: [
  { id: 's1', name: 'Pizza', items: [{ id: 'm', name: 'Margherita', price: '16' }, { id: 'd', name: 'Diavola', price: '$18.50' }] },
  { id: 's2', name: 'Pasta', items: [{ id: 'v', name: 'Vongole', price: 'MP' }] }
] };
const VENUE = { name: "Luigi's", ownerUserId: 'owner', managerUserIds: ['mgr'], storefront: { menu: MENU }, ordering: { enabled: true, leadMinutes: 15 } };

beforeEach(async () => {
  for (const c of ['orders', 'stickerVenues', 'users', 'dailyBudgets']) mockDb.rows(c).clear();
  mockPushes.length = 0;
  mockLive.value = true;
  await mockDb.collection('stickerVenues').doc('v1').set(VENUE);
  await mockDb.collection('users').doc('cust').set({ displayName: 'Ana', email: 'ana@example.com' });
  await mockDb.collection('users').doc('owner').set({ displayName: 'Lu', email: 'lu@example.com' });
});

describe('rules', () => {
  test('prices come from the menu, never the phone; the estimate skips "MP"', () => {
    const p = rules.priceCart(MENU, [{ itemId: 'm', qty: 2, name: 'free pizza', price: '0' }, { itemId: 'd', qty: 1 }, { itemId: 'v', qty: 1, note: 'extra garlic' }]);
    expect(p.lines.map((l) => [l.name, l.price, l.qty])).toEqual([['Margherita', '16', 2], ['Diavola', '$18.50', 1], ['Vongole', 'MP', 1]]);
    expect(p.estimate).toBe(50.5);
    expect(p.estimateIsPartial).toBe(true);
    expect(p.lines[2].note).toBe('extra garlic');
  });

  test('the place page lists every open order the customer has at that store, newest first', async () => {
    expect(await orders.openOrdersAtVenue('cust', 'v1')).toEqual([]);
    const first = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }], pickup: 'asap' });
    const second = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'd', qty: 1 }], pickup: 'asap' }, { now: new Date(Date.now() + 1000) });
    expect((await orders.openOrdersAtVenue('cust', 'v1')).map((o) => o.orderId)).toEqual([second.orderId, first.orderId]);
    expect(await orders.openOrdersAtVenue('cust', 'other-venue')).toEqual([]);
    expect(await orders.openOrdersAtVenue('someone-else', 'v1')).toEqual([]);
    await orders.cancel(second.orderId, 'cust');
    expect((await orders.openOrdersAtVenue('cust', 'v1')).map((o) => o.orderId)).toEqual([first.orderId]);
    await orders.cancel(first.orderId, 'cust');
    expect(await orders.openOrdersAtVenue('cust', 'v1')).toEqual([]);
  });

  test('the customer can mark a ready (or accepted) order picked up; the counter hears, a stranger cannot', async () => {
    const placed = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }], pickup: 'asap' });
    await expect(orders.pickedUp(placed.orderId, 'cust')).rejects.toMatchObject({ code: 'order_moved_on' });
    await orders.storeAction('v1', placed.orderId, 'ready', { actorId: 'owner' });
    mockPushes.length = 0;
    await expect(orders.pickedUp(placed.orderId, 'someone-else')).rejects.toMatchObject({ code: 'order_not_found' });
    const done = await orders.pickedUp(placed.orderId, 'cust');
    expect(done.status).toBe('picked_up');
    expect(mockPushes.map((p) => [p.uid, p.type])).toEqual([['owner', 'order_new'], ['mgr', 'order_new']]);
    expect(mockPushes[0].title).toBe('Picked up: Ana');
    expect(await orders.openOrdersAtVenue('cust', 'v1')).toEqual([]);
  });

  test('a removed item, a silly quantity or an empty cart is refused', () => {
    expect(() => rules.priceCart(MENU, [{ itemId: 'gone', qty: 1 }])).toThrow(expect.objectContaining({ code: 'menu_changed' }));
    expect(() => rules.priceCart(MENU, [{ itemId: 'm', qty: 0 }])).toThrow(expect.objectContaining({ code: 'bad_quantity' }));
    expect(() => rules.priceCart(MENU, [{ itemId: 'm', qty: 99 }])).toThrow(expect.objectContaining({ code: 'bad_quantity' }));
    expect(() => rules.priceCart(MENU, [])).toThrow(expect.objectContaining({ code: 'empty_order' }));
  });

  test('prices that read as a number, and ones that don’t', () => {
    expect(rules.priceValue('16')).toBe(16);
    expect(rules.priceValue('$12.50')).toBe(12.5);
    expect(rules.priceValue('12,50')).toBe(12.5);
    expect(rules.priceValue('8 / 14')).toBeNull();
    expect(rules.priceValue('glass 10 · bottle 36')).toBeNull();
  });

  test('pickup: as soon as possible, or later within the lead time and a day', () => {
    const now = new Date('2026-10-20T16:00:00Z');
    expect(rules.pickupFor('asap', { now })).toEqual({ asap: true, at: null });
    expect(rules.pickupFor('2026-10-20T17:00:00Z', { now }).at).toBe('2026-10-20T17:00:00.000Z');
    expect(() => rules.pickupFor('2026-10-20T16:05:00Z', { now })).toThrow(expect.objectContaining({ code: 'pickup_too_soon' }));
    expect(() => rules.pickupFor('2026-10-22T16:00:00Z', { now })).toThrow(expect.objectContaining({ code: 'pickup_too_late' }));
  });

  test('ordering shows only when on, with a menu, while Business is live', () => {
    expect(rules.orderingFor(VENUE, { live: true })).toEqual({ enabled: true, leadMinutes: 15, note: null });
    expect(rules.orderingFor(VENUE, { live: false })).toBeNull();
    expect(rules.orderingFor({ ...VENUE, ordering: { enabled: false } }, { live: true })).toBeNull();
    expect(rules.orderingFor({ ...VENUE, storefront: { menu: { sections: [] } } }, { live: true })).toBeNull();
  });

  test('who may do what, and only from the right status', () => {
    expect(rules.transition({ status: 'placed' }, 'accept', 'store')).toBe('accepted');
    expect(() => rules.transition({ status: 'placed' }, 'accept', 'customer')).toThrow(expect.objectContaining({ code: 'bad_action' }));
    expect(() => rules.transition({ status: 'accepted' }, 'cancel', 'customer')).toThrow(expect.objectContaining({ code: 'order_moved_on' }));
    expect(rules.transition({ status: 'ready' }, 'picked_up', 'store')).toBe('picked_up');
  });
});

describe('the order flow', () => {
  test('place → the team hears → accept with a ready time → ready → picked up, the customer hears each step', async () => {
    const placed = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 2 }], note: 'Cut in squares', pickup: 'asap' });
    expect(placed).toMatchObject({ status: 'placed', customerName: 'Ana', venueName: "Luigi's", estimate: 32, note: 'Cut in squares' });
    expect(mockPushes.filter((p) => p.type === 'order_new').map((p) => p.uid).sort()).toEqual(['mgr', 'owner']);

    const accepted = await orders.storeAction('v1', placed.orderId, 'accept', { actorId: 'owner', readyInMinutes: 20 });
    expect(accepted.status).toBe('accepted');
    expect(new Date(accepted.readyAt).getTime()).toBeGreaterThan(Date.now() + 19 * 60000);
    expect(mockPushes.at(-1)).toMatchObject({ uid: 'cust', type: 'order_update' });

    await orders.storeAction('v1', placed.orderId, 'ready', { actorId: 'mgr' });
    expect(mockPushes.at(-1).title).toMatch(/ready/);
    const done = await orders.storeAction('v1', placed.orderId, 'picked_up', { actorId: 'owner' });
    expect(done.status).toBe('picked_up');
    expect((await orders.mine('cust'))[0].status).toBe('picked_up');
  });

  test('only the customer and the store’s team can see an order', async () => {
    const placed = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }], pickup: 'asap' });
    await expect(orders.get(placed.orderId, 'mgr')).resolves.toMatchObject({ orderId: placed.orderId });
    await expect(orders.get(placed.orderId, 'stranger')).rejects.toMatchObject({ code: 'order_not_found' });
    await expect(orders.storeAction('other-venue', placed.orderId, 'accept', { actorId: 'x' })).rejects.toMatchObject({ code: 'order_not_found' });
  });

  test('the customer can cancel until it’s accepted; the team is told', async () => {
    const placed = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'd', qty: 1 }], pickup: 'asap' });
    const cancelled = await orders.cancel(placed.orderId, 'cust');
    expect(cancelled.status).toBe('cancelled');
    expect(mockPushes.at(-1)).toMatchObject({ type: 'order_new' });
    const again = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'd', qty: 1 }], pickup: 'asap' });
    await orders.storeAction('v1', again.orderId, 'accept', { actorId: 'owner', readyInMinutes: 10 });
    await expect(orders.cancel(again.orderId, 'cust')).rejects.toMatchObject({ code: 'order_moved_on' });
  });

  test('a decline carries the store’s reason to the customer', async () => {
    const placed = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }], pickup: 'asap' });
    await orders.storeAction('v1', placed.orderId, 'decline', { actorId: 'owner', reason: 'Out of dough tonight' });
    expect(mockPushes.at(-1)).toMatchObject({ uid: 'cust', body: 'Out of dough tonight' });
  });

  test('refused: ordering off, Business lapsed, own store, too many open orders', async () => {
    mockLive.value = false;
    await expect(orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }] })).rejects.toMatchObject({ code: 'ordering_off' });
    mockLive.value = true;
    await expect(orders.place({ customerId: 'mgr', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }] })).rejects.toMatchObject({ code: 'own_store' });
    await expect(orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }], test: true })).rejects.toMatchObject({ code: 'not_your_store' });
    for (let i = 0; i < 3; i += 1) await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }] });
    await expect(orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }] })).rejects.toMatchObject({ code: 'too_many_open' });
  });

  test('nobody answers in 30 minutes: expired, and the customer is told not to head over', async () => {
    const placed = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }] });
    const later = new Date(Date.now() + 31 * 60000);
    const result = await orders.sweep({ db: mockDb, now: later });
    expect(result.expired).toBe(1);
    expect((await orders.get(placed.orderId, 'cust')).status).toBe('expired');
    expect(mockPushes.at(-1)).toMatchObject({ uid: 'cust', type: 'order_update' });
  });

  test('turning ordering on needs a menu', async () => {
    await expect(orders.saveSettings({ venueId: 'v1', storefront: {} }, { enabled: true })).rejects.toMatchObject({ code: 'no_menu' });
    const saved = await orders.saveSettings({ venueId: 'v1', ...VENUE }, { enabled: true, leadMinutes: 500 });
    expect(saved).toMatchObject({ enabled: true, leadMinutes: 120 });
  });

  test('the store\u2019s team can place a TEST order, even before switching ordering on; no email, no allowance spent', async () => {
    await mockDb.collection('stickerVenues').doc('v1').set({ ...VENUE, ordering: { enabled: false } });
    const t = await orders.place({ customerId: 'owner', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }], test: true });
    expect(t).toMatchObject({ test: true, status: 'placed' });
    expect(mockPushes.find((p) => p.type === 'order_new').title).toMatch(/^Test order/);
    expect(mockDb.rows('dailyBudgets').size).toBe(0);
    // ...but not without Business, and customers still can't order while it's off
    mockLive.value = false;
    await expect(orders.place({ customerId: 'owner', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }], test: true })).rejects.toMatchObject({ code: 'business_required' });
    mockLive.value = true;
    await expect(orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }] })).rejects.toMatchObject({ code: 'ordering_off' });
  });

  test('newCount: orders waiting to be accepted, only while ordering is on', async () => {
    await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'm', qty: 1 }] });
    const venue = (await mockDb.collection('stickerVenues').doc('v1').get()).data();
    const n = await orders.newCount({ ...venue, venueId: 'v1' }, { db: mockDb });
    expect(n).toBeGreaterThanOrEqual(1);
    expect(await orders.newCount({ ...venue, venueId: 'v1', ordering: { enabled: false } }, { db: mockDb })).toBe(0);
    expect(await orders.newCount(null, { db: mockDb })).toBe(0);
  });
});
