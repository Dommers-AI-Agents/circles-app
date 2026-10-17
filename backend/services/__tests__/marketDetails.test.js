jest.mock('../../config/firebase', () => ({ getFirestore: () => ({ collection: () => ({ doc: () => ({ set: async () => {} }) }) }) }));
const { hoursFrom, isSameMarket, clock, withDetails } = require('../localEvents/marketDetails');

test('Google hours become a short line and the app\'s rows', () => {
  expect(clock('0800')).toBe('8 AM');
  expect(clock('1230')).toBe('12:30 PM');
  const { openingHours, hoursSummary } = hoursFrom([
    { open: { day: 2, time: '0600' }, close: { day: 2, time: '1700' } },
    { open: { day: 6, time: '0700' }, close: { day: 6, time: '1500' } },
    { open: { day: 4, time: '0600' }, close: { day: 4, time: '1700' } }
  ]);
  expect(hoursSummary).toBe('Tue, Thu 6 AM–5 PM · Sat 7 AM–3 PM');
  expect(openingHours[0]).toEqual({ day: 2, open: '06:00', close: '17:00', isClosed: false });
  expect(hoursFrom([{ open: { day: 0, time: '0000' } }]).hoursSummary).toBe('Open 24 hours');
  expect(hoursFrom(undefined).hoursSummary).toBeNull();
});

test('a Google result counts as the market only if close and sharing a name word', () => {
  const market = { name: 'Kings Drive Farmers’ Market', lat: 35.2105, lng: -80.8389 };
  expect(isSameMarket(market, { name: 'Kings Drive Farmers Market', geometry: { location: { lat: 35.2108, lng: -80.8391 } } })).toBe(true);
  expect(isSameMarket(market, { name: 'Harris Teeter', geometry: { location: { lat: 35.2108, lng: -80.8391 } } })).toBe(false);
  expect(isSameMarket(market, { name: 'Kings Drive Market', geometry: { location: { lat: 35.25, lng: -80.8391 } } })).toBe(false);
});

test('cached details are used without a lookup; closed markets and repeats drop out', async () => {
  global.fetch = jest.fn();
  const fresh = new Date().toISOString();
  const out = await withDetails([
    { id: '1', name: 'A Market', lat: 1, lng: 1, google: { googlePlaceId: 'g1', photoUrl: 'p', hoursSummary: 'Sat 8 AM–1 PM', checkedAt: fresh } },
    { id: '2', name: 'A Market at the Mill', lat: 1, lng: 1, google: { googlePlaceId: 'g1', checkedAt: fresh } },
    { id: '3', name: 'Gone Market', lat: 1, lng: 1, google: { closed: true, googlePlaceId: 'g3', checkedAt: fresh } },
    { id: '4', name: 'Unknown', lat: 1, lng: 1, google: { noMatch: true, checkedAt: fresh } }
  ], { apiKey: 'k' });
  expect(global.fetch).not.toHaveBeenCalled();
  expect(out.map((m) => m.id)).toEqual(['1', '4']);
  expect(out[0]).toMatchObject({ googlePlaceId: 'g1', photoUrl: 'p', hoursSummary: 'Sat 8 AM–1 PM' });
  expect(out[0].google).toBeUndefined();
});
