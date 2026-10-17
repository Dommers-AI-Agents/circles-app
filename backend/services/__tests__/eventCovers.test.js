const { eventCoverUrl, isEventCover } = require('../../config/eventCovers');

test('each event emoji has its own cover; others get the party one', () => {
  expect(eventCoverUrl('🚌')).toBe('https://favcircles.com/images/event-covers/event-1f68c.jpg');
  expect(eventCoverUrl('💍')).toMatch(/event-1f48d\.jpg$/);
  expect(eventCoverUrl('🏖️')).toBe(eventCoverUrl('🏖')); // with or without the variation selector
  expect(eventCoverUrl('⛳️')).toMatch(/event-26f3\.jpg$/);
  expect(eventCoverUrl('🦄')).toMatch(/event-1f389\.jpg$/);
  expect(eventCoverUrl(null)).toMatch(/event-1f389\.jpg$/);
});

test('only our covers count as event covers (a cover someone picked is kept)', () => {
  expect(isEventCover(eventCoverUrl('🚌'))).toBe(true);
  expect(isEventCover('https://firebasestorage.googleapis.com/x.jpg')).toBe(false);
  expect(isEventCover(null)).toBe(false);
});

test('Places from my photos always ends up with a cover', () => {
  jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
  const { photoCircleCover } = require('../importService');
  const { PHOTOS_FALLBACK_COVER: fallback } = require('../../config/eventCovers');
  expect(photoCircleCover(null, 'https://x/1.jpg', fallback)).toBe('https://x/1.jpg');
  expect(photoCircleCover(null, undefined, fallback)).toBe(fallback);
  expect(photoCircleCover(fallback, 'https://x/2.jpg', fallback)).toBe('https://x/2.jpg'); // a real photo replaces the placeholder
  expect(photoCircleCover('https://mine.jpg', 'https://x/3.jpg', fallback)).toBe('https://mine.jpg'); // a chosen cover stays
});
