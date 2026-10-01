// Security audit 2026-10-01, remaining backend items: each test pins one fix
// against the in-memory Firestore.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  admin: { firestore: { FieldPath: { documentId: () => '__name__' } } },
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/notificationService', () => ({
  notifyStoreClaimSubmitted: jest.fn(async () => {}),
  sendToUserWithRecord: jest.fn(async () => {})
}));
jest.mock('../../services/sseService', () => ({ notifyUser: jest.fn() }));
jest.mock('../../services/userStatsCache', () => ({ getPlaceCountMap: jest.fn(async () => new Map()) }));
jest.mock('../../services/emailService', () => ({ sendEmail: jest.fn(async () => {}) }));
jest.mock('../../services/adminAlerts', () => ({ alertAdmin: jest.fn(async () => true) }));
jest.mock('../../services/backgroundAggregationService', () => ({}));
jest.mock('../../services/cacheInvalidationService', () => ({}));
jest.mock('../../services/activityFeedService', () => ({ fetchActivitiesByActors: jest.fn(async () => []) }));
jest.mock('../../utils/networkAccess', () => ({
  ...jest.requireActual('../../utils/networkAccess'),
  getInnerCircleGrantorLists: jest.fn(async () => new Map())
}));
jest.mock('../../services/globalPlaceResolver', () => ({
  findCanonicalByNameAndLocation: jest.fn(async () => null),
  createGlobalPlaceFromDetails: jest.fn(async () => ({ resolvedId: 'gp1' }))
}));
jest.mock('../../services/rewardService', () => ({ findVenueByPlace: jest.fn(async () => null) }));
// Its module-level setInterval would keep jest from exiting.
jest.mock('../../services/requestDeduplicator', () => ({}));

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  r.set = jest.fn(() => r);
  return r;
};
const fail = (e) => { throw e; };
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

beforeEach(() => {
  for (const name of ['users', 'circles', 'places', 'connections', 'reports', 'placeVideos', 'venueClaimRequests']) {
    mockDb.rows(name).clear();
  }
  jest.clearAllMocks();
});

describe('projectPublicUser location (item 4)', () => {
  const { projectPublicUser, LOCATION_HIDDEN } = require('../../services/publicUserProjection');
  const hidden = { id: 'sal', displayName: 'Sal', location: 'Charlotte', email: 'sal@x.com', preferences: { showLocation: false } };

  test('"Show my city" off hides location from others, and marks the card', () => {
    const card = projectPublicUser(hidden);
    expect(card.location).toBeNull();
    expect(card[LOCATION_HIDDEN]).toBe(true);
    expect(JSON.parse(JSON.stringify(card))).toEqual({ id: 'sal', displayName: 'Sal', location: null });
  });

  test('the user themself still sees their own city', () => {
    expect(projectPublicUser(hidden, [], { viewerId: 'sal' }).location).toBe('Charlotte');
  });

  test('default preference passes location through', () => {
    expect(projectPublicUser({ id: 'a', displayName: 'A', location: 'Durham' }).location).toBe('Durham');
  });

  test('enrichment does not backfill an assumed city onto a hidden card', async () => {
    const { decorateUserCards } = require('../../services/userCardEnrichment');
    const card = projectPublicUser(hidden);
    await decorateUserCards([card], { activityReason: false });
    expect(card.location).toBeNull();
  });
});

describe('GET /api/connections (item 2)', () => {
  const { getConnections } = require('../connectionController');

  test('connected users come back as public cards — no email, phone or tokens', async () => {
    await put('users', 'me', { displayName: 'Me', followers: ['sal'] });
    await put('users', 'sal', {
      displayName: 'Sal', email: 'sal@example.com', phoneNumber: '7045550199',
      deviceTokens: ['tok'], location: 'Charlotte', preferences: { showLocation: false }
    });
    await put('connections', 'c1', { userId: 'me', connectedUserId: 'sal', status: 'accepted' });

    const out = res();
    await getConnections({ user: { uid: 'me' } }, out);
    const body = out.json.mock.calls[0][0];
    expect(body.connections).toHaveLength(1);
    const user = body.connections[0].connectedUser;
    expect(user.displayName).toBe('Sal');
    expect(user.followsYou).toBe(true);
    expect(user.location).toBeNull();
    expect(JSON.stringify(body)).not.toMatch(/@|7045550199|tok/);
  });
});

