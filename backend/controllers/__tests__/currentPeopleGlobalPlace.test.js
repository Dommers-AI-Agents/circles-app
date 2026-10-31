// A venue's photos/videos name the uploader as they are NOW (reviews already
// did); the name stored at upload time stays for a deleted account.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getMessaging: () => ({}),
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));
jest.mock('../../services/globalPlaceResolver', () => ({
  resolveGlobalPlace: async (id) => ({ globalPlaceDoc: await mockDb.collection('globalPlaces').doc(id).get() }),
  createGlobalPlaceFromLegacy: jest.fn()
}));

const controller = require('../globalPlaceController');
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const call = async (handler, req) => {
  let body;
  const res = { status() { return this; }, json(b) { body = b; return this; } };
  await handler({ params: {}, query: {}, user: { uid: 'viewer' }, ...req }, res, (e) => { throw e; });
  return body;
};

beforeAll(async () => {
  await put('users', 'sal', { displayName: 'Sal Sgroi', profilePicture: 'https://x/sal.jpg' });
  await put('globalPlaces', 'g1', {
    name: 'Cafe',
    photos: [
      { id: 'ph1', url: 'https://x/1.jpg', uploadedBy: 'sal', uploadedByName: 'Salvatore' },
      { id: 'ph2', url: 'https://x/2.jpg', uploadedBy: 'gone', uploadedByName: 'Ghost' },
      { id: 'ph3', url: 'https://x/3.jpg', uploadedBy: 'google', source: 'google' }
    ],
    videos: [{ id: 'v1', videoUrl: 'https://x/v.mp4', uploadedBy: 'sal', uploadedByName: 'Salvatore' }],
    publicReviews: [{ userId: 'sal', userName: 'Salvatore', text: 'good' }]
  });
});

test('place page: current uploader and reviewer names; deleted and imported rows unchanged', async () => {
  const body = await call(controller.getGlobalPlace, { params: { placeId: 'g1' } });
  const place = body.data.globalPlace;
  expect(place.photos.map(p => p.uploadedByName)).toEqual(['Sal Sgroi', 'Ghost', undefined]);
  expect('uploadedByName' in place.photos[2]).toBe(false);
  expect(place.videos[0].uploadedByName).toBe('Sal Sgroi');
  expect(place.publicReviews[0]).toMatchObject({ userName: 'Sal Sgroi', userPhoto: 'https://x/sal.jpg' });
});

test('photos debug: current uploader names', async () => {
  const body = await call(controller.getPhotosDebug, { params: { placeId: 'g1' } });
  expect(body.data.photos.map(p => p.uploadedByName)).toEqual(['Sal Sgroi', 'Ghost', undefined]);
});
