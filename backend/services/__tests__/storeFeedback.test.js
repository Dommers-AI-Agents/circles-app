// "Enjoying <store>?" once per store, and private feedback to the team (2026-11-02)
const store = { users: {}, venues: {}, feedback: {}, globalPlaces: {} };
const mockDb = {
  collection: (name) => ({
    doc: (id) => ({
      get: async () => {
        const table = { users: store.users, stickerVenues: store.venues, globalPlaces: store.globalPlaces }[name] || {};
        return { id, exists: !!table[id], data: () => table[id] };
      },
      update: async (u) => Object.entries(u).forEach(([k, v]) => {
        const keys = k.split('.'); let o = store.users[id];
        keys.slice(0, -1).forEach((key) => { o[key] = o[key] || {}; o = o[key]; });
        o[keys[keys.length - 1]] = v;
      }),
      set: async (data) => { store.feedback[id] = data; }
    })
  })
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
const mockPush = jest.fn();
jest.mock('../notifyQuiet', () => ({ sendInBackground: (...a) => mockPush(...a) }));
jest.mock('../venueHelpers', () => ({
  venueGlobalPlaceId: async (v) => v.globalPlaceId || null,
  venueManagerIds: (v) => v.managerUserIds || []
}));
jest.mock('../ownSaveOfVenue', () => ({ findOwnSaveOfStore: async () => ({ id: 'save1' }) }));

const fb = require('../storeFeedback');

beforeEach(() => {
  store.users = { u1: { displayName: 'Ann', rewardPointsByVenue: { v1: { points: 0 } } } };
  store.venues = { v1: { venueName: 'Fresh Monkee', ownerUserId: 'owner', managerUserIds: ['mgr'], globalPlaceId: 'g1' } };
  store.globalPlaces = { g1: { followers: ['someoneElse'] } };
  store.feedback = {};
  mockPush.mockClear();
});

test('the card comes once per store, with what to offer', async () => {
  const first = await fb.enjoyingCard('u1', 'v1');
  // ownPlaceId/currentRating: the card asks for a 0–10 rating on their own save (2026-11-09)
  expect(first).toEqual({ show: true, venueName: 'Fresh Monkee', globalPlaceId: 'g1', reviewPlaceId: 'save1', following: false, ownPlaceId: 'save1', currentRating: null });
  expect(await fb.enjoyingCard('u1', 'v1')).toEqual({ show: false });
});

test('the card knows when they already follow the store', async () => {
  store.globalPlaces.g1.followers = ['u1'];
  expect((await fb.enjoyingCard('u1', 'v1')).following).toBe(true);
});

test('feedback: stars 1–5 required, stored once a day, pushed to owner and managers', async () => {
  await expect(fb.sendFeedback('u1', 'v1', { rating: 0 })).rejects.toMatchObject({ status: 400 });
  await expect(fb.sendFeedback('u1', 'v1', { rating: 6 })).rejects.toMatchObject({ status: 400 });

  await fb.sendFeedback('u1', 'v1', { rating: 4, note: '  Great smoothies, slow line  ' });
  await fb.sendFeedback('u1', 'v1', { rating: 5 });

  const docs = Object.values(store.feedback);
  expect(docs).toHaveLength(1);                                   // same day replaces
  expect(docs[0]).toMatchObject({ venueId: 'v1', userId: 'u1', rating: 5, note: null });
  expect(mockPush.mock.calls.map((c) => c[0]).sort()).toEqual(['mgr', 'mgr', 'owner', 'owner']);
  expect(mockPush.mock.calls[0][1]).toMatchObject({ type: 'store_feedback', title: '★★★★☆ from Ann', body: 'Great smoothies, slow line', data: { venueId: 'v1' } });
});
