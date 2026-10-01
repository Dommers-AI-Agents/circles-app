// Security audit 2026-10-01: endpoints that served other users' personal data.
// Each test pins one fix against a real (fake) Firestore.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

// Real queries call select() on a collection; the fake's collections don't
// have it. A no-limit query is the same rows.
Object.getPrototypeOf(mockDb.collection('users')).select = function select() { return this.limit(1e9); };

const res = () => {
  const r = {};
  r.status = jest.fn(() => r);
  r.json = jest.fn(() => r);
  r.set = jest.fn(() => r);
  r.type = jest.fn(() => r);
  r.send = jest.fn(() => r);
  r.redirect = jest.fn(() => r);
  return r;
};
const fail = (e) => { throw e; };
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);

beforeEach(() => {
  for (const name of ['users', 'circles', 'circleComments', 'placeVideos', 'connections']) {
    mockDb.rows(name).clear();
  }
});

describe('GET /api/users/search', () => {
  const { searchUsers } = require('../users/userController');
  const { resetSearchIndexForTests } = require('../../services/userSearchIndex');

  beforeEach(async () => {
    resetSearchIndexForTests(); // each test seeds its own users
    await put('users', 'me', { displayName: 'Me', blockedUsers: ['blocked1'], blockedBy: ['blocker1'] });
    await put('users', 'sal', {
      displayName: 'Sal Smith', email: 'sal@example.com', phoneNumber: '7045550199',
      location: 'Charlotte', preferences: { showLocation: false }
    });
    await put('users', 'sally', { displayName: 'Sally Jones', email: 'sally@example.com', location: 'Durham' });
    await put('users', 'blocked1', { displayName: 'Sal Blocked' });
    await put('users', 'blocker1', { displayName: 'Sal Blocker' });
  });

  const search = async (query) => {
    const out = res();
    await searchUsers({ query: { query }, user: { uid: 'me' } }, out, fail);
    return out.json.mock.calls[0][0];
  };

  test('empty or one-character query returns nobody (used to return everyone)', async () => {
    expect((await search('')).users).toEqual([]);
    expect((await search(undefined)).users).toEqual([]);
    expect((await search('s')).users).toEqual([]);
  });

  test('never returns email or phone, honours "Show my city", excludes blocks', async () => {
    const { users } = await search('sal');
    expect(users.map(u => u._id).sort()).toEqual(['sal', 'sally']);
    for (const u of users) {
      expect(u).not.toHaveProperty('email');
      expect(u).not.toHaveProperty('phoneNumber');
    }
    expect(users.find(u => u._id === 'sal').location).toBeNull();
    expect(users.find(u => u._id === 'sally').location).toBe('Durham');
  });

  test('email and phone digits are not searchable', async () => {
    expect((await search('sal@example.com')).users).toEqual([]);
    expect((await search('example')).users).toEqual([]);
    expect((await search('5550199')).users).toEqual([]);
  });
});

describe('circles', () => {
  const circles = require('../firebaseCircleController');

  beforeEach(async () => {
    await put('users', 'owner', { displayName: 'Owner', email: 'owner@example.com', phoneNumber: '1' });
    await put('users', 'stranger', { displayName: 'Stranger', email: 'stranger@example.com', phoneNumber: '2' });
    await put('circles', 'pub', {
      name: 'Public', owner: 'owner', privacy: 'public', category: 'food',
      sharedWith: ['invitee@example.com'], editors: ['ed'], likes: ['stranger'], followers: ['f'],
      createdAt: '2026-01-01', updatedAt: '2026-01-02'
    });
    await put('circles', 'priv', { name: 'Private', owner: 'owner', privacy: 'private', category: 'food' });
    await put('circleComments', 'c1', { circleId: 'priv', userId: 'owner', text: 'secret', parentCommentId: null, createdAt: '2026-01-01' });
    await put('circleComments', 'c2', { circleId: 'pub', userId: 'owner', text: 'hi', parentCommentId: null, createdAt: '2026-01-01' });
  });

  test('getCirclePublic serves public fields only', async () => {
    const out = res();
    await circles.getCirclePublic({ params: { id: 'pub' } }, out, fail);
    const { circle } = out.json.mock.calls[0][0];
    expect(circle).toMatchObject({ _id: 'pub', name: 'Public', owner: 'owner', privacy: 'public' });
    for (const key of ['sharedWith', 'editors', 'likes', 'followers']) {
      expect(circle).not.toHaveProperty(key);
    }
  });

  test.each([
    ['getCircleComments', { id: 'priv' }, {}],
    ['getCircleLikes', { id: 'priv' }, {}],
    ['addCircleComment', { id: 'priv' }, { text: 'hello' }],
    ['addCommentReply', { id: 'priv', commentId: 'c1' }, { text: 'hello' }],
    ['getCommentReplies', { id: 'priv', commentId: 'c1' }, {}],
    ['likeCircle', { id: 'priv' }, {}]
  ])('%s on a circle the caller cannot see → 404', async (handler, params, body) => {
    const out = res();
    await circles[handler]({ params, body, user: { uid: 'stranger' } }, out, fail);
    expect(out.status).toHaveBeenCalledWith(404);
    expect(mockDb.rows('circleComments').size).toBe(2); // nothing written
    expect(mockDb.rows('circles').get('priv').likes).toBeUndefined();
  });

  test('followCircle on a hidden circle → 404', async () => {
    const out = res();
    await circles.followCircle({ params: { id: 'priv' }, path: '/priv/follow', user: { uid: 'stranger' } }, out, fail);
    expect(out.status).toHaveBeenCalledWith(404);
  });

  test('comment and like lists embed a public card, not the whole user doc', async () => {
    const comments = res();
    await circles.getCircleComments({ params: { id: 'pub' }, user: { uid: 'stranger' } }, comments, fail);
    const [comment] = comments.json.mock.calls[0][0].data;
    expect(comment.user).toMatchObject({ _id: 'owner', displayName: 'Owner' });
    expect(comment.user).not.toHaveProperty('email');
    expect(comment.user).not.toHaveProperty('phoneNumber');

    const likes = res();
    await circles.getCircleLikes({ params: { id: 'pub' }, user: { uid: 'owner' } }, likes, fail);
    const [liker] = likes.json.mock.calls[0][0].data;
    expect(liker).toMatchObject({ _id: 'stranger', displayName: 'Stranger' });
    expect(liker).not.toHaveProperty('email');
  });
});