describe('GET /api/users/contacts/search (item 3)', () => {
  const { searchUsersAdvanced } = require('../userDiscoveryController');

  // The fake has no cursor ranges; the name-prefix query needs them.
  const FakeQueryProto = Object.getPrototypeOf(mockDb.collection('users').orderBy('x'));
  FakeQueryProto.startAt = function startAt(v) { return this.where(this.order.field, '>=', v); };
  FakeQueryProto.endAt = function endAt(v) { return this.where(this.order.field, '<=', v); };

  test('exact email lookup still finds the person, without echoing the address', async () => {
    await put('users', 'me', { displayName: 'Me' });
    await put('users', 'sal', { displayName: 'Sal', email: 'sal@example.com', displayNameLowercase: 'sal' });

    const out = res();
    await searchUsersAdvanced({ query: { query: 'sal@example.com' }, user: { uid: 'me' } }, out);
    const body = out.json.mock.calls[0][0];
    expect(body.users).toHaveLength(1);
    expect(body.users[0]).toMatchObject({ id: 'sal', displayName: 'Sal', matchedBy: 'email', matchType: 'email' });
    expect(body.users[0].email).toBeUndefined();
  });
});

describe('GET /api/home/dashboard (item 1)', () => {
  const { getDashboard } = require('../dashboardController');

  test('own circles are read by owner (no composite index); hidden ones and private notes stay hidden', async () => {
    await put('users', 'me', { displayName: 'Me', following: ['fan'] });
    await put('users', 'fan', { displayName: 'Followed' });
    await put('circles', 'mine', { owner: 'me', name: 'Mine', privacy: 'private' });
    await put('circles', 'trashed', { owner: 'me', name: 'Trashed', privacy: 'private', deletedAt: '2026-09-01' });
    await put('circles', 'theirPublic', { owner: 'fan', name: 'Public', privacy: 'public' });
    // Followed, not connected: a myNetwork circle is not theirs to see.
    await put('circles', 'theirNetwork', { owner: 'fan', name: 'Network only', privacy: 'myNetwork' });
    await put('places', 'p1', { circleId: 'theirPublic', addedBy: 'fan', name: 'Deli', privateNotes: 'secret', sharedWith: ['x'] });
    await put('places', 'p2', { circleId: 'theirPublic', addedBy: 'fan', name: 'Hidden', privacy: 'private' });
    await put('places', 'p3', { circleId: 'mine', addedBy: 'me', name: 'Mine', privateNotes: 'my note' });

    const out = res();
    await getDashboard({ user: { uid: 'me' }, query: {} }, out, fail);
    const { data } = out.json.mock.calls[0][0];
    expect(data.myCircles.map(c => c._id || c.id)).toEqual(['mine']);
    expect(data.myCircles[0].places[0].privateNotes).toBe('my note');
    expect(data.networkCircles.map(c => c._id || c.id)).toEqual(['theirPublic']);
    const theirPlaces = data.networkCircles[0].places;
    expect(theirPlaces.map(p => p.name)).toEqual(['Deli']);
    expect(theirPlaces[0].privateNotes).toBeUndefined();
    expect(theirPlaces[0].sharedWith).toBeUndefined();
  });
});

