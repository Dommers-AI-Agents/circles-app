// Guest orders from a store's web page (services/orders/webOrderService, 2026-10-28).
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
const mockLive = { value: true };
jest.mock('../ownerSubscriptionService', () => ({ isVenueBusinessLive: async () => mockLive.value }));
const mockPushes = [];
jest.mock('../notifyQuiet', () => ({ sendInBackground: (uid, n) => mockPushes.push({ uid, ...n }) }));
const mockMails = [];
jest.mock('../emailService', () => ({ sendEmail: async (m) => { mockMails.push(m); return {}; } }));
process.env.JWT_SECRET = 'test-secret';

const guest = require('../orders/guestRules');
const web = require('../orders/webOrderService');
const orders = require('../orders/orderService');
const { formatHours } = require('../../utils/hoursText');

const MENU = { sections: [
  { id: 's1', name: 'Pastries', items: [{ id: 'c', name: 'Croissant', price: '4', description: 'Butter' }, { id: 'k', name: 'Kouign-amann', price: '$5.50' }] },
  { id: 's2', name: 'Specials', items: [{ id: 'm', name: 'Market cake', price: 'MP' }] },
  { id: 's3', name: 'Empty', items: [] }
] };
const VENUE = { venueName: 'Test Bakery', placeName: 'Test Bakery', placeAddress: '1 Elm St, Charlotte, NC 28202', category: 'cafe',
  ownerUserId: 'owner', managerUserIds: ['mgr'], globalPlaceId: 'gp1', slug: 'test-bakery', windowCode: 'WIN123', registerCode: 'REG123',
  storefront: { menu: MENU }, ordering: { enabled: true, leadMinutes: 15, note: 'Ring the bell' } };
const PLACE = { coverPhotoUrl: 'https://img/cover.jpg', googleData: { phone: '(704) 555-0199', website: 'https://bakery.example', openingHours: [
  { day: 0, isClosed: true }, { day: 1, open: '07:00', close: '15:30' }, { day: 2, hours: '7 AM–12 PM, 2–6 PM' }
] } };
const GUEST = { name: 'Ana Ruiz', phone: '(704) 555-0100', email: 'ana@example.com' };
const flush = () => new Promise((r) => setTimeout(r, 0));

beforeEach(async () => {
  for (const c of ['orders', 'stickerVenues', 'venueSlugs', 'globalPlaces', 'users', 'dailyBudgets']) mockDb.rows(c).clear();
  mockPushes.length = 0; mockMails.length = 0; mockLive.value = true;
  await mockDb.collection('stickerVenues').doc('v1').set(VENUE);
  await mockDb.collection('venueSlugs').doc('test-bakery').set({ venueId: 'v1', retiredAt: null });
  await mockDb.collection('globalPlaces').doc('gp1').set(PLACE);
  await mockDb.collection('users').doc('owner').set({ displayName: 'Wes', email: 'owner@example.com' });
});

describe('guest rules', () => {
  test('phones become E.164, or are refused', () => {
    expect(guest.normalizePhone('(704) 555-0100')).toBe('+17045550100');
    expect(guest.normalizePhone('1 704 555 0100')).toBe('+17045550100');
    expect(guest.normalizePhone('+44 20 7946 0958')).toBe('+442079460958');
    expect(() => guest.normalizePhone('555-0100')).toThrow(expect.objectContaining({ code: 'bad_phone' }));
    expect(guest.displayPhone('+17045550100')).toBe('(704) 555-0100');
  });
  test('a guest needs a name and a phone; a bad email is refused, none is fine', () => {
    expect(guest.cleanGuest(GUEST)).toEqual({ name: 'Ana Ruiz', phone: '+17045550100', email: 'ana@example.com' });
    expect(guest.cleanGuest({ name: ' Bo ', phone: '7045550100', email: '' }).email).toBeNull();
    expect(() => guest.cleanGuest({ name: 'A', phone: '7045550100' })).toThrow(expect.objectContaining({ code: 'bad_name' }));
    expect(() => guest.cleanGuest({ name: 'Ana', phone: '7045550100', email: 'nope' })).toThrow(expect.objectContaining({ code: 'bad_email' }));
  });
  test('the limit key hides the number', () => {
    const k = guest.guestKeyFor('+17045550100');
    expect(k).not.toContain('704');
    expect(guest.guestKeyFor('+17045550100')).toBe(k);
    expect(guest.guestKeyFor('+17045550101')).not.toBe(k);
  });
});

