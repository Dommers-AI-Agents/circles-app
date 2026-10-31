// The App Clip's one reminder (2026-10-31) and the clip's preview fields
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), getAuth: () => ({}) }));
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const svc = require('../clipReminderService');

const HOUR = 60 * 60 * 1000;
const TOKEN = 'ab'.repeat(32);

describe('clip reminders', () => {
  test('words follow what they have at the store', () => {
    const venue = { venueId: 'v1', venueName: 'Test Bakery' };
    expect(svc.reminderFor({ venue, venuePoints: 25 }).body).toMatch(/points are saved/);
    expect(svc.reminderFor({ venue, venuePoints: 0 }).body).toBe('Get FavCircles to keep Test Bakery on your map.');
    expect(svc.reminderFor({ venue: { genericJoin: true } }).body).toBe('Get FavCircles to start your map.');
  });

  test('due two hours after sign-in, never after Apple’s 8-hour window', () => {
    const row = { sent: false, createdAt: 0, sendAfter: 2 * HOUR };
    expect(svc.isDue(row, HOUR)).toBe(false);
    expect(svc.isDue(row, 2 * HOUR)).toBe(true);
    expect(svc.isDue(row, 8 * HOUR)).toBe(false);
    expect(svc.isDue({ ...row, sent: true }, 3 * HOUR)).toBe(false);
  });

  test('register keeps one row per person; a sent reminder is never re-armed', async () => {
    const db = new FakeFirestore({ namespaced: true });
    await expect(svc.registerDevice('u1', { token: 'nope' }, { db, now: 0 })).rejects.toMatchObject({ code: 'TOKEN_INVALID' });
    await svc.registerDevice('u1', { token: TOKEN, code: 'abc123' }, { db, now: 0 });
    expect(db.rows('clipDevices').get('u1')).toMatchObject({ code: 'ABC123', sendAfter: 2 * HOUR, sent: false, environment: 'production' });
    await db.collection('clipDevices').doc('u1').update({ sent: true });
    await svc.registerDevice('u1', { token: 'cd'.repeat(32), code: 'XYZ999' }, { db, now: HOUR });
    expect(db.rows('clipDevices').get('u1')).toMatchObject({ token: TOKEN, sent: true });
  });

  test('sends once to people without the app; skips installers and stale rows', async () => {
    const db = new FakeFirestore({ namespaced: true });
    db.rows('users').set('u1', { venueBalances: {} });
    db.rows('users').set('u2', { clipInstallConvertedAt: 'yes' });
    db.rows('clipDevices').set('u1', { token: TOKEN, code: 'REG001', environment: 'production', createdAt: 0, sendAfter: 2 * HOUR, sent: false });
    db.rows('clipDevices').set('u2', { token: TOKEN, code: 'REG001', createdAt: 0, sendAfter: 2 * HOUR, sent: false });
    db.rows('clipDevices').set('u3', { token: TOKEN, code: 'REG001', createdAt: -9 * HOUR, sendAfter: -7 * HOUR, sent: false });
    const pushes = [];
    const deps = {
      apns: { configured: () => true, sendAlert: async (p) => { pushes.push(p); return true; } },
      rewardService: {
        findVenueByCode: async () => ({ venueId: 'v1', venueName: 'Test Bakery' }),
        venueBalancesFrom: () => [{ venueId: 'v1', points: 25 }]
      }
    };
    expect(await svc.sendDue({ db, now: 3 * HOUR, deps })).toEqual({ sent: 1, installed: 1, expired: 1 });
    expect(pushes).toHaveLength(1);
    expect(pushes[0]).toMatchObject({ topic: 'com.favcircles.circles.Clip', title: 'Test Bakery', expiresAt: 8 * HOUR });
    expect(await svc.sendDue({ db, now: 4 * HOUR, deps })).toEqual({ sent: 0, installed: 0, expired: 0 });
  });

  test('without an APNs key nothing is sent or marked', async () => {
    const db = new FakeFirestore({ namespaced: true });
    db.rows('clipDevices').set('u1', { token: TOKEN, createdAt: 0, sendAfter: 0, sent: false });
    const out = await svc.sendDue({ db, now: 3 * HOUR, deps: { apns: { configured: () => false }, rewardService: {} } });
    expect(out.skipped).toMatch(/not configured/);
    expect(db.rows('clipDevices').get('u1').sent).toBe(false);
  });
});

describe('clip preview location', () => {
  test('any stored shape becomes {latitude, longitude}; junk is null', () => {
    jest.isolateModules(() => {
      jest.doMock('../rewardService', () => ({}));
      jest.doMock('../placePhotoService', () => ({ venueCoverUrl: async () => null }));
      const { clipLocation } = require('../../controllers/clipController');
      expect(clipLocation({ latitude: 35.2, longitude: -80.8 })).toEqual({ latitude: 35.2, longitude: -80.8 });
      expect(clipLocation({ _latitude: 35.2, _longitude: -80.8 })).toEqual({ latitude: 35.2, longitude: -80.8 });
      expect(clipLocation({ lat: 1, lng: 2 })).toEqual({ latitude: 1, longitude: 2 });
      expect(clipLocation(null)).toBeNull();
      expect(clipLocation({ latitude: 'x' })).toBeNull();
    });
  });

  test('the preview carries the store photo and location; the generic code neither', async () => {
    let store; let generic;
    await jest.isolateModulesAsync(async () => {
      const venue = { venueId: 'v1', venueName: 'Test Bakery', kind: 'register', location: { latitude: 35, longitude: -80 }, globalPlaceId: 'g1' };
      jest.doMock('../rewardService', () => ({
        findVenueByCode: async (code) => (code === 'JOINUS' ? { venueId: 'g', genericJoin: true } : venue),
        incrementVenueStats: () => {},
        effectiveEarnRate: () => 25
      }));
      jest.doMock('../placePhotoService', () => ({ venueCoverUrl: async () => 'https://x/cover.jpg' }));
      jest.doMock('../ownerSubscriptionService', () => ({ registerScanEarns: async () => ({ earns: true }) }));
      const { getVenuePreview } = require('../../controllers/clipController');
      const call = async (code) => {
        let out;
        await getVenuePreview({ params: { code } }, { status() { return this; }, json(b) { out = b; return this; } });
        return out.data;
      };
      store = await call('REG001');
      generic = await call('JOINUS');
    });
    expect(store).toMatchObject({ coverUrl: 'https://x/cover.jpg', location: { latitude: 35, longitude: -80 }, earnRate: 25 });
    expect(generic).toMatchObject({ generic: true, coverUrl: null, location: null });
  });
});

