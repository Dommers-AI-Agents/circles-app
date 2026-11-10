// The store's website (Wes, 2026-11-09): every Business store has a page;
// its sections come from what the owner already keeps; the sitemap lists
// the public ones; web guests join the waitlist by email.
const { FakeFirestore, FakeFieldValue: MockFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: MockFieldValue, admin: { firestore: { FieldValue: MockFieldValue } } }));
const mockLive = { value: true };
jest.mock('../ownerSubscriptionService', () => ({
  isVenueBusinessLive: async () => mockLive.value,
  venueLoyaltyStatus: async () => ({ active: mockLive.value, reason: 'owner_premium' })
}));
jest.mock('../../config/secrets', () => ({ jwtSecret: () => 'test-secret-test-secret-test-secret' }));
const mockMails = [];
jest.mock('../emailService', () => ({ sendEmail: async (m) => { mockMails.push(m); return {}; } }));
const mockPushes = [];
jest.mock('../notifyQuiet', () => ({ sendInBackground: (uid, n) => mockPushes.push({ uid, ...n }) }));
jest.mock('../venueHelpers', () => {
  const actual = jest.requireActual('../venueHelpers');
  return { ...actual, venueGlobalPlaceId: async (v) => v.globalPlaceId || null, venueManagerIds: (v) => v.managerUserIds || [] };
});

const web = require('../orders/webOrderService');
const pages = require('../../views/orderPage');
const waitlist = require('../waitlistService');

const NOW = new Date('2026-11-09T18:00:00.000Z');
const VENUE = {
  venueId: 'v1', venueName: "Sal's Coffee", placeAddress: '1 Elm St, Charlotte, NC 28202', category: 'cafe', active: true,
  ownerUserId: 'owner', globalPlaceId: 'gp1', slug: 'sals-coffee', earnRate: 25,
  offers: [{ offerId: 'o1', title: 'Free coffee', pointsCost: 100, active: true }, { offerId: 'o2', title: 'Half-price bagel', pointsCost: 60, active: true }],
  announcements: [
    { announcementId: 'a1', title: 'Live music', message: 'Jazz trio', expiresAt: '2026-12-01T00:00:00.000Z', event: { startsAt: '2026-11-13T19:00:00.000Z', localDate: 'Fri, Nov 13', localTime: '7:00 PM', isFree: true } },
    { announcementId: 'a2', title: 'New fall menu', message: 'Pumpkin everything' },
    { announcementId: 'a3', title: 'Gone', message: 'old', expiresAt: '2026-01-01T00:00:00.000Z' }
  ],
  storefront: { menu: { sections: [] }, actions: { reserve: 'https://resy.example/sals', order: 'https://order.example', catering: null, hide: ['order'] } },
  waitlist: { enabled: true, quoteMinutes: 20 },
  insightsCache: { '30d': { at: NOW.toISOString(), data: { score: { average: 8.4, ratings: 12, recommend: 9 } } } }
};
const PLACE = {
  description: 'Third-wave coffee and fresh bagels since 2019.',
  coverPhotoUrl: 'https://img/cover.jpg',
  photos: [{ id: 'p1', url: 'https://img/1.jpg' }, { id: 'p2', url: 'https://img/cover.jpg' }, { id: 'p3', url: 'https://img/private.jpg', isPrivate: true }, { id: 'p4', url: 'https://img/gone.jpg', removedAt: 'x' }],
  location: { type: 'Point', coordinates: [-80.84, 35.22] },
  googleData: { rating: 4.6, userRatingsTotal: 212, phone: '(704) 555-0199', website: 'https://sals.example' }
};

beforeEach(async () => {
  for (const c of ['stickerVenues', 'venueSlugs', 'globalPlaces', 'users', 'waitlistEntries']) mockDb.rows(c).clear();
  mockMails.length = 0; mockPushes.length = 0; mockLive.value = true;
  await mockDb.collection('stickerVenues').doc('v1').set(VENUE);
  await mockDb.collection('stickerVenues').doc('v2').set({ ...VENUE, venueName: 'Demo', slug: 'demo-store', isTestStore: true });
  await mockDb.collection('stickerVenues').doc('v3').set({ ...VENUE, venueName: 'No slug', slug: null });
  await mockDb.collection('venueSlugs').doc('sals-coffee').set({ venueId: 'v1', retiredAt: null });
  await mockDb.collection('globalPlaces').doc('gp1').set(PLACE);
});

