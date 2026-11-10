// The store's waitlist: settings, places in line, join/leave, the host's
// actions with their pushes, and the sweep.
const { FakeFirestore, FakeFieldValue: MockFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb, FieldValue: MockFieldValue, admin: { firestore: { FieldValue: MockFieldValue } }
}));
const mockPush = jest.fn();
jest.mock('../notifyQuiet', () => ({ sendInBackground: (...args) => mockPush(...args) }));
jest.mock('../ownerSubscriptionService', () => ({ isVenueBusinessLive: async (venue) => venue.live !== false }));
jest.mock('../venueHelpers', () => ({ venueGlobalPlaceId: async () => 'gp1', venueManagerIds: (v) => v.managerUserIds || [] }));

const wl = require('../waitlistService');

const NOW = new Date('2026-11-09T18:00:00.000Z');
const at = (minutesAgo) => new Date(NOW.getTime() - minutesAgo * 60000).toISOString();
const venue = { venueId: 'v1', venueName: "Sal's", ownerUserId: 'owner', managerUserIds: ['mgr'], waitlist: { enabled: true, quoteMinutes: 20 } };

beforeEach(async () => {
  mockPush.mockClear();
  mockDb.rows('waitlistEntries').clear(); mockDb.rows('stickerVenues').clear(); mockDb.rows('users').clear();
  await mockDb.collection('stickerVenues').doc('v1').set(venue);
  await mockDb.collection('stickerVenues').doc('v2').set({ ...venue, venueName: 'Off', waitlist: { enabled: false } });
  await mockDb.collection('users').doc('ana').set({ firstName: 'Ana', displayName: 'Ana Lopez' });
});

test('settings fill defaults and refuse bad values; customers see the list only while it is on', () => {
  expect(wl.settingsOf({})).toEqual({ enabled: false, quoteMinutes: 15 });
  expect(wl.settingsOf(venue)).toEqual({ enabled: true, quoteMinutes: 20 });
  expect(() => wl.normalizeSettings({ quoteMinutes: 2 })).toThrow(/5 to 120/);
  expect(wl.normalizeSettings({ enabled: true, quoteMinutes: 30 })).toMatchObject({ enabled: true, quoteMinutes: 30 });
  expect(wl.waitlistFor(venue, { live: true })).toEqual({ enabled: true, quoteMinutes: 20 });
  expect(wl.waitlistFor(venue, { live: false })).toBeNull();
  expect(wl.waitlistFor({}, { live: true })).toBeNull();
});

test('places in line follow who joined first; the estimate grows with the line', () => {
  const line = wl.withPositions([
    { id: 'b', joinedAt: at(5) }, { id: 'a', joinedAt: at(9) }, { id: 'c', joinedAt: at(1) }
  ]);
  expect(line.map((e) => [e.id, e.position])).toEqual([['a', 1], ['b', 2], ['c', 3]]);
  expect(wl.estimateMinutes(1, 20)).toBe(20);
  expect(wl.estimateMinutes(3, 20)).toBe(60);
  expect(() => wl.normalizeParty(0)).toThrow(/1 to 12/);
});

