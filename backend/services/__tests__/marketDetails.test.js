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

test('cached details are used without a lookup; closed, unconfirmed and repeated markets drop out', async () => {
  global.fetch = jest.fn();
  const fresh = new Date().toISOString();
  const out = await withDetails([
    { id: '1', name: 'A Market', lat: 1, lng: 1, google: { googlePlaceId: 'g1', photoUrl: 'p', hoursSummary: 'Sat 8 AM–1 PM', checkedAt: fresh } },
    { id: '2', name: 'A Market at the Mill', lat: 1, lng: 1, google: { googlePlaceId: 'g1', checkedAt: fresh } },
    { id: '3', name: 'Gone Market', lat: 1, lng: 1, google: { closed: true, googlePlaceId: 'g3', checkedAt: fresh } },
    { id: '4', name: 'Unknown', lat: 1, lng: 1, google: { noMatch: true, checkedAt: fresh } }
  ], { apiKey: 'k' });
  expect(global.fetch).not.toHaveBeenCalled();
  expect(out.map((m) => m.id)).toEqual(['1']); // 4: Google doesn't know it, so it isn't shown
  expect(out[0]).toMatchObject({ googlePlaceId: 'g1', photoUrl: 'p', hoursSummary: 'Sat 8 AM–1 PM' });
  expect(out[0].google).toBeUndefined();
});

const { osmPeriods, refresh } = require('../localEvents/marketDetails');

test('OpenStreetMap hours read like Google\'s; anything fancier is left to Google', () => {
  expect(hoursFrom(osmPeriods('Sa 08:00-12:30')).hoursSummary).toBe('Sat 8 AM–12:30 PM');
  expect(hoursFrom(osmPeriods('We-Su 08:00-17:00')).hoursSummary).toBe('Sun, Wed, Thu, Fri, Sat 8 AM–5 PM');
  expect(hoursFrom(osmPeriods('Su-Tu 09:00-19:00; We 09:00-20:00')).hoursSummary)
    .toBe('Sun, Mon, Tue 9 AM–7 PM · Wed 9 AM–8 PM');
  expect(hoursFrom(osmPeriods('Mo-Sa 08:00-18:00; Su off; PH off')).hoursSummary).toBe('Mon, Tue, Wed, Thu, Fri, Sat 8 AM–6 PM');
  expect(osmPeriods('Apr-Nov: Sa 08:00-12:00')).toBeNull();
  expect(osmPeriods('Sa sunrise-12:00')).toBeNull();
  expect(osmPeriods('')).toBeNull();
});

describe('refresh: free source first, Google only for what is missing', () => {
  const now = Date.parse('2026-10-17T12:00:00Z');
  const market = { id: 'm1', name: 'Uptown Farmers Market', lat: 35.22, lng: -80.84 };
  const osm = { osmId: 'node/1', editedAt: '2026-05-01T00:00:00Z', website: 'https://osm.example', periods: osmPeriods('Sa 08:00-12:30') };
  const googleReply = (hours) => (url) => Promise.resolve({ ok: true, json: async () => (
    url.includes('findplacefromtext')
      ? { candidates: [{ place_id: 'g1', name: 'Uptown Farmers Market', geometry: { location: { lat: 35.2201, lng: -80.8401 } } }] }
      : { result: { business_status: 'OPERATIONAL', opening_hours: hours ? { periods: osmPeriods(hours) } : undefined } }) });
  const opts = (extra = {}) => ({ key: 'k', now, logConflict: jest.fn(), ...extra });

  test('known photo + OpenStreetMap hours + recent closure check → no Google call', async () => {
    global.fetch = jest.fn();
    const prev = { googlePlaceId: 'g1', photoUrl: 'p', googleCheckedAt: '2026-09-01T00:00:00Z' };
    const out = await refresh(market, prev, osm, opts());
    expect(global.fetch).not.toHaveBeenCalled();
    expect(out).toMatchObject({ hoursSummary: 'Sat 8 AM–12:30 PM', hoursSource: 'osm', photoUrl: 'p', googlePlaceId: 'g1', osmId: 'node/1' });
  });

  test('a known Google place skips the search', async () => {
    global.fetch = jest.fn(googleReply(null));
    const prev = { googlePlaceId: 'g1', photoUrl: 'p' };
    await refresh(market, prev, osm, opts());
    expect(global.fetch).toHaveBeenCalledTimes(1);
    expect(global.fetch.mock.calls[0][0]).toContain('details/json');
    expect(global.fetch.mock.calls[0][0]).not.toContain('photos');
  });

  test('not on OpenStreetMap → Google confirms and gives the hours', async () => {
    global.fetch = jest.fn(googleReply('Sa 08:00-13:00'));
    const out = await refresh(market, { photoTriedAt: 'x' }, null, opts());
    expect(out).toMatchObject({ googlePlaceId: 'g1', hoursSummary: 'Sat 8 AM–1 PM', hoursSource: 'google', osmId: null });
  });

  test('neither source knows it → no match (hidden)', async () => {
    global.fetch = jest.fn(async () => ({ ok: true, json: async () => ({ candidates: [] }) }));
    expect(await refresh(market, null, null, opts())).toMatchObject({ noMatch: true });
  });

  test('disagreeing hours: a recent map edit wins, an old one loses; both logged', async () => {
    global.fetch = jest.fn(googleReply('Sa 09:00-13:00'));
    const o1 = opts();
    expect((await refresh(market, null, osm, o1)).hoursSource).toBe('osm');
    expect(o1.logConflict).toHaveBeenCalledWith(expect.objectContaining({ osm: 'Sat 8 AM–12:30 PM', google: 'Sat 9 AM–1 PM', chose: 'osm' }));
    const o2 = opts();
    const old = { ...osm, editedAt: '2023-01-01T00:00:00Z' };
    expect(await refresh(market, null, old, o2)).toMatchObject({ hoursSource: 'google', hoursSummary: 'Sat 9 AM–1 PM' });
    expect(o2.logConflict).toHaveBeenCalled();
  });

  test('OpenStreetMap unreachable: keep what we had instead of judging on one source', async () => {
    global.fetch = jest.fn();
    expect(await refresh(market, { googlePlaceId: 'g1' }, undefined, opts())).toBeNull();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  test('Google says closed → closed', async () => {
    global.fetch = jest.fn(async (url) => ({ ok: true, json: async () => (url.includes('findplace')
      ? { candidates: [{ place_id: 'g1', name: 'Uptown Market', geometry: { location: { lat: 35.22, lng: -80.84 } } }] }
      : { result: { business_status: 'CLOSED_PERMANENTLY' } }) }));
    expect((await refresh(market, null, osm, opts())).closed).toBe(true);
  });
});

test('a known but stale market shows its saved details at once (refresh runs behind)', async () => {
  let release;
  global.fetch = jest.fn(() => new Promise((r) => { release = r; }));
  const old = '2026-01-01T00:00:00.000Z';
  const out = await withDetails([{ id: '9', name: 'Old Market', lat: 1, lng: 1,
    details: { googlePlaceId: 'g9', hoursSummary: 'Sat 8 AM–12 PM', checkedAt: old } }], { apiKey: 'k', now: Date.parse('2026-10-17T00:00:00Z') });
  expect(out[0]).toMatchObject({ googlePlaceId: 'g9', hoursSummary: 'Sat 8 AM–12 PM' });
  expect(global.fetch).toHaveBeenCalled();   // the background Overpass call started
  release({ ok: false, status: 503 });
});