describe('GET /api/circles/:id/places/public (item 5)', () => {
  const { getPlacesByCircleIdPublic } = require('../places/placeController');

  test('fetches only the adders in one batched read', async () => {
    await put('circles', 'c', { owner: 'sal', privacy: 'public', name: 'C' });
    await put('users', 'sal', { displayName: 'Sal', email: 'sal@example.com' });
    await put('users', 'bystander', { displayName: 'Nobody', email: 'nobody@example.com' });
    await put('places', 'p1', { circleId: 'c', addedBy: 'sal', name: 'Deli', createdAt: '2026-09-01' });

    const getAll = jest.spyOn(mockDb, 'getAll');
    const out = res();
    await getPlacesByCircleIdPublic({ params: { circleId: 'c' }, url: '/', method: 'GET' }, out, fail);
    const body = out.json.mock.calls[0][0];
    expect(body.places).toHaveLength(1);
    expect(body.places[0].addedByUser.displayName).toBe('Sal');
    expect(getAll).toHaveBeenCalledTimes(1);
    expect(getAll.mock.calls[0].map(ref => ref.id)).toEqual(['sal']);
    expect(JSON.stringify(body)).not.toMatch(/@/);
    getAll.mockRestore();
  });
});

describe('admin emails escape user input (item 7)', () => {
  test('flag-a-place goes through alertAdmin (which escapes) with the report content', async () => {
    const { flagPlaceInfo } = require('../places/placeVenueMaintenanceController');
    const { alertAdmin } = require('../../services/adminAlerts');
    const emailService = require('../../services/emailService');
    await put('places', 'p1', { name: '<img src=x onerror=alert(1)>', address: '1 Main' });

    const out = res();
    await flagPlaceInfo({ params: { id: 'p1' }, body: { message: '<script>bad()</script>' }, user: { uid: 'u1' } }, out);
    expect(alertAdmin).toHaveBeenCalledTimes(1);
    const call = alertAdmin.mock.calls[0][0];
    expect(call.key).toBe('place_flag_p1');
    expect(call.minIntervalMs).toBe(0);
    expect(call.body).toContain("What's wrong: <script>bad()</script>"); // plain text; alertAdmin escapes the HTML
    expect(emailService.sendEmail).not.toHaveBeenCalled(); // no hand-built HTML email any more
  });

  test('ownership-claim email escapes every user-supplied field in the HTML', async () => {
    const { claimBusinessByDetails } = require('../venues/venueClaimsController');
    const emailService = require('../../services/emailService');
    const out = res();
    await claimBusinessByDetails({
      user: { uid: 'u1', email: 'u1@example.com', displayName: '<b>Owner</b>' },
      body: {
        name: '<script>x()</script>', address: '1 <i>Main</i>', lat: 35, lng: -80,
        contactName: '<a href=evil>Me</a>', contactEmail: 'me@example.com', message: '<img src=x>'
      }
    }, out);
    expect(emailService.sendEmail).toHaveBeenCalledTimes(1);
    const { html, text } = emailService.sendEmail.mock.calls[0][0];
    expect(html).not.toMatch(/<script|<img|<a href|<b>|<i>/);
    expect(html).toContain('&lt;script&gt;x()&lt;/script&gt;');
    expect(text).toContain('<script>x()</script>'); // plain-text part is not HTML
  });
});

describe('video feed pagination is clamped (item 6)', () => {
  const { getPlaceReels } = require('../video/videoFeedController');

  test('an absurd ?limit is capped at 100 and garbage falls back to the default', async () => {
    await put('users', 'me', { displayName: 'Me' });
    for (let i = 0; i < 130; i++) {
      await put('placeVideos', `v${String(i).padStart(3, '0')}`, {
        placeId: 'pl', userId: 'me', uploadStatus: 'ready', deletedAt: null,
        privacy: 'public', createdAt: new Date(Date.UTC(2026, 0, 1, 0, i)).toISOString()
      });
    }
    const call = async (query) => {
      const out = res();
      await getPlaceReels({ params: { placeId: 'pl' }, query, user: { uid: 'me' } }, out);
      return out.json.mock.calls[0][0];
    };
    const big = await call({ limit: '100000', offset: '0' });
    expect(big.data).toHaveLength(100);
    expect(big.hasMore).toBe(true);
    expect((await call({ limit: 'abc', offset: '-5' })).data).toHaveLength(20);
    expect((await call({ limit: '10', offset: '999999' })).data).toHaveLength(0); // offset capped at 1000
  });
});
