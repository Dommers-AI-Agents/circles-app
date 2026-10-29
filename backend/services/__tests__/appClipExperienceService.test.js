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

  test('register says the points, window says save it; both within 56 characters', () => {
    const register = svc.copyFor({ venueName: 'X', earnRate: 25 }, 'register');
    expect(register.subtitle).toBe('Earn 25 points every visit. Save it to your map.');
    const window = svc.copyFor({ venueName: 'X' }, 'window');
    expect(window.subtitle).toMatch(/Save this spot/);
    expect(register.subtitle.length).toBeLessThanOrEqual(svc.SUBTITLE_MAX);
    expect(window.subtitle.length).toBeLessThanOrEqual(svc.SUBTITLE_MAX);
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
    expect(notLive.pill).toBe('Save this spot');
    // The night loyalty goes live the fingerprint moves, so the card republishes with the points
    const base = { venueName: 'Pasta & Provisions', earnRate: 25 };
    expect(svc.fingerprintFor(base, 'register', 'C1', null, { live: false }))
      .not.toBe(svc.fingerprintFor(base, 'register', 'C1', null, { live: true }));
    // The window card never cared about loyalty
    expect(svc.fingerprintFor(base, 'window', 'C1', null, { live: false }))
      .toBe(svc.fingerprintFor(base, 'window', 'C1', null, { live: true }));
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
