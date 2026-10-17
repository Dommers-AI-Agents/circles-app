// When the welcome suggestion goes out: once, near the new user when we know
// where they are, otherwise after a day without a location fix.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
jest.mock('../notificationService', () => ({ notifyDirectedSuggestion: jest.fn(async () => {}) }));

const OnboardingService = require('../onboardingService');
const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const sent = () => [...mockDb.rows('suggestions').values()];
const ago = (ms) => new Date(Date.now() - ms).toISOString();
const charlotte = { latitude: 35.2169, longitude: -80.8593 };

beforeEach(async () => {
  for (const name of ['users', 'places', 'circles', 'suggestions']) mockDb.rows(name).clear();
  await put('users', 'wes', { email: 'sgroiwes@gmail.com' });
  await put('circles', 'pub', { owner: 'wes', privacy: 'public' });
  await put('places', 'shore', { addedBy: 'wes', circleId: 'pub', name: 'La Dolce Vita', userRating: 10,
    location: { type: 'Point', coordinates: [-74.0218, 40.1784] } });
  await put('places', 'clt', { addedBy: 'wes', circleId: 'pub', name: 'Optimist Hall', userRating: 8,
    location: { type: 'Point', coordinates: [-80.8253, 35.2340] } });
});

const newUser = async (data) => { await put('users', 'u1', data); return data; };

test('a location fix sends one nearby, once', async () => {
  const u = await newUser({ createdAt: ago(60000) });
  await OnboardingService.maybeSendWelcomeSuggestion('u1', u, charlotte);
  expect(sent().map(s => s.placeId)).toEqual(['clt']);
  const again = (await mockDb.collection('users').doc('u1').get()).data();
  await OnboardingService.maybeSendWelcomeSuggestion('u1', again, charlotte);
  await OnboardingService.sendWelcomeSuggestion('u1', u, charlotte);
  expect(sent()).toHaveLength(1);
});

test('no fix: waits a day, then sends from anywhere', async () => {
  await OnboardingService.maybeSendWelcomeSuggestion('u1', await newUser({ createdAt: ago(3600000) }), null);
  expect(sent()).toHaveLength(0);
  await OnboardingService.maybeSendWelcomeSuggestion('u1', await newUser({ createdAt: ago(2 * 86400000) }), null);
  expect(sent().map(s => s.placeId)).toEqual(['shore']);
});

test('older accounts and ones that already got one are left alone', async () => {
  await OnboardingService.maybeSendWelcomeSuggestion('u1', await newUser({ createdAt: ago(8 * 86400000) }), charlotte);
  expect(sent()).toHaveLength(0);
  await put('suggestions', 'old', { userId: 'wes', recipientId: 'u1', placeId: 'x' });
  await OnboardingService.maybeSendWelcomeSuggestion('u1', await newUser({ createdAt: ago(60000) }), charlotte);
  expect(sent()).toHaveLength(1);
});
