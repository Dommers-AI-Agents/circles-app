jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const svc = require('../storeWelcomeEmailService');

const store = { name: "Sal's Bakery", address: '1 Main St, Charlotte, NC 28203', photoUrl: 'https://x/p.jpg', placeUrl: 'https://api.favcircles.com/place/g1' };
const people = [{ userId: 'u2', displayName: 'Dana Lee', profilePicture: null, reason: "Saved Sal's Bakery" }];

describe('store welcome email', () => {
  test('welcomes them, shows the store, what the app does, people and the app button', () => {
    const { subject, html, text } = svc.buildEmail({ user: { displayName: 'Jane Doe' }, store, people });
    expect(subject).toBe("Welcome to FavCircles — Sal's Bakery is on your map");
    expect(html).toContain('You saved Sal');
    expect(html).toContain('Hi Jane,');
    expect(html).toContain('What FavCircles does');
    expect(html).toContain('Dana Lee');
    expect(html).toContain('/user/u2');
    expect(html).toContain('Get the FavCircles app');
    expect(text).toContain('Get the FavCircles app: https://apps.apple.com/');
  });

  test('points and rewards only when the store has them', () => {
    const none = svc.buildEmail({ user: {}, store });
    expect(none.html).not.toContain('KEEP EARNING');
    expect(none.html).not.toMatch(/\+\d+ points/);
    const live = svc.buildEmail({ user: {}, store, awardedPoints: 25,
      rewards: { earnRate: 25, balance: 25, offers: [{ title: 'Free drip coffee', pointsCost: 100 }] } });
    expect(live.html).toContain('+25 points at');
    expect(live.html).toContain('Every visit earns 25 points');
    expect(live.html).toContain('Free drip coffee');
  });

  test('only accounts that joined at a store (not the generic code) skip the generic welcome', () => {
    expect(svc.isStoreSignup({ acquisitionSource: 'app_clip', acquisitionVenueId: 'v1' })).toBe(true);
    expect(svc.isStoreSignup({ acquisitionSource: 'app_clip', acquisitionVenueId: 'v1', acquisitionGeneric: true })).toBe(false);
    expect(svc.isStoreSignup({})).toBe(false);
  });
});