test('the website parts: about, public photos cover first, live announcements events first, score beside Google, earn, buttons minus hidden ones, waitlist, geo', async () => {
  const site = await web.siteProjection(VENUE, PLACE, { live: true });
  expect(site.description).toBe('Third-wave coffee and fresh bagels since 2019.');
  expect(site.photos).toEqual(['https://img/cover.jpg', 'https://img/1.jpg']);
  expect(site.announcements.map((a) => a.title)).toEqual(['Live music', 'New fall menu']);
  expect(site.announcements[0].event).toMatchObject({ localDate: 'Fri, Nov 13', localTime: '7:00 PM', isFree: true });
  expect(site.score).toEqual({ average: 8.4, ratings: 12, recommend: 9, google: { rating: 4.6, total: 212 } });
  expect(site.earn).toMatchObject({ earnRate: 25, firstReward: { title: 'Half-price bagel', pointsCost: 60 } });
  expect(site.earn.offers.map((o) => o.title)).toEqual(['Half-price bagel', 'Free coffee']);
  expect(site.actions).toEqual([{ key: 'reserve', label: 'Reserve', url: 'https://resy.example/sals' }]);
  expect(site.waitlist).toEqual({ enabled: true, quoteMinutes: 20 });
  expect(site.location).toEqual({ latitude: 35.22, longitude: -80.84 });

  mockLive.value = false;
  const dark = await web.siteProjection(VENUE, PLACE, { live: false });
  expect(dark.earn).toBeNull();
  expect(dark.waitlist).toBeNull();
});

test('a store without a menu still has a page, and it renders every section with LocalBusiness data', async () => {
  const page = await web.pageFor('sals-coffee');
  expect(page).not.toBeNull();
  const p = { ...web.projection(page.venue, page.place, { live: page.live, ordering: page.ordering }), ...(await web.siteProjection(page.venue, page.place, { live: page.live })) };
  const html = pages.renderOrderPage(p, { base: '', canonicalUrl: 'https://order.favcircles.com/sals-coffee' });
  expect(html).toContain('<h1>Sal&#39;s Coffee</h1>');
  expect(html).toContain('Third-wave coffee');
  expect(html).toContain("What's on");
  expect(html).toContain('Live music');
  expect(html).not.toContain('>Gone<');
  expect(html).toContain('FavCircles score');
  expect(html).toContain('4.6★');
  expect(html).toContain('Join the line');
  expect(html).toContain('store-waitlist.js');
  expect(html).toContain('Every visit earns 25 points');
  expect(html).toContain('href="https://resy.example/sals"');
  expect(html).toContain('"@type":"LocalBusiness"');
  expect(html).toContain('"ratingValue":4.6');
  expect(html).toContain('"latitude":35.22');
  expect(html).not.toContain('id="bar"'); // no menu: no ordering chrome
  expect(html).not.toMatch(/ownerUserId|insightsCache/);
});

test('the sitemap lists public Business stores with a slug, never test stores', async () => {
  expect((await web.sitemapSlugs()).map((r) => r.slug)).toEqual(['sals-coffee']);
  mockLive.value = false;
  expect(await web.sitemapSlugs()).toEqual([]);
});

test('a web guest joins by email, reads their spot with the token, is emailed when called, and can leave', async () => {
  await expect(waitlist.joinGuest({ venueId: 'v1', name: 'A', email: 'ana@example.com', partySize: 2 })).rejects.toThrow(/who the table is for/);
  await expect(waitlist.joinGuest({ venueId: 'v1', name: 'Ana', email: 'nope', partySize: 2 })).rejects.toThrow(/email/);
  const joined = await waitlist.joinGuest({ venueId: 'v1', name: 'Ana Ruiz', email: 'Ana@Example.com', partySize: 2, now: NOW });
  expect(joined.entry).toMatchObject({ name: 'Ana Ruiz', partySize: 2, status: 'waiting', position: 1, estimateMinutes: 20 });
  expect(typeof joined.token).toBe('string');
  expect(mockPushes[0]).toMatchObject({ uid: 'owner', type: 'waitlist_joined' });

  const again = await waitlist.joinGuest({ venueId: 'v1', name: 'Ana Ruiz', email: 'ana@example.com', partySize: 4, now: NOW });
  expect(again.alreadyInLine).toBe(true);

  const status = await waitlist.guestStatus(joined.entry.entryId, joined.token);
  expect(status.position).toBe(1);
  await expect(waitlist.guestStatus(joined.entry.entryId, 'bad')).rejects.toThrow(/not valid/);

  await waitlist.act({ venueId: 'v1', venueName: "Sal's Coffee", waitlist: VENUE.waitlist }, joined.entry.entryId, 'notify', { now: NOW });
  await new Promise((r) => setTimeout(r, 0));
  expect(mockMails).toHaveLength(1);
  expect(mockMails[0]).toMatchObject({ to: 'ana@example.com', subject: "Your table is ready at Sal's Coffee" });
  expect((await waitlist.guestStatus(joined.entry.entryId, joined.token)).status).toBe('notified');

  expect(await waitlist.leaveGuest(joined.entry.entryId, joined.token)).toEqual({ left: true, status: 'left' });
  expect(await waitlist.count('v1')).toBe(0);
});
