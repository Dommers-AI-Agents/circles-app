jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../rewardService', () => ({
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`,
  effectiveEarnRate: (venue) => venue.earnRate || 10
}));
jest.mock('../placePhotoService', () => ({ coverUrl: () => null }));
jest.mock('../appStoreConnect/ascClient', () => ({ configured: () => false, get: jest.fn(), post: jest.fn(), patch: jest.fn() }));
const svc = require('../appClipExperienceService');

describe('appClipExperienceService copy', () => {
  test('title is the store name, cut to Apple\'s 30 characters', () => {
    const long = svc.copyFor({ venueName: 'The Absolutely Enormous Name Of A Coffee Place', earnRate: 25 }, 'register');
    expect(long.title.length).toBeLessThanOrEqual(svc.TITLE_MAX);
    expect(long.title.endsWith('…')).toBe(true);
    expect(svc.copyFor({ venueName: 'Tommy\'s Tavern + Tap' }, 'window').title).toBe('Tommy\'s Tavern + Tap');
  });

  test('a store card says each thing once: hook in the picture, name in the title, why in the subtitle', async () => {
    const register = svc.copyFor({ venueName: 'Test Bakery', earnRate: 25 }, 'register');
    expect(register.hook).toEqual(['Earn 25 points', 'every visit.']);
    const window = svc.copyFor({ venueName: 'Test Bakery' }, 'window');
    expect(window.hook).toEqual(['Love it here?', 'Save us.']);
    for (const copy of [register, window]) {
      expect(copy.title).toBe('Test Bakery');
      expect(copy.subtitle).toBe('Stay connected. Catch every moment.');
      expect(copy.subtitle.length).toBeLessThanOrEqual(svc.SUBTITLE_MAX);
      const picture = [...copy.hook, copy.lead || ''].join(' ');
      expect(picture).not.toMatch(/FavCircles|Test Bakery/);
      expect(copy.subtitle).not.toMatch(/save|love|points/i);
    }
    const jpeg = await svc.headerImagePNG({ venueName: 'Test Bakery' }, 'window', null);
    const meta = await require('sharp')(jpeg).metadata();
    expect([meta.format, meta.width, meta.height]).toEqual(['jpeg', 1800, 1200]);
  });

  test('the generic join card says what FavCircles is for, never its name, and no line repeats another', async () => {
    for (const kind of svc.KINDS) {
      const copy = svc.copyFor({ venueName: 'FavCircles', genericJoin: true }, kind);
      expect(copy.title).toBe('Build your map.');
      expect(copy.subtitle).toBe('Stay connected. Catch every moment.');
      expect(copy.title.length).toBeLessThanOrEqual(svc.TITLE_MAX);
      expect(copy.subtitle.length).toBeLessThanOrEqual(svc.SUBTITLE_MAX);
      expect([copy.title, copy.subtitle, ...copy.hook, copy.lead].join(' ')).not.toMatch(/FavCircles/);
    }
    const jpeg = await svc.headerImagePNG({ venueName: 'FavCircles', genericJoin: true }, 'window', null);
    const meta = await require('sharp')(jpeg).metadata();
    expect([meta.format, meta.width, meta.height]).toEqual(['jpeg', 1800, 1200]);
  });

  test('business category follows the store\'s category, shops otherwise', () => {
    expect(svc.businessCategoryFor({ category: 'cafe' })).toBe('FOOD_AND_DRINK');
    expect(svc.businessCategoryFor({ category: 'restaurant' })).toBe('FOOD_AND_DRINK');
    expect(svc.businessCategoryFor({ category: 'gym' })).toBe('FITNESS');
    expect(svc.businessCategoryFor({ category: 'other', venueName: 'Main Street Books' })).toBe('BOOKS');
    expect(svc.businessCategoryFor({ category: 'other', venueName: 'Acme' })).toBe('SHOPPING');
  });

  test('a register card before loyalty is live is the store\'s own card without the points promise', () => {
    const notLive = svc.copyFor({ venueName: 'Pasta & Provisions', earnRate: 25 }, 'register', { live: false });
    expect(notLive.title).toBe('Pasta & Provisions');
    expect(notLive.subtitle).not.toMatch(/points|earn/i);
    expect(notLive.hook).toEqual(['Love it here?', 'Save us.']);
    // The night loyalty goes live the fingerprint moves, so the card republishes with the points
    const base = { venueName: 'Pasta & Provisions', earnRate: 25 };
    expect(svc.fingerprintFor(base, 'register', 'C1', null, { live: false }))
      .not.toBe(svc.fingerprintFor(base, 'register', 'C1', null, { live: true }));
    // The window card never cared about loyalty
    expect(svc.fingerprintFor(base, 'window', 'C1', null, { live: false }))
      .toBe(svc.fingerprintFor(base, 'window', 'C1', null, { live: true }));
  });

  test('a live register card names the store\'s first reward in the picture, not the words', () => {
    const venue = { venueName: 'X', earnRate: 25, offers: [{ title: 'Free lunch', pointsCost: 300 }, { title: 'Free coffee', pointsCost: 100 }] };
    const copy = svc.copyFor(venue, 'register');
    expect(copy.lead).toBe('100 points = Free coffee');
    expect(copy.subtitle).toBe('Stay connected. Catch every moment.');
    expect(copy.hook).toEqual(['Earn 25 points', 'every visit.']);
    expect(svc.copyFor({ ...venue, offers: [] }, 'register').lead).toBeNull();
    // A changed offer republishes the picture
    const f = svc.fingerprintFor(venue, 'register', 'C1', null);
    expect(svc.fingerprintFor({ ...venue, offers: [{ title: 'Free coffee', pointsCost: 120 }] }, 'register', 'C1', null)).not.toBe(f);
    expect(svc.fingerprintFor({ ...venue, offers: [] }, 'register', 'C1', null)).not.toBe(f);
    // The window card ignores offers
    expect(svc.fingerprintFor({ ...venue, offers: [] }, 'window', 'C1', null)).toBe(svc.fingerprintFor(venue, 'window', 'C1', null));
  });

  test('the fingerprint changes with name, points, cover and code', () => {
    const base = { venueName: 'A', earnRate: 10 };
    const f = svc.fingerprintFor(base, 'register', 'C1', null);
    expect(svc.fingerprintFor(base, 'register', 'C1', null)).toBe(f);
    expect(svc.fingerprintFor({ ...base, venueName: 'B' }, 'register', 'C1', null)).not.toBe(f);
    expect(svc.fingerprintFor({ ...base, earnRate: 20 }, 'register', 'C1', null)).not.toBe(f);
    expect(svc.fingerprintFor(base, 'register', 'C1', 'https://x/y.jpg')).not.toBe(f);
    expect(svc.fingerprintFor(base, 'register', 'C2', null)).not.toBe(f);
    expect(svc.fingerprintFor(base, 'window', 'C1', null)).not.toBe(f);
  });

  test('long names wrap to two lines at most', () => {
    expect(svc.wrapName('Short', 112, 1560, 2)).toEqual(['Short']);
    const lines = svc.wrapName('The Absolutely Enormous Name Of A Coffee Place Downtown', 112, 1560, 2);
    expect(lines.length).toBe(2);
    expect(lines[1].endsWith('…')).toBe(true);
  });

  test('without an API key the sync is a no-op that says so', async () => {
    const result = await svc.syncVenue({ venueId: 'v', venueName: 'A', registerCode: 'R', windowCode: 'W' });
    expect(result.skipped).toBe('not configured');
  });
});
