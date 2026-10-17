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
