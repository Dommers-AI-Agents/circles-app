// The settings saves answer with the person's own profile: app builds before
// 1.4.4 decode `user` from the notification-preferences reply and showed
// "Oops" without it (2026-11-01).
const { ownProfileJson } = require('../ownProfileResponse');

test('carries the id the app decodes and the saved notification preferences', () => {
  const out = ownProfileJson({ id: 'u1', displayName: 'Wes', email: 'w@x.com', notificationPreferences: { newMessages: false, dailyQuote: true } });
  expect(out._id).toBe('u1');
  expect(out.displayName).toBe('Wes');
  expect(out.notificationPreferences).toEqual({ newMessages: false, dailyQuote: true });
  expect(out.followersCount).toBe(0);
  expect(out.zipcode).toBeNull();
});
