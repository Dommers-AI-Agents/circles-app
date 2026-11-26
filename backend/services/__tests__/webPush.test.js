// Browser notifications (services/webPush.js): where a tap lands, what is
// sent, and which subscriptions are accepted.
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const { webPathFor, payloadFor, cleanSubscription } = require('../webPush');

test('a tap lands where the app would land', () => {
  expect(webPathFor({ type: 'new_message', data: { conversationId: 'c1' } })).toBe('/messages/c1');
  expect(webPathFor({ type: 'new_message', data: {} })).toBe('/messages');
  expect(webPathFor({ type: 'connection_request', data: { fromUserId: 'u1' } })).toBe('/people');
  expect(webPathFor({ type: 'connection_accepted', data: { fromUserId: 'u1' } })).toBe('/user/u1');
  expect(webPathFor({ type: 'new_follower', data: { fromUserId: 'u1' } })).toBe('/user/u1');
  expect(webPathFor({ type: 'store_alert', data: { placeId: 'gp1', kind: 'offer' } })).toBe('/place/gp1');
  expect(webPathFor({ type: 'store_nudge', data: {} })).toBe('/rewards');
  expect(webPathFor({ type: 'place_comment', data: { placeId: 'p1', fromUserId: 'u1' } })).toBe('/place/p1');
  expect(webPathFor({ type: 'circle_shared', data: { circleId: 'c9' } })).toBe('/circle/c9');
  expect(webPathFor({ type: 'something_new', data: {} })).toBe('/notifications');
  // An id that isn't an id never becomes part of a path
  expect(webPathFor({ type: 'place_comment', data: { placeId: '../../admin' } })).toBe('/notifications');
});

test('the payload is short and groups by conversation or place', () => {
  const payload = payloadFor({ type: 'new_message', title: 'Sunil', body: 'x'.repeat(900), data: { conversationId: 'c1' } });
  expect(payload).toEqual({ title: 'Sunil', body: 'x'.repeat(300), url: '/messages/c1', tag: 'c1' });
  expect(payloadFor({ type: 'new_follower', data: {} })).toMatchObject({ title: 'FavCircles', body: '', tag: 'new_follower' });
});

test('only a real https subscription with both keys is kept', () => {
  const good = { endpoint: 'https://fcm.googleapis.com/fcm/send/abc', keys: { p256dh: 'k'.repeat(87), auth: 'a'.repeat(22) }, expirationTime: null };
  expect(cleanSubscription(good)).toEqual({ endpoint: good.endpoint, keys: good.keys });
  expect(() => cleanSubscription({ ...good, endpoint: 'http://insecure.example/x' })).toThrow(/aren't valid/);
  expect(() => cleanSubscription({ ...good, endpoint: 'not a url' })).toThrow();
  expect(() => cleanSubscription({ endpoint: good.endpoint, keys: { p256dh: 'k' } })).toThrow();
  expect(() => cleanSubscription(null)).toThrow();
});
