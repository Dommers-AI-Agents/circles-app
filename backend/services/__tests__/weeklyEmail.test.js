jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const content = require('../weeklyEmail/content');
const { renderWeeklyEmail, subjectFor } = require('../weeklyEmail/html');

const NOW = new Date('2026-10-19T16:00:00Z');
const fmt = (n) => `${n} FavCoins`;

describe("what's new", () => {
  const entries = [
    { date: '2026-10-19', title: 'Next build', minVersion: '1.4.1' },
    { date: '2026-10-17', title: 'In the store build', minVersion: '1.4.0' },
    { date: '2026-10-16', title: 'Server side' },
    { date: '2026-08-01', title: 'Old news' }
  ];
  it('waits for the App Store, and tells older builds to update', () => {
    const out = content.whatsNewFor({ userVersion: '1.3.9', storeVersion: '1.4.0', now: NOW, entries });
    expect(out.map((e) => e.title)).toEqual(['In the store build', 'Server side']);
    expect(out[0].needsUpdate).toBe(true);
    expect(out[1].needsUpdate).toBe(false);
    expect(content.whatsNewFor({ userVersion: '1.4.1', storeVersion: '1.4.1', now: NOW, entries }).map((e) => e.needsUpdate))
      .toEqual([false, false, false]);
    // Store unknown: only what needs no build
    expect(content.whatsNewFor({ userVersion: '1.4.0', storeVersion: null, now: NOW, entries }).map((e) => e.title)).toEqual(['Server side']);
  });
  it('compares versions numerically', () => {
    expect(content.compareVersions('1.10.0', '1.9.9')).toBe(1);
    expect(content.compareVersions('1.4', '1.4.0')).toBe(0);
  });
});

describe('widget spotlight', () => {
  const catalog = { a: { title: 'A' }, b: { title: 'B' }, c: { title: 'C' }, d: { title: 'D' }, e: { title: 'E' } };
  it('picks three, rotates weekly, skips widgets already used', () => {
    const week1 = content.widgetSpotlight({ now: NOW, catalog }).map((w) => w.id);
    const week2 = content.widgetSpotlight({ now: new Date(NOW.getTime() + 7 * 86400000), catalog }).map((w) => w.id);
    expect(week1).toHaveLength(3);
    expect(week1).not.toEqual(week2);
    const fresh = content.widgetSpotlight({ now: NOW, catalog, usedIds: new Set(['a', 'b']) }).map((w) => w.id);
    expect(fresh.sort()).toEqual(['c', 'd', 'e']);
  });
});

describe("friends' saves shown by name", () => {
  const circle = { privacy: 'public' };
  it('only what the saver lets connections see', () => {
    expect(content.canShowNetworkSave({ privacy: 'followCircle' }, circle, undefined)).toBe(true);
    expect(content.canShowNetworkSave({}, { privacy: 'myNetwork' }, undefined)).toBe(true);
    expect(content.canShowNetworkSave({ privacy: 'private' }, circle, undefined)).toBe(false);
    expect(content.canShowNetworkSave({ privacy: 'innerCircle' }, circle, undefined)).toBe(false);
    expect(content.canShowNetworkSave({ privacy: 'something odd' }, circle, undefined)).toBe(false);
    expect(content.canShowNetworkSave({}, { privacy: 'private' }, undefined)).toBe(false);
    expect(content.canShowNetworkSave({}, null, undefined)).toBe(false);
    expect(content.canShowNetworkSave({}, circle, { savedPlaces: { public: false, myNetwork: false, innerCircle: true } })).toBe(false);
  });
});

describe('the letter', () => {
  const stats = { newPlaces: 7, newPlacesByCategory: {}, newConnections: 1, unreadMessages: 0, placeComments: 2, placeLikes: 3,
    topContributors: [{ name: 'Sal <b>', count: 2 }], windowStart: '2026-10-12T04:00:00Z',
    favCoins: { confirmedCoins: 41.25, pendingCoins: 0, lifetimeCoins: 60, settledOnChain: 0, hasWallet: false, earnedThisWeek: 3, earnEventsThisWeek: 4 } };
  const extras = {
    own: { saved: 2, checkIns: 1 },
    networkPlaces: [{ id: 'p1', name: 'Flower <Child>', category: 'restaurant', city: 'Charlotte', photo: 'https://img/x.jpg', savedBy: 'Joe', rating: 8 }],
    widgets: [{ id: 'weather', title: 'Weather', blurb: 'Forecasts', emoji: '🌤️' }],
    whatsNew: [{ emoji: '💳', title: 'Subscriptions', body: 'One place', needsUpdate: true }],
    locals: { events: [{ name: 'Concert', date: '2026-10-21', time: '19:30', venue: 'Fillmore', url: 'https://tm/x' }], markets: [], attribution: 'Events from Ticketmaster' },
    tip: { emoji: '👆', text: 'Long-press the icon.' }
  };
  const html = renderWeeklyEmail({ user: { displayName: 'Wesley Sgroi' }, stats, extras, fmtCoins: fmt, now: NOW });
  it('has every section, linked', () => {
    expect(html).toContain('Hi Wesley');
    expect(html).toContain('places you saved');
    expect(html).toContain('7 new places from your network');
    expect(html).toContain('/place/p1');
    expect(html).toContain('+ 6 more places in the app');
    expect(html).toContain('41.25 FavCoins available');
    expect(html).toContain('Cactus blockchain 🌵');
    expect(html).toContain('path=create-wallet');
    expect(html).toContain('Happening near you');
    expect(html).toContain('Wed, Oct 21 · 7:30 PM');
    expect(html).toContain("What's new in FavCircles");
    expect(html).toContain('Update FavCircles to get this');
    expect(html).toContain('/app/widget/weather');
    expect(html).toContain('Tip of the week');
  });
  it('escapes names from the database', () => {
    expect(html).toContain('Flower &lt;Child&gt;');
    expect(html).toContain('Sal &lt;b&gt;');
    expect(html).not.toContain('<Child>');
  });
  it('subject says what is inside', () => {
    expect(subjectFor(stats, fmt)).toBe('Your FavCircles week: 7 new places from friends · +3 FavCoins');
    expect(subjectFor({ newPlaces: 0 }, fmt)).toBe('Your FavCircles week');
  });
});