describe('the page', () => {
  test('a store with a menu on Business has a page; hours, phone and cover come from its place record', async () => {
    const page = await web.pageFor('test-bakery');
    const p = web.projection(page.venue, page.place, { live: page.live, ordering: page.ordering });
    expect(p.name).toBe('Test Bakery');
    expect(p.phone).toBe('(704) 555-0199');
    expect(p.coverPhotoUrl).toBe('https://img/cover.jpg');
    expect(p.hours[0]).toEqual({ day: 0, label: 'Sun', text: 'Closed' });
    expect(p.hours[1].text).toBe('7 AM–3:30 PM');
    expect(p.hours[2].text).toBe('7 AM–12 PM, 2–6 PM');
    expect(p.hours[3].text).toBe('Closed');
    expect(p.ordering).toEqual({ enabled: true, leadMinutes: 15, note: 'Ring the bell' });
    expect(p.menu.sections.map((s) => s.name)).toEqual(['Pastries', 'Specials']);
    expect(JSON.stringify(p)).not.toMatch(/WIN123|REG123|ownerUserId|mgr/);
  });
  test('ordering off: the page stays (menu only); not on Business or no menu: no page', async () => {
    await mockDb.collection('stickerVenues').doc('v1').set({ ...VENUE, ordering: { enabled: false } });
    let page = await web.pageFor('test-bakery');
    expect(page.ordering).toBeNull();
    mockLive.value = false;
    expect(await web.pageFor('test-bakery')).toBeNull();
    mockLive.value = true;
    await mockDb.collection('stickerVenues').doc('v1').set({ ...VENUE, storefront: { menu: { sections: [] } } });
    expect(await web.pageFor('test-bakery')).toBeNull();
    expect(await web.pageFor('no-such')).toBeNull();
  });
  test('a retired address redirects to the current one', async () => {
    await mockDb.collection('venueSlugs').doc('old-bakery').set({ venueId: 'v1', retiredAt: '2026-10-01T00:00:00.000Z' });
    expect(await web.pageFor('old-bakery')).toEqual({ redirectTo: 'test-bakery' });
  });
  test('hours formatter copes with odd rows', () => {
    expect(formatHours(null)).toBeNull();
    expect(formatHours([{ day: 9, open: '09:00' }])).toBeNull();
    expect(formatHours([{ day: 5, open: '0900', close: '1700' }])[5].text).toBe('9 AM–5 PM');
  });
});

