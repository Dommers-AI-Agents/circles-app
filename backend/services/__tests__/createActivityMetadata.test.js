// The activity row keeps the fields the feed renders from (2026-11-16: the
// moment's clip URL, so the Activity feed can loop it inline).
const { FakeFirestore, FakeFieldValue: MockFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: MockFieldValue,
  admin: { firestore: { FieldValue: { serverTimestamp: () => 'now' } } }
}));
jest.mock('../activity/hiddenPlaceGate', () => ({ isAboutHiddenVenue: async () => false }));

const { createActivity } = require('../activity/createActivity');

test('a moment row carries its clip, thumbnail and content type; unknown keys are dropped', async () => {
  const id = await createActivity('video_uploaded', 'u1', 'place_video', 'v1', 'Sal’s', {
    videoThumbnail: 'https://x/t.jpg', videoUrl: 'https://x/c.mp4', contentType: 'video', placeId: 'p1', bogus: 'no'
  });
  expect(id).toBeTruthy();
  const row = mockDb.rows('activities').get(id);
  expect(row.metadata).toMatchObject({ videoThumbnail: 'https://x/t.jpg', videoUrl: 'https://x/c.mp4', contentType: 'video', placeId: 'p1' });
  expect(row.metadata.bogus).toBeUndefined();
  // Rows without a clip say so plainly
  const plain = await createActivity('check_in', 'u1', 'place', 'p1', 'Sal’s', { placePhoto: 'https://x/p.jpg', latitude: 35.2, longitude: -80.8 });
  expect(mockDb.rows('activities').get(plain).metadata).toMatchObject({ videoUrl: null, placePhoto: 'https://x/p.jpg', latitude: 35.2, longitude: -80.8 });
});
