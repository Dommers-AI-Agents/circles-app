// Points for delivery orders: a receipt, checked, paid once (2026-11-06)
const tables = {};
const table = (name) => (tables[name] = tables[name] || {});
const docRef = (name, id) => ({
  id,
  get: async () => ({ id, exists: !!table(name)[id], data: () => table(name)[id] }),
  set: async (data) => { table(name)[id] = { ...data }; },
  create: async (data) => {
    if (table(name)[id]) { const e = new Error('already exists'); e.code = 6; throw e; }
    table(name)[id] = { ...data };
  },
  update: async (u) => { table(name)[id] = { ...table(name)[id], ...u }; },
  delete: async () => { delete table(name)[id]; }
});
const mockDb = {
  collection: (name) => ({ doc: (id) => docRef(name, id) }),
  runTransaction: async (fn) => fn({
    get: (ref) => ref.get(),
    update: (ref, u) => { ref.update(u); }
  })
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
jest.mock('sharp', () => () => {
  const chain = { rotate: () => chain, resize: () => chain, jpeg: () => chain, toBuffer: async () => Buffer.from('jpg') };
  return chain;
});
const mockSaved = [];
jest.mock('firebase-admin/storage', () => ({
  getStorage: () => ({ bucket: () => ({ file: (path) => ({ save: async () => { mockSaved.push(path); } }) }) })
}));
const mockPush = jest.fn();
jest.mock('../notifyQuiet', () => ({ sendInBackground: (...a) => mockPush(...a) }));
jest.mock('../venueHelpers', () => ({ venueManagerIds: (v) => v.managerUserIds || [] }));
jest.mock('../ownerSubscriptionService', () => ({ registerScanEarns: async (v) => ({ earns: v.paused !== true }) }));
jest.mock('../storeCustomers', () => ({ isRemoved: async (userId) => userId === 'banned' }));
jest.mock('../dailyBudget', () => ({ consume: async () => ({ allowed: true }) }));
jest.mock('../scanAttempts', () => ({ recordScanAttempt: async () => null }));
// The visit award's daily key, as rewardService keeps it
const mockAwards = [];
jest.mock('../rewardService', () => ({
  awardVenueVisit: async (userId, venue, { via, day }) => {
    const key = `visit:${userId}:${venue.venueId}:${day}`;
    if (mockAwards.some((a) => a.key === key)) return { awarded: false, duplicate: true, reason: 'already_today' };
    mockAwards.push({ key, via });
    return { awarded: true, points: 10 };
  },
  getBalance: async () => ({ venueBalances: [{ venueId: 'v1', points: 30 }] })
}));

const rc = require('../receiptClaims');

const NOW = new Date('2026-11-06T18:00:00Z');
const receipt = (over = {}) => ({
  image: Buffer.from('photo').toString('base64'),
  receipt: { text: 'DoorDash\nILIOS CRAFTED GREEK - SOUTHEND\nOrder #A1B2-C3D4\nNov 5, 2026', orderDate: '2026-11-05', orderNumber: '#a1b2-c3d4', deliveryApp: 'DoorDash', ...over }
});

beforeEach(() => {
  Object.keys(tables).forEach((k) => delete tables[k]);
  table('stickerVenues').v1 = { venueName: 'Ilios Crafted Greek', ownerUserId: 'owner', managerUserIds: ['mgr'], deliveryReceipts: 'approve' };
  mockAwards.length = 0;
  mockSaved.length = 0;
  mockPush.mockClear();
});

describe('checks', () => {
  test('the store name: its identifying words, not "Greek" or "Kitchen"', () => {
    expect(rc.matchStoreName('ILIOS CRAFTED GREEK - SOUTHEND #12', 'Ilios Crafted Greek')).toBe(true);
    expect(rc.matchStoreName('Zeus Greek Kitchen', 'Ilios Crafted Greek')).toBe(false);
    expect(rc.matchStoreName("Sal's Pizza order 44", "Sal's Pizza Kitchen")).toBe(true);
    expect(rc.matchStoreName('Domino’s Pizza', "Sal's Pizza Kitchen")).toBe(false);
  });

  test('the date: within a week, not in the future', () => {
    expect(rc.dateCheck('2026-11-05', NOW)).toBe('ok');
    expect(rc.dateCheck('2026-10-20', NOW)).toBe('too_old');
    expect(rc.dateCheck('2026-11-09', NOW)).toBe('future');
    expect(rc.dateCheck(null, NOW)).toBe('missing');
  });

  test('order numbers compare without punctuation', () => {
    expect(rc.normalizeOrderNumber('#a1b2-c3d4')).toBe('A1B2C3D4');
    expect(rc.normalizeOrderNumber('#12')).toBeNull();
  });
});

describe('sending a receipt', () => {
  test('a store that approves: waits, the team hears, the photo is kept privately', async () => {
    const out = await rc.submit('u1', 'v1', receipt(), { now: NOW });
    expect(out.status).toBe('pending');
    expect(mockSaved).toEqual([`receipts/v1/${out.claimId}.jpg`]);
    expect(mockPush.mock.calls.map((c) => c[0]).sort()).toEqual(['mgr', 'owner']);
    expect(mockPush.mock.calls[0][1].type).toBe('receipt_new');
    expect(table('receiptClaims')[out.claimId].checks).toEqual({ storeName: true, date: true, orderNumber: true });
  });

  test('automatic: pays right away when everything checks out', async () => {
    table('stickerVenues').v1.deliveryReceipts = 'auto';
    const out = await rc.submit('u1', 'v1', receipt(), { now: NOW });
    expect(out).toMatchObject({ status: 'approved', points: 10, venueBalance: 30 });
    expect(mockAwards).toEqual([{ key: 'visit:u1:v1:2026-11-06', via: 'delivery_receipt' }]);
    expect(mockPush).not.toHaveBeenCalled();
  });

  test('automatic: a receipt that doesn\'t check out waits for the team instead of failing', async () => {
    table('stickerVenues').v1.deliveryReceipts = 'auto';
    const out = await rc.submit('u1', 'v1', receipt({ text: 'Some Other Place', orderNumber: '' }), { now: NOW });
    expect(out.status).toBe('pending');
    expect(mockAwards).toEqual([]);
  });

  test('refused: store off, paused, removed, too old, used order number, already earned today', async () => {
    table('stickerVenues').v1.deliveryReceipts = 'off';
    await expect(rc.submit('u1', 'v1', receipt(), { now: NOW })).rejects.toMatchObject({ code: 'receipts_off' });
    table('stickerVenues').v1.deliveryReceipts = 'approve';
    table('stickerVenues').v1.paused = true;
    await expect(rc.submit('u1', 'v1', receipt(), { now: NOW })).rejects.toMatchObject({ code: 'rewards_paused' });
    delete table('stickerVenues').v1.paused;
    await expect(rc.submit('banned', 'v1', receipt(), { now: NOW })).rejects.toMatchObject({ code: 'removed' });
    await expect(rc.submit('u1', 'v1', receipt({ orderDate: '2026-10-01' }), { now: NOW })).rejects.toMatchObject({ code: 'too_old' });

    await rc.submit('u1', 'v1', receipt(), { now: NOW });
    await expect(rc.submit('u2', 'v1', receipt(), { now: NOW })).rejects.toMatchObject({ code: 'order_used' });

    table('rewardEvents')['visit:u3:v1:2026-11-06'] = { points: 10 };
    await expect(rc.submit('u3', 'v1', receipt({ orderNumber: 'ZZZZ9999' }), { now: NOW })).rejects.toMatchObject({ code: 'already_today' });
  });
});

describe('the team answers', () => {
  const venue = () => ({ venueId: 'v1', ...table('stickerVenues').v1 });

  test('Give points pays once; a second tap is refused', async () => {
    const { claimId } = await rc.submit('u1', 'v1', receipt(), { now: NOW });
    mockPush.mockClear();
    expect(await rc.approve(venue(), claimId, 'owner')).toMatchObject({ approved: true, points: 10 });
    await expect(rc.approve(venue(), claimId, 'mgr')).rejects.toMatchObject({ code: 'already_decided' });
    expect(mockAwards).toHaveLength(1);
    expect(mockPush.mock.calls[0][0]).toBe('u1');
    expect(mockPush.mock.calls[0][1]).toMatchObject({ type: 'receipt_result', title: 'Ilios Crafted Greek gave you 10 points' });
  });

  test('a day they also scanned at the register earns once', async () => {
    const { claimId } = await rc.submit('u1', 'v1', receipt(), { now: NOW });
    mockAwards.push({ key: 'visit:u1:v1:2026-11-06' });
    expect(await rc.approve(venue(), claimId, 'owner')).toMatchObject({ points: 0, alreadyEarned: true });
  });

  test('Decline tells the customer and pays nothing', async () => {
    const { claimId } = await rc.submit('u1', 'v1', receipt(), { now: NOW });
    mockPush.mockClear();
    expect(await rc.decline(venue(), claimId, 'owner')).toEqual({ declined: true });
    expect(table('receiptClaims')[claimId].status).toBe('declined');
    expect(mockAwards).toEqual([]);
    expect(mockPush.mock.calls[0][1].title).toBe('Ilios Crafted Greek couldn’t match your receipt');
  });

  test('another store can\'t answer this one\'s receipts', async () => {
    const { claimId } = await rc.submit('u1', 'v1', receipt(), { now: NOW });
    await expect(rc.approve({ venueId: 'v2', venueName: 'X' }, claimId, 'x')).rejects.toMatchObject({ status: 404 });
  });
});
