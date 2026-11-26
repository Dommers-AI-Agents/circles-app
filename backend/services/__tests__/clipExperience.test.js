const { buildClipExperience, ROW_KINDS } = require('../clipExperience');

const venue = { venueName: 'Caffeena Coffee House' };
const globalPlace = { googleData: { rating: 4.7, userRatingsTotal: 812, website: 'https://caffeena.com/' } };
const base = { venue, globalPlace, loyaltyLive: false, offers: [], earnRate: null, savePoints: 0,
  coverUrl: 'https://x/cover.jpg', photoUrls: ['https://x/cover.jpg', 'https://x/inside.jpg'] };

describe('buildClipExperience', () => {
  test('a store without live rewards: promises, no points anywhere', () => {
    const e = buildClipExperience(base);
    expect(e.welcome.rows.map((r) => r.kind)).toEqual(['menu', 'specials', 'events', 'announcements']);
    expect(e.welcome.button).toBe('Save Caffeena Coffee House & stay connected');
    expect(e.welcome.ratingLine).toBe('4.7 on Google · 812 reviews');
    expect(e.connect.pointsLine).toBeNull();
    expect(e.done.showRewards).toBe(false);
    expect(e.done.showWallet).toBe(false);
    expect(JSON.stringify(e)).not.toMatch(/only|no one|nobody|yet/i);
  });

  test('the sign-in screen uses a second photo, else the cover', () => {
    expect(buildClipExperience(base).connect.photoUrl).toBe('https://x/inside.jpg');
    expect(buildClipExperience({ ...base, photoUrls: ['https://x/cover.jpg'] }).connect.photoUrl).toBe('https://x/cover.jpg');
  });

  test('live rewards: the rewards row, points and Wallet', () => {
    const e = buildClipExperience({ ...base, loyaltyLive: true, earnRate: 25, savePoints: 25,
      offers: [{ title: 'Free latte', pointsCost: 100 }] });
    expect(e.welcome.rows[0]).toEqual({ kind: 'rewards', title: 'Rewards', detail: '100 points = Free latte' });
    expect(e.connect.pointsLine).toBe('+25 points when it’s saved');
    expect(e.done.showWallet).toBe(true);
  });

  test('the owner can hide points but never show them where rewards are not live', () => {
    const live = { ...base, loyaltyLive: true, earnRate: 25, savePoints: 25 };
    const hidden = buildClipExperience({ ...live, venue: { ...venue, clipExperience: { showRewards: false } } });
    expect(hidden.welcome.rows.some((r) => r.kind === 'rewards')).toBe(false);
    expect(hidden.connect.pointsLine).toBeNull();
    const forced = buildClipExperience({ ...base, venue: { ...venue, clipExperience: { showRewards: true } } });
    expect(forced.done.showRewards).toBe(false);
  });

  test('owner overrides: short name, words, row order, photo', () => {
    const e = buildClipExperience({ ...base, venue: { ...venue, clipExperience: {
      shortName: 'Caffeena', welcomeLine: 'Coffee and cars, every month.', rows: ['events', 'menu', 'bogus', 'events'],
      connectPhotoUrl: 'https://x/cars.jpg', doneLine: 'See you at the next meet.' } } });
    expect(e.welcome.button).toBe('Save Caffeena & stay connected');
    expect(e.welcome.title).toBe('Caffeena Coffee House');
    expect(e.welcome.line).toBe('Coffee and cars, every month.');
    expect(e.welcome.rows.map((r) => r.kind)).toEqual(['events', 'menu']);
    expect(e.connect.photoUrl).toBe('https://x/cars.jpg');
    expect(e.done.line).toBe('See you at the next meet.');
    expect(e.connect.alerts).toBe('Get alerts from Caffeena: specials, events and announcements.');
  });

  test('no menu link: no menu row; no rating: no rating line', () => {
    const e = buildClipExperience({ ...base, globalPlace: null });
    expect(e.welcome.rows.some((r) => r.kind === 'menu')).toBe(false);
    expect(e.welcome.ratingLine).toBeNull();
    expect(ROW_KINDS).toContain('menu');
  });
});
