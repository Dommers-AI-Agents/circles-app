// Opening the thing a notification is about clears it from the red dot.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const { originFor, rowMatches, markSeen } = require('../notificationSeen');

const row = async (id, type, data, read = false) =>
  mockDb.collection('notifications').doc(id).set({ userId: 'wes', type, data, read });
const readIds = () => [...mockDb.rows('notifications').entries()].filter(([, r]) => r.read).map(([id]) => id).sort();

beforeEach(() => {
  mockDb.rows('notifications').clear();
  mockDb.rows('places').clear();
});

describe('originFor', () => {
  test('requests that open one thing', () => {
    expect(originFor('POST', '/messages/conversations/c1/read')).toEqual({ kind: 'conversation', id: 'c1' });
    expect(originFor('GET', '/places/global/g1')).toEqual({ kind: 'place', id: 'g1' });
    expect(originFor('GET', '/places/p1/comments')).toEqual({ kind: 'place', id: 'p1' });
    expect(originFor('GET', '/activities/a1/comments')).toEqual({ kind: 'activity', id: 'a1' });
    expect(originFor('GET', '/videos/v1')).toEqual({ kind: 'video', id: 'v1' });
    expect(originFor('GET', '/users/sal')).toEqual({ kind: 'person', id: 'sal' });
    expect(originFor('POST', '/connections/k1/accept')).toEqual({ kind: 'connection', id: 'k1' });
    expect(originFor('GET', '/widgets/care/asks', { planId: 'plan1' })).toEqual({ kind: 'carePlan', id: 'plan1' });
  });
  test('lists and other verbs are not an origin', () => {
    expect(originFor('GET', '/users/me')).toBeNull();
    expect(originFor('GET', '/places/nearby')).toBeNull();
    expect(originFor('GET', '/messages/conversations')).toBeNull();
    expect(originFor('DELETE', '/places/p1')).toBeNull();
    expect(originFor('GET', '/widgets/care/asks', {})).toBeNull();
  });
});

test('a row matches only its own kind of origin', () => {
  const ids = new Set(['c1']);
  expect(rowMatches({ type: 'new_message', data: { conversationId: 'c1' } }, 'conversation', ids)).toBe(true);
  expect(rowMatches({ type: 'new_message', data: { conversationId: 'c2' } }, 'conversation', ids)).toBe(false);
  expect(rowMatches({ type: 'place_like', data: { conversationId: 'c1' } }, 'conversation', ids)).toBe(false);
});

test('reading a conversation clears its message rows, not other chats', async () => {
  await row('m1', 'new_message', { conversationId: 'c1' });
  await row('m2', 'new_message', { conversationId: 'c1' });
  await row('m3', 'new_message', { conversationId: 'c2' });
  expect(await markSeen('wes', { kind: 'conversation', id: 'c1' })).toBe(2);
  expect(readIds()).toEqual(['m1', 'm2']);
});

test('opening the venue clears a like on any save of it', async () => {
  await mockDb.collection('places').doc('wesSave').set({ globalPlaceId: 'cafe' });
  await row('like', 'place_like', { placeId: 'wesSave' });
  await row('other', 'place_like', { placeId: 'elsewhere' });
  expect(await markSeen('wes', { kind: 'place', id: 'cafe' })).toBe(1);
  expect(readIds()).toEqual(['like']);
});

test('a profile visit clears that person\'s accepted / follow rows only', async () => {
  await row('acc', 'connection_accepted', { fromUserId: 'sal' });
  await row('fol', 'new_follower', { fromUserId: 'sal' });
  await row('req', 'connection_request', { fromUserId: 'sal', connectionId: 'k1' });
  await markSeen('wes', { kind: 'person', id: 'sal' });
  expect(readIds()).toEqual(['acc', 'fol']);
  await markSeen('wes', { kind: 'connection', id: 'k1' });
  expect(readIds()).toEqual(['acc', 'fol', 'req']);
});

test('opening a check-in post clears the check-in notification', async () => {
  await mockDb.collection('activities').doc('act').set({ type: 'check_in', metadata: { checkInId: 'x' } });
  await row('ci', 'check_in', { checkInId: 'x' });
  await row('other', 'check_in', { checkInId: 'y' });
  await markSeen('wes', { kind: 'activity', id: 'act' });
  expect(readIds()).toEqual(['ci']);
});
