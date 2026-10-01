// security audit 2026-10-01: an invalid zip is billed to Google at most once,
// and non-zip strings never reach Firestore or Google.

const docs = new Map();
const mockDb = {
  collection: () => ({
    doc: (id) => ({
      get: async () => ({ exists: docs.has(id), data: () => docs.get(id) }),
      set: async (v) => { docs.set(id, v); }
    })
  })
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
jest.mock('../../data/us-zipcodes-sample.json', () => ({}), { virtual: false });

const { geocodeZipcode } = require('../zipcodeService');

let fetchMock;
beforeEach(() => {
  docs.clear();
  process.env.GOOGLE_MAPS_API_KEY = 'test-key';
  fetchMock = jest.fn();
  global.fetch = fetchMock;
  jest.spyOn(console, 'log').mockImplementation(() => {});
  jest.spyOn(console, 'warn').mockImplementation(() => {});
});
afterEach(() => jest.restoreAllMocks());

test('ZERO_RESULTS is cached; the second lookup never calls Google', async () => {
  fetchMock.mockResolvedValue({ json: async () => ({ status: 'ZERO_RESULTS', candidates: [] }) });
  const first = await geocodeZipcode('00001');
  const second = await geocodeZipcode('00001');
  expect(fetchMock).toHaveBeenCalledTimes(1);
  expect(docs.get('00001')).toMatchObject({ notFound: true });
  expect(second).toEqual(first);
});

test('a Google error is not cached as not-found', async () => {
  fetchMock.mockResolvedValue({ json: async () => ({ status: 'OVER_QUERY_LIMIT' }) });
  await geocodeZipcode('00002');
  await geocodeZipcode('00002');
  expect(fetchMock).toHaveBeenCalledTimes(2);
  expect(docs.has('00002')).toBe(false);
});

test('non-zip input never reaches Firestore or Google', async () => {
  const result = await geocodeZipcode('abc/def; DROP');
  expect(fetchMock).not.toHaveBeenCalled();
  expect(docs.size).toBe(0);
  expect(result).toEqual({ city: 'United States', state: 'US' });
});

test('ZIP+4 is trimmed to five digits', async () => {
  fetchMock.mockResolvedValue({ json: async () => ({
    status: 'OK',
    candidates: [{ formatted_address: 'Charlotte, NC 28202', geometry: { location: { lat: 35.2, lng: -80.8 } } }]
  }) });
  const result = await geocodeZipcode('28202-1234');
  expect(result).toMatchObject({ city: 'Charlotte', state: 'NC' });
  expect(docs.has('28202')).toBe(true);
});