describe('GET /api/videos/user/:userId', () => {
  const { getUserVideos } = require('../video/videoFeedController');
  // The fake has no offset(); page 1 is the same rows.
  Object.getPrototypeOf(mockDb.collection('placeVideos').limit(1)).offset = function offset() { return this; };

  beforeEach(async () => {
    await put('users', 'owner', { displayName: 'Owner' });
    await put('users', 'pal', { displayName: 'Pal', following: ['owner'] });
    await put('users', 'foe', { displayName: 'Foe', blockedBy: ['owner'] });
    const moment = { userId: 'owner', uploadStatus: 'ready', deletedAt: null, createdAt: '2026-09-01', videoUrl: 'v.mp4' };
    await put('placeVideos', 'pub', { ...moment, visibility: 'public' });
    await put('placeVideos', 'priv', { ...moment, visibility: 'private' });
    await put('placeVideos', 'net', { ...moment, visibility: 'network' });
    await put('placeVideos', 'fol', { ...moment, visibility: 'followers' });
    await put('placeVideos', 'flagged', { ...moment, visibility: 'public', moderationStatus: 'removed' });
  });

  const shelf = async (viewer) => {
    const out = res();
    await getUserVideos({ params: { userId: 'owner' }, query: {}, user: viewer ? { uid: viewer } : undefined }, out);
    return out.json.mock.calls[0][0].data.map(v => v.id).sort();
  };

  test('anonymous callers get public, un-moderated moments only (used to get every tier)', async () => {
    expect(await shelf(null)).toEqual(['pub']);
  });

  test('a follower also sees followers-tier; the owner sees everything', async () => {
    expect(await shelf('pal')).toEqual(['fol', 'pub']);
    expect(await shelf('owner')).toEqual(['flagged', 'fol', 'net', 'priv', 'pub']);
  });

  test('blocked either way → empty shelf', async () => {
    expect(await shelf('foe')).toEqual([]);
  });
});

describe('public moment surfaces', () => {
  const { getPublicVideoDetails } = require('../video/videoFeedController');
  const { getVideoShareInfo } = require('../video/videoShareController');

  beforeEach(async () => {
    const moment = { userId: 'owner', placeName: 'Secret Spot', placeAddress: '9 Hidden Ln', uploadStatus: 'ready', deletedAt: null };
    await put('placeVideos', 'pub', { ...moment, visibility: 'public' });
    await put('placeVideos', 'priv', { ...moment, visibility: 'private' });
    await put('placeVideos', 'net', { ...moment, visibility: 'network' });
    await put('placeVideos', 'hidden', { ...moment, visibility: 'public', moderationStatus: 'under_review' });
  });

  test.each(['priv', 'net', 'hidden', 'missing'])('%s moment → 404 on both routes', async (videoId) => {
    const details = res();
    await getPublicVideoDetails({ params: { videoId } }, details);
    expect(details.status).toHaveBeenCalledWith(404);

    const info = res();
    await getVideoShareInfo({ params: { videoId } }, info);
    expect(info.status).toHaveBeenCalledWith(404);
  });

  test('a public moment is still described', async () => {
    const details = res();
    await getPublicVideoDetails({ params: { videoId: 'pub' } }, details);
    expect(details.json.mock.calls[0][0].data.placeName).toBe('Secret Spot');

    const info = res();
    await getVideoShareInfo({ params: { videoId: 'pub' } }, info);
    expect(info.json.mock.calls[0][0].data.placeName).toBe('Secret Spot');
  });
});