test('join: one open entry per person, the team is told, the guest sees their place and wait', async () => {
  const first = await wl.join({ venueId: 'v1', userId: 'ana', partySize: 2, now: NOW });
  expect(first).toMatchObject({ venueId: 'v1', name: 'Ana', partySize: 2, status: 'waiting', position: 1, estimateMinutes: 20, placeId: 'gp1' });
  expect(mockPush).toHaveBeenCalledTimes(2); // owner + manager
  expect(mockPush.mock.calls[0][1]).toMatchObject({ type: 'waitlist_joined', title: 'Ana joined the waitlist' });

  const again = await wl.join({ venueId: 'v1', userId: 'ana', partySize: 4, now: NOW });
  expect(again.alreadyInLine).toBe(true);
  expect(again.partySize).toBe(2);

  const second = await wl.join({ venueId: 'v1', userId: 'ben', partySize: 3, name: 'Ben', now: new Date(NOW.getTime() + 60000) });
  expect(second.position).toBe(2);
  expect(second.estimateMinutes).toBe(40);
  expect((await wl.mine('v1', 'ben')).position).toBe(2);
  expect(await wl.count('v1')).toBe(2);
  await expect(wl.join({ venueId: 'v2', userId: 'cy', partySize: 2 })).rejects.toThrow(/isn't taking a waitlist/);
});

test('leaving frees the spot; the host notifies, seats and removes with the right pushes', async () => {
  await wl.join({ venueId: 'v1', userId: 'ana', partySize: 2, now: NOW });
  const ben = await wl.join({ venueId: 'v1', userId: 'ben', partySize: 3, now: new Date(NOW.getTime() + 60000) });
  const cy = await wl.join({ venueId: 'v1', userId: 'cy', partySize: 1, now: new Date(NOW.getTime() + 120000) });
  mockPush.mockClear();

  const ana = (await wl.line(venue))[0];
  await wl.leave(ana.entryId, 'ana');
  expect((await wl.mine('v1', 'ben')).position).toBe(1);
  await expect(wl.leave(ben.entryId, 'someone-else')).rejects.toThrow(/not found/);

  const notified = await wl.act(venue, ben.entryId, 'notify', { now: NOW });
  expect(notified.status).toBe('notified');
  expect(mockPush).toHaveBeenLastCalledWith('ben', expect.objectContaining({ type: 'waitlist_ready', title: "Your table is ready at Sal's", data: expect.objectContaining({ placeId: 'gp1' }) }), 'waitlist_ready');
  await expect(wl.act(venue, ben.entryId, 'notify')).rejects.toThrow(/already notified/);
  expect((await wl.act(venue, ben.entryId, 'seat')).status).toBe('seated');

  const removed = await wl.act(venue, cy.entryId, 'remove');
  expect(removed.status).toBe('removed');
  expect(mockPush).toHaveBeenLastCalledWith('cy', expect.objectContaining({ type: 'waitlist_update' }), 'waitlist_update');
  expect(await wl.line(venue)).toEqual([]);
  await expect(wl.act({ venueId: 'v2' }, cy.entryId, 'seat')).rejects.toThrow(/not in your line/);
});

test('the sweep expires called parties after 15 minutes (told) and stale waiting entries quietly', async () => {
  await mockDb.collection('waitlistEntries').doc('called').set({ venueId: 'v1', venueName: "Sal's", userId: 'ana', status: 'notified', joinedAt: at(40), notifiedAt: at(16) });
  await mockDb.collection('waitlistEntries').doc('fresh').set({ venueId: 'v1', userId: 'ben', status: 'notified', joinedAt: at(30), notifiedAt: at(5) });
  await mockDb.collection('waitlistEntries').doc('forgotten').set({ venueId: 'v1', userId: 'cy', status: 'waiting', joinedAt: at(5 * 60) });
  await mockDb.collection('waitlistEntries').doc('waiting').set({ venueId: 'v1', userId: 'dee', status: 'waiting', joinedAt: at(10) });
  const result = await wl.sweep({ now: NOW });
  expect(result).toEqual({ waitlistExpired: 1, waitlistClosed: 1 });
  expect((await mockDb.collection('waitlistEntries').doc('called').get()).data().status).toBe('expired');
  expect((await mockDb.collection('waitlistEntries').doc('fresh').get()).data().status).toBe('notified');
  expect((await mockDb.collection('waitlistEntries').doc('forgotten').get()).data().status).toBe('expired');
  expect((await mockDb.collection('waitlistEntries').doc('waiting').get()).data().status).toBe('waiting');
  expect(mockPush).toHaveBeenCalledTimes(1);
  expect(mockPush.mock.calls[0][1].title).toContain('went to the next party');
});
