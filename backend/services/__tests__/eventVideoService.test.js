// Event videos (Wes, 2026-10-10): free clips up to 15 s, 5 per person per
// event; Premium up to 60 s, 20 per person per event; oversize files refused.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
const mockEventRef = { id: 'ev1', update: jest.fn(async () => {}) };
const mockSizes = { video: 3 * 1024 * 1024, poster: 200 * 1024, thumb: 20 * 1024 };
let mockStatus = 'none';

jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: jest.fn() }));
jest.mock('../eventLiveActivityService', () => ({ refreshSoon: jest.fn() }));
jest.mock('../subscriptionLimitService', () => ({ getUserSubscriptionData: async () => ({ subscriptionStatus: mockStatus }) }));
jest.mock('firebase-admin/firestore', () => ({
  FieldValue: { increment: (n) => ({ __increment: n }) },
  FieldPath: function FieldPath(...parts) { this.parts = parts; }
}));
jest.mock('firebase-admin/storage', () => ({
  getStorage: () => ({ bucket: () => ({
    name: 'test-bucket',
    file: (path) => ({
      getSignedUrl: async () => [`https://signed/${path}`],
      getMetadata: async () => {
        const slot = path.endsWith('_thumb.jpg') ? 'thumb' : path.endsWith('.jpg') ? 'poster' : 'video';
        return [{ size: String(mockSizes[slot]) }];
      },
      delete: jest.fn(async () => {})
    })
  }) })
}));
jest.mock('../eventService', () => ({
  loadAsMember: async (eventId, uid) => {
    if (uid === 'stranger') { const e = new Error('Join'); e.status = 403; e.code = 'not_member'; throw e; }
    return { ref: mockEventRef, data: { hostId: 'host', name: 'Party Bus', memberIds: ['me', 'pal'], members: { me: { name: 'Me' } } } };
  },
  photosCol: () => mockDb.collection('eventPhotos'),
  parsePhotoCapture: () => ({ takenAt: null, lat: null, lng: null }),
  toClientPhoto: (doc) => ({ id: doc.id, ...doc.data() }),
  DEFAULT_EMOJI: '🚌'
}));

const svc = require('../eventVideoService');
const { maxEventVideoBytes } = require('../uploadSizeGuard');

beforeEach(() => {
  mockDb.collections.clear();
  mockStatus = 'none';
  Object.assign(mockSizes, { video: 3 * 1024 * 1024, poster: 200 * 1024, thumb: 20 * 1024 });
});

const start = (secs, uid = 'me') => svc.startVideo('ev1', uid, { durationSec: secs });
const rows = async () => (await mockDb.collection('eventPhotos').limit(100).get()).docs.map(d => ({ id: d.id, ...d.data() }));

describe('limits', () => {
  test('free: a 15-second clip is fine, a 16-second one asks for Premium', async () => {
    await expect(start(15)).resolves.toHaveProperty('videoId');
    await expect(start(16)).rejects.toMatchObject({ status: 403, code: 'video_too_long', details: { upgradeRequired: true, maxSeconds: 15 } });
  });

  test('premium: up to 60 seconds', async () => {
    mockStatus = 'active';
    await expect(start(60)).resolves.toHaveProperty('videoId');
    await expect(start(61)).rejects.toMatchObject({ code: 'video_too_long', details: { upgradeRequired: false } });
  });

  test('free: 5 per person per event, then the paywall', async () => {
    for (let i = 0; i < 5; i++) await start(5);
    await expect(start(5)).rejects.toMatchObject({ status: 403, code: 'video_limit', details: { upgradeRequired: true, perEvent: 5 } });
    // Someone else in the same event has their own 5
    await expect(start(5, 'pal')).resolves.toHaveProperty('videoId');
  });

  test('premium: a hard cap of 20 per person per event', async () => {
    mockStatus = 'active';
    for (let i = 0; i < 20; i++) await start(30);
    await expect(start(30)).rejects.toMatchObject({ code: 'video_limit', details: { upgradeRequired: false, perEvent: 20 } });
  });

  test('an abandoned upload stops counting after two hours', () => {
    const now = Date.now();
    const old = { kind: 'video', uploaderId: 'me', status: 'uploading', createdAt: new Date(now - svc.UPLOAD_TTL_MS - 1).toISOString() };
    const fresh = { ...old, createdAt: new Date(now - 1000).toISOString() };
    expect(svc.countsTowardCap(old, 'me', now)).toBe(false);
    expect(svc.countsTowardCap(fresh, 'me', now)).toBe(true);
    expect(svc.countsTowardCap({ ...old, status: 'ready' }, 'me', now)).toBe(true);
    expect(svc.countsTowardCap({ kind: 'photo', uploaderId: 'me' }, 'me', now)).toBe(false);
  });

  test('a clip with no length is refused', async () => {
    await expect(start(0)).rejects.toMatchObject({ code: 'invalid_duration' });
  });

  test('members only', async () => {
    await expect(start(5, 'stranger')).rejects.toMatchObject({ code: 'not_member' });
  });
});

describe('upload and publish', () => {
  test('start reserves a hidden row with server-named files and signed URLs', async () => {
    const r = await start(10);
    expect(r.uploadUrls.video).toBe(`https://signed/events/ev1/videos/me/${r.videoId}.mp4`);
    const [row] = await rows();
    expect(row).toMatchObject({ kind: 'video', status: 'uploading', durationSec: 10 });
    expect(svc.isVisible(row)).toBe(false);
  });

  test('finish publishes with the poster as the image (old apps show a still)', async () => {
    const { videoId } = await start(10);
    const photo = await svc.finishVideo('ev1', 'me', videoId);
    expect(photo.status).toBe('ready');
    expect(photo.videoUrl).toContain(encodeURIComponent(`events/ev1/videos/me/${videoId}.mp4`));
    expect(photo.imageUrl).toContain('.jpg');
    expect(mockEventRef.update).toHaveBeenCalledWith(expect.objectContaining({ lastPhoto: expect.objectContaining({ kind: 'video' }) }));
  });

  test('a file too big for a free clip is deleted and refused', async () => {
    const { videoId } = await start(10);
    mockSizes.video = maxEventVideoBytes(15) + 1;
    await expect(svc.finishVideo('ev1', 'me', videoId)).rejects.toMatchObject({ status: 413, code: 'video_too_large' });
    expect(await rows()).toHaveLength(0);
  });

  test('only the uploader can finish their video', async () => {
    const { videoId } = await start(10);
    await expect(svc.finishVideo('ev1', 'pal', videoId)).rejects.toMatchObject({ code: 'not_found' });
  });

  test('byte cap: about 2 Mbit/s plus 2 MB', () => {
    expect(maxEventVideoBytes(15)).toBe(15 * 250 * 1024 + 2 * 1024 * 1024);
    expect(maxEventVideoBytes(60)).toBeLessThan(18 * 1024 * 1024);
  });
});
