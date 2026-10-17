// Store alerts: a follower's bell is the opt-in, only new posts push, and a
// store reaches its followers at most once a day (Wes, 2026-10-17).
const { FakeFirestore, FakeFieldValue } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../notificationService', () => ({ sendToUser: jest.fn(async () => ({ success: true })) }));

const notificationService = require('../notificationService');
const { setAlerts, alertFollowers, alertText, alertAudience } = require('../placeAlerts');
const { GLOBAL_COLLECTIONS } = require('../../models/GlobalPlace');

const PLACE = 'pasta';
const ref = () => mockDb.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(PLACE);
const NOW = Date.UTC(2026, 9, 17, 18, 0);

beforeEach(async () => {
  mockDb.rows(GLOBAL_COLLECTIONS.GLOBAL_PLACES).clear();
  mockDb.rows('pushThrottle').clear();
  notificationService.sendToUser.mockClear();
  await ref().set({ name: 'Pasta & Provisions', followers: ['wes', 'sal', 'kate'], alertFollowerIds: [] });
});

describe('the bell', () => {
  test('a follower can turn it on and off; nobody is on by default', async () => {
    expect(alertAudience((await ref().get()).data())).toEqual([]);
    expect(await setAlerts(ref(), 'wes', true)).toEqual({ alertsOn: true, alertFollowersCount: 1 });
    expect((await ref().get()).data().alertFollowerIds).toEqual(['wes']);
    expect(await setAlerts(ref(), 'wes', false)).toEqual({ alertsOn: false, alertFollowersCount: 0 });
    expect((await ref().get()).data().alertFollowerIds).toEqual([]);
  });

  test('only a follower can turn it on', async () => {
    await expect(setAlerts(ref(), 'stranger', true)).rejects.toMatchObject({ status: 409 });
  });

  test('someone who unfollowed is never alerted, even with a stale bell', () => {
    expect(alertAudience({ followers: ['sal'], alertFollowerIds: ['sal', 'gone'] })).toEqual(['sal']);
  });
});

describe('alerts', () => {
  test('a new post reaches bell-on followers only, as a store_alert to the place', async () => {
    await setAlerts(ref(), 'wes', true);
    await setAlerts(ref(), 'sal', true);
    const result = await alertFollowers({ globalPlaceId: PLACE, placeName: 'Pasta & Provisions',
      kind: 'announcement', title: 'Half-price wine', message: 'Tonight from 5 to 7', now: NOW });
    expect(result).toEqual({ audience: 2, sent: 2, throttled: false });
    expect(notificationService.sendToUser).toHaveBeenCalledTimes(2);
    expect(notificationService.sendToUser).toHaveBeenCalledWith('wes', expect.objectContaining({
      type: 'store_alert',
      title: 'Pasta & Provisions: Half-price wine',
      body: 'Tonight from 5 to 7',
      data: expect.objectContaining({ type: 'store_alert', placeId: PLACE })
    }));
    expect(notificationService.sendToUser).not.toHaveBeenCalledWith('kate', expect.anything());
  });

  test('at most once a day per store; the next day it pushes again', async () => {
    await setAlerts(ref(), 'wes', true);
    await alertFollowers({ globalPlaceId: PLACE, kind: 'offer', title: 'Free tiramisu', now: NOW });
    const second = await alertFollowers({ globalPlaceId: PLACE, kind: 'offer', title: 'Another', now: NOW + 60 * 60 * 1000 });
    expect(second).toEqual({ audience: 1, sent: 0, throttled: true });
    expect(notificationService.sendToUser).toHaveBeenCalledTimes(1);
    const nextDay = await alertFollowers({ globalPlaceId: PLACE, kind: 'offer', title: 'Next', now: NOW + 25 * 60 * 60 * 1000 });
    expect(nextDay.sent).toBe(1);
  });

  test('nobody with the bell on: no push, no throttle used', async () => {
    const result = await alertFollowers({ globalPlaceId: PLACE, kind: 'offer', title: 'x', now: NOW });
    expect(result).toEqual({ audience: 0, sent: 0, throttled: false });
    expect(mockDb.rows('pushThrottle').size).toBe(0);
  });

  test('wording for offers, announcements and events', () => {
    expect(alertText('Pasta & Provisions', 'offer', 'Free tiramisu')).toEqual({ title: 'Pasta & Provisions', body: 'New reward: Free tiramisu' });
    expect(alertText('Pasta & Provisions', 'event', 'Trivia night', 'Thursday at 8')).toEqual({ title: 'Pasta & Provisions: Trivia night', body: 'Thursday at 8' });
    expect(alertText(null, 'announcement', 'Open late', '')).toEqual({ title: 'A place you follow: Open late', body: 'Open late' });
  });
});
