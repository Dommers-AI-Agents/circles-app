const mockStore = new Map();
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({
    collection: () => ({
      doc: (id) => ({
        get: async () => ({ exists: mockStore.has(id), data: () => mockStore.get(id) }),
        update: async (patch) => {
          const doc = JSON.parse(JSON.stringify(mockStore.get(id)));
          for (const [k, v] of Object.entries(patch)) {
            const parts = k.split('.');
            let o = doc;
            while (parts.length > 1) { const p = parts.shift(); o[p] = o[p] || {}; o = o[p]; }
            o[parts[0]] = v;
          }
          mockStore.set(id, doc);
        }
      })
    })
  })
}));
const { fillVenue, hoursFromGoogle } = require('../venueGoogleDetails');

const google = (over = {}) => jest.fn(async () => ({
  formatted_phone_number: '(980) 294-0500', website: 'https://iamaflowerchild.com', business_status: 'OPERATIONAL',
  opening_hours: { periods: [0, 1, 2, 3, 4, 5, 6].map((day) => ({ open: { day, time: '1100' }, close: { day, time: '2100' } })) },
  ...over
}));

beforeEach(() => mockStore.clear());

test('fills only empty fields and remembers it asked', async () => {
  mockStore.set('v1', { googlePlaceId: 'g1', googleData: { website: 'https://owner-set.example' } });
  const fetcher = google();
  expect(await fillVenue('v1', { fetcher })).toEqual({ filled: ['phone', 'openingHours'] });
  const v = mockStore.get('v1');
  expect(v.googleData.website).toBe('https://owner-set.example');   // an owner's value stays
  expect(v.googleData.phone).toBe('(980) 294-0500');
  expect(v.googleData.openingHours[1]).toEqual({ day: 1, open: '11:00', close: '21:00', isClosed: false });
  expect(v.googleData.detailsCheckedAt).toEqual(expect.any(String));
  // Asked once: no second bill
  expect(await fillVenue('v1', { fetcher })).toEqual({ skipped: 'checked' });
  expect(fetcher).toHaveBeenCalledTimes(1);
});

test('Google having nothing is an answer; an error is not', async () => {
  mockStore.set('v2', { googlePlaceId: 'g2', googleData: {} });
  expect(await fillVenue('v2', { fetcher: jest.fn(async () => null) })).toEqual({ skipped: 'google_error' });
  expect(mockStore.get('v2').googleData.detailsCheckedAt).toBeUndefined();
  expect(await fillVenue('v2', { fetcher: jest.fn(async () => ({ business_status: 'OPERATIONAL' })) })).toEqual({ filled: [] });
  expect(mockStore.get('v2').googleData.detailsCheckedAt).toEqual(expect.any(String));
});

test('skips venues that are not Google-matched, merged, or complete', async () => {
  mockStore.set('a', { googleData: {} });
  mockStore.set('m', { googlePlaceId: 'g', mergedInto: 'x' });
  mockStore.set('c', { googlePlaceId: 'g', googleData: { website: 'w', phone: 'p', openingHours: [{ day: 1 }] } });
  const fetcher = google();
  expect((await fillVenue('a', { fetcher })).skipped).toBe('not_google');
  expect((await fillVenue('m', { fetcher })).skipped).toBe('not_google');
  expect((await fillVenue('c', { fetcher })).skipped).toBe('complete');
  expect(fetcher).not.toHaveBeenCalled();
});

test('hours: split days, closed days, open all day', () => {
  const rows = hoursFromGoogle([
    { open: { day: 2, time: '1100' }, close: { day: 2, time: '1400' } },
    { open: { day: 2, time: '1700' }, close: { day: 2, time: '2130' } },
    { open: { day: 3, time: '0900' }, close: { day: 3, time: '1700' } }
  ]);
  expect(rows[2]).toEqual({ day: 2, hours: '11 AM–2 PM, 5 PM–9:30 PM' });
  expect(rows[3]).toEqual({ day: 3, open: '09:00', close: '17:00', isClosed: false });
  expect(rows[0]).toEqual({ day: 0, open: null, close: null, isClosed: true });
  expect(hoursFromGoogle([{ open: { day: 0, time: '0000' } }])[4]).toEqual({ day: 4, open: '00:00', close: '23:59', isClosed: false });
  expect(hoursFromGoogle(undefined)).toBeNull();
});
