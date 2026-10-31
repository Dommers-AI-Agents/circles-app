// Discover type=following (Wes, 2026-10-12): the people you follow but
// aren't connected with, so Connect is one tap away instead of a profile
// visit each. Pinned against the in-memory Firestore.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  admin: { firestore: { FieldPath: { documentId: () => '__name__' } } },
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/userStatsCache', () => ({
  getPlaceCountMap: jest.fn(async () => new Map([
    ['big', { placesCount: 90, circlesCount: 4 }],
    ['small', { placesCount: 2, circlesCount: 1 }],
    ['mutual', { placesCount: 5, circlesCount: 1 }]
  ]))
}));
jest.mock('../../services/suggestionEngine', () => ({ getSuggestionsFor: jest.fn(async () => []) }));
jest.mock('../../services/userCardEnrichment', () => ({
  getAssumedLocation: jest.fn(),
  effectiveCoords: jest.fn(),
  decorateUserCards: jest.fn(async () => {}),
  isFreshAssumedLocation: jest.fn()
}));
jest.mock('../../services/requestDeduplicator', () => ({}));

const { getDiscoverUsers } = require('../userDiscoveryController');

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  return r;
};
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

beforeEach(() => {
  for (const name of ['users', 'connections']) mockDb.rows(name).clear();
});

describe('GET /api/users/contacts/discover?type=following', () => {
  test('followed-not-connected people, mutual follows first, each saying where you stand', async () => {
    await put('users', 'me', {
      displayName: 'Me',
      following: ['big', 'small', 'mutual', 'connected', 'asked', 'askedMe', 'dismissed', 'blocked', 'gone', 'me'],
      followers: ['mutual'],
      dismissedSuggestions: ['dismissed'],
      blockedUsers: ['blocked']
    });
    for (const id of ['big', 'small', 'mutual', 'connected', 'asked', 'askedMe', 'dismissed', 'blocked']) {
      await put('users', id, { displayName: id });
    }
    await put('users', 'gone', { displayName: 'gone', active: false });
    await put('connections', 'c1', { userId: 'me', connectedUserId: 'connected', status: 'accepted' });
    await put('connections', 'c2', { userId: 'me', connectedUserId: 'asked', status: 'pending' });
    await put('connections', 'c3', { userId: 'askedMe', connectedUserId: 'me', status: 'pending' });

    const out = res();
    await getDiscoverUsers({ user: { uid: 'me' }, query: { type: 'following' } }, out);
    const body = out.json.mock.calls[0][0];
    expect(body.success).toBe(true);
    expect(body.users.map((u) => u.id)).toEqual(['mutual', 'big', 'small']);
    expect(body.users[0]).toMatchObject({
      discoveryType: 'following', isFollowing: true, followsYou: true,
      connectionStatus: 'none', suggestionReason: '👋 You follow each other'
    });
    expect(body.users[1]).toMatchObject({ isFollowing: true, followsYou: false, suggestionReason: 'You follow them' });
  });

  test('follows-you suggestions skip people you are already connected with or have asked', async () => {
    await put('users', 'me', { displayName: 'Me', following: [], followers: ['fan', 'connected', 'asked'] });
    for (const id of ['fan', 'connected', 'asked']) await put('users', id, { displayName: id, following: ['me'] });
    await put('connections', 'c1', { userId: 'me', connectedUserId: 'connected', status: 'accepted' });
    await put('connections', 'c2', { userId: 'asked', connectedUserId: 'me', status: 'pending' });
    const out = res();
    await getDiscoverUsers({ user: { uid: 'me' }, query: { type: 'followsYou' } }, out);
    expect(out.json.mock.calls[0][0].users.map((u) => u.id)).toEqual(['fan']);
  });

  test('the everyone list leaves out people you are already connected with', async () => {
    await put('users', 'me', { displayName: 'Me', following: ['followed'], followers: [] });
    for (const id of ['stranger', 'followed', 'connected', 'asked']) {
      await put('users', id, { displayName: id, following: [], createdAt: '2026-01-01T00:00:00.000Z' });
    }
    await put('connections', 'c1', { userId: 'me', connectedUserId: 'connected', status: 'accepted' });
    await put('connections', 'c2', { userId: 'me', connectedUserId: 'asked', status: 'pending' });
    const out = res();
    await getDiscoverUsers({ user: { uid: 'me' }, query: { type: 'everyone' } }, out);
    const users = out.json.mock.calls[0][0].users;
    expect(users.map((u) => u.id)).toEqual(['stranger', 'followed', 'asked']);
    expect(users.find((u) => u.id === 'asked').connectionStatus).toBe('pending');
  });

  test('nobody followed means an empty list, not an error', async () => {
    await put('users', 'me', { displayName: 'Me' });
    const out = res();
    await getDiscoverUsers({ user: { uid: 'me' }, query: { type: 'following' } }, out);
    expect(out.json.mock.calls[0][0]).toMatchObject({ success: true, users: [], hasMore: false });
  });

  test('people you may know (stored suggestions) show the person\'s current name and photo', async () => {
    require('../../services/suggestionEngine').getSuggestionsFor.mockResolvedValueOnce([
      { userId: 'sal', displayName: 'Salvatore', profilePicture: 'https://x/old.jpg', signal: 'fof', reason: 'Followed by Wes' }
    ]);
    await put('users', 'me', { displayName: 'Me', following: [], followers: [] });
    await put('users', 'sal', { displayName: 'Sal Sgroi', profilePicture: 'https://x/new.jpg' });
    const out = res();
    await getDiscoverUsers({ user: { uid: 'me' }, query: { type: 'friendsOfFriends' } }, out);
    expect(out.json.mock.calls[0][0].users[0]).toMatchObject({ id: 'sal', displayName: 'Sal Sgroi', profilePicture: 'https://x/new.jpg' });
  });
});