describe('placing as a guest', () => {
  const place = (over = {}) => web.placeGuest({ slug: 'test-bakery', guest: GUEST, items: [{ itemId: 'c', qty: 2, note: 'warm' }, { itemId: 'm', qty: 1 }], note: 'thanks', pickup: 'asap', ...over });

  test('the order is written for the store’s queue with the guest’s contact, and the app sees a string customerId', async () => {
    const res = await place();
    expect(res.order.customerId).toBe('guest');
    expect(res.order.channel).toBe('web');
    expect(res.order.customer).toBeUndefined();
    expect(res.order.venuePhone).toBe('(704) 555-0199');
    expect(res.order.estimate).toBe(8);
    expect(res.order.estimateIsPartial).toBe(true);
    expect(res.statusUrl).toBe(`https://order.favcircles.com/o/${res.order.orderId}?t=${res.token}`);
    const doc = (await mockDb.collection('orders').doc(res.order.orderId).get()).data();
    expect(doc.customerId).toBeNull();
    expect(doc.customerName).toBe('Ana Ruiz');
    expect(doc.customer).toEqual({ name: 'Ana Ruiz', phone: '+17045550100', email: 'ana@example.com' });
    expect(doc.guestKey).toBe(guest.guestKeyFor('+17045550100'));
    expect(doc.slug).toBe('test-bakery');
    expect(doc.history[0].by).toBe('guest');
    // The team is told it's a web order and gets the phone; the guest gets a receipt
    await flush();
    expect(mockPushes.map((p) => p.uid).sort()).toEqual(['mgr', 'owner']);
    expect(mockPushes[0].title).toBe('New web order: Ana Ruiz');
    expect(mockPushes[0].body).toContain('+17045550100');
    expect(mockMails.map((m) => m.to).sort()).toEqual(['ana@example.com', 'owner@example.com']);
    expect(mockMails.find((m) => m.to === 'ana@example.com').html).toContain(res.statusUrl);
    // The store's list carries the contact; the guest's own view never carries guestKey
    const list = await orders.forVenue('v1');
    expect(list[0].customer).toEqual({ name: 'Ana Ruiz', phone: '+17045550100', email: 'ana@example.com' });
    expect(list[0].customerId).toBe('guest');
    const status = await web.status(res.order.orderId, res.token);
    expect(status.customer).toBeUndefined();
    expect(status.guestKey).toBeUndefined();
    expect(status.status).toBe('placed');
  });

  test('without an email nothing is mailed to the guest; the team still hears', async () => {
    await place({ guest: { name: 'Bo Li', phone: '7045550101' } });
    await flush();
    expect(mockMails.map((m) => m.to)).toEqual(['owner@example.com']);
  });

  test('a filled honeypot writes nothing; ordering off, a bad cart or a bad phone are refused before any limit is spent', async () => {
    expect(await place({ honeypot: 'http://spam' })).toEqual({ ignored: true });
    expect(mockDb.rows('orders').size).toBe(0);
    await expect(place({ items: [{ itemId: 'gone', qty: 1 }] })).rejects.toMatchObject({ code: 'menu_changed' });
    await expect(place({ guest: { name: 'Ana', phone: '12' } })).rejects.toMatchObject({ code: 'bad_phone' });
    expect(mockDb.rows('dailyBudgets').size).toBe(0);
    await mockDb.collection('stickerVenues').doc('v1').set({ ...VENUE, ordering: { enabled: false } });
    await expect(place()).rejects.toMatchObject({ code: 'ordering_off' });
    await expect(web.placeGuest({ slug: 'nope', guest: GUEST, items: [{ itemId: 'c', qty: 1 }], pickup: 'asap' })).rejects.toMatchObject({ code: 'store_not_found' });
  });

  test('one phone: three open orders, then no more; cancelling frees a slot', async () => {
    const a = await place(); await place(); await place();
    await expect(place()).rejects.toMatchObject({ code: 'too_many_open' });
    await web.cancel(a.order.orderId, a.token);
    await expect(place()).resolves.toBeTruthy();
    await expect(place({ guest: { ...GUEST, phone: '7045550199' } })).resolves.toBeTruthy();
  });

  test('the token opens one order only; the store’s steps reach the guest by email, never by push', async () => {
    const res = await place();
    const other = await place({ guest: { ...GUEST, phone: '7045550198' } });
    await flush(); mockPushes.length = 0; mockMails.length = 0;
    expect(web.verifyOrderToken(res.token, res.order.orderId)).toBe(true);
    expect(web.verifyOrderToken(res.token, other.order.orderId)).toBe(false);
    await expect(web.status(res.order.orderId, 'nope')).rejects.toMatchObject({ code: 'order_not_found' });
    await expect(web.status(other.order.orderId, res.token)).rejects.toMatchObject({ code: 'order_not_found' });
    // An app customer's order can't be read with a guest token even if it matched
    await mockDb.collection('users').doc('cust').set({ displayName: 'App User' });
    const appOrder = await orders.place({ customerId: 'cust', venueId: 'v1', items: [{ itemId: 'c', qty: 1 }], pickup: 'asap' });
    await expect(web.status(appOrder.orderId, web.signOrderToken(appOrder.orderId))).rejects.toMatchObject({ code: 'order_not_found' });
    await flush(); mockMails.length = 0; // the app order's own team email

    await orders.storeAction('v1', res.order.orderId, 'accept', { actorId: 'owner', readyInMinutes: 20 });
    await flush();
    expect(mockPushes.filter((p) => p.type === 'order_update')).toEqual([]);
    expect(mockPushes.some((p) => p.uid === null)).toBe(false);
    expect(mockMails.length).toBe(1);
    expect(mockMails[0].to).toBe('ana@example.com');
    expect(mockMails[0].subject).toBe('Test Bakery accepted your order');
    expect(mockMails[0].html).toContain(`/o/${res.order.orderId}?t=`);
    await orders.storeAction('v1', res.order.orderId, 'decline', { actorId: 'owner', reason: 'Out of croissants' });
    await flush();
    expect(mockMails[1].subject).toBe('Test Bakery couldn’t take your order');
    expect(mockMails[1].html).toContain('Out of croissants');
    expect((await web.status(res.order.orderId, res.token)).status).toBe('declined');
  });

  test('the sweep expires an unanswered guest order and emails them, with no push', async () => {
    const res = await place();
    await flush(); mockPushes.length = 0; mockMails.length = 0;
    const later = new Date(Date.now() + 31 * 60000);
    expect(await orders.sweep({ now: later })).toEqual({ expired: 1, closed: 0 });
    await flush();
    expect(mockPushes).toEqual([]);
    expect(mockMails.length).toBe(1);
    expect(mockMails[0].subject).toContain('didn’t answer');
    expect((await web.status(res.order.orderId, res.token)).status).toBe('expired');
  });

  test('a guest can cancel only while the order is waiting', async () => {
    const res = await place();
    await orders.storeAction('v1', res.order.orderId, 'accept', { actorId: 'owner', readyInMinutes: 10 });
    await expect(web.cancel(res.order.orderId, res.token)).rejects.toMatchObject({ code: 'order_moved_on' });
  });
});
