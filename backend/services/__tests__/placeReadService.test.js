// Read-side place helpers: what every list/detail endpoint layers over a thin
// save doc. These lock in the overlay/merge rules that iOS depends on.

const mockGetAll = jest.fn();
const mockGet = jest.fn();
const mockDoc = jest.fn(() => ({ get: mockGet }));
const mockCollection = jest.fn(() => ({ doc: mockDoc }));

jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({ collection: mockCollection, getAll: mockGetAll })
}));
jest.mock('../../models/FirestoreModels', () => ({
  COLLECTIONS: { USERS: 'users', PLACES: 'places' },
  serializeDoc: (doc) => ({ id: doc.id, ...doc.data() })
}));
jest.mock('../../models/GlobalPlace', () => ({
  GLOBAL_COLLECTIONS: { GLOBAL_PLACES: 'globalPlaces' }
}));
jest.mock('../globalPlaceResolver', () => ({
  ensureGlobalPlaceLink: jest.fn(async () => null)
}));

const svc = require('../placeReadService');

describe('normalizePhotosArray', () => {
  it('flattens {url} objects to strings and leaves strings alone', () => {
    const place = { photos: ['a.jpg', { url: 'b.jpg', by: 'u1' }, null] };
    expect(svc.normalizePhotosArray(place).photos).toEqual(['a.jpg', 'b.jpg', null]);
  });
  it('is a no-op without a photos array', () => {
    expect(svc.normalizePhotosArray({ name: 'x' })).toEqual({ name: 'x' });
  });
});

describe('overlayVenuePhotos', () => {
  it('serves the venue pool first, then the save-only leftovers, de-duped by url', () => {
    const place = { photos: ['c.jpg', { url: 'a.jpg' }] };
    const out = svc.overlayVenuePhotos(place, { photos: ['a.jpg', 'b.jpg'] });
    expect(out.photos).toEqual(['a.jpg', 'b.jpg', 'c.jpg']);
  });
  it('keeps the save photos when the venue has none', () => {
    const place = { photos: ['c.jpg'] };
    expect(svc.overlayVenuePhotos(place, { photos: [] }).photos).toEqual(['c.jpg']);
    expect(svc.overlayVenuePhotos(place, null).photos).toEqual(['c.jpg']);
  });
});

describe('overlayVenueFields', () => {
  it('overwrites venue fields from the canonical record, lifting googleData to top level', () => {
    const place = { name: 'Old', address: 'Old St', privateNotes: 'mine', rating: 3 };
    const out = svc.overlayVenueFields(place, {
      name: 'New', address: '', googleData: { rating: 4.5, website: 'w', delivery: false }
    });
    expect(out.name).toBe('New');
    expect(out.address).toBe('Old St');        // empty canonical value does not clobber
    expect(out.rating).toBe(4.5);
    expect(out.website).toBe('w');
    expect(out.delivery).toBe(false);          // false is a real answer
    expect(out.privateNotes).toBe('mine');     // per-user fields untouched
    expect(place.name).toBe('Old');            // input not mutated
  });
});

describe('isPlaceVisibleToViewer', () => {
  it('hides private places from everyone but the saver', () => {
    const place = { addedBy: 'u1', privacy: 'private' };
    expect(svc.isPlaceVisibleToViewer(place, 'u1')).toBe(true);
    expect(svc.isPlaceVisibleToViewer(place, 'u2')).toBe(false);
  });
  it('inherits circle visibility for every other privacy value', () => {
    expect(svc.isPlaceVisibleToViewer({ addedBy: 'u1', privacy: 'followCircle' }, 'u2')).toBe(true);
    expect(svc.isPlaceVisibleToViewer({ addedBy: 'u1' }, 'u2')).toBe(true);
  });
});

describe('fetchGlobalSocialMap', () => {
  beforeEach(() => { mockGetAll.mockReset(); mockCollection.mockClear(); mockDoc.mockClear(); });

  it('returns an empty map without touching Firestore when no place is linked', async () => {
    const map = await svc.fetchGlobalSocialMap([{ id: 'p1' }, { id: 'p2', globalPlaceId: null }]);
    expect(map.size).toBe(0);
    expect(mockGetAll).not.toHaveBeenCalled();
  });

  it('does ONE getAll over the unique canonical ids and skips missing docs', async () => {
    mockGetAll.mockResolvedValue([
      { id: 'g1', exists: true, data: () => ({ likes: ['u1'], commentsCount: 2, name: 'Cafe' }) },
      { id: 'g2', exists: false }
    ]);
    const map = await svc.fetchGlobalSocialMap([
      { globalPlaceId: 'g1' }, { globalPlaceId: 'g1' }, { globalPlaceId: 'g2' }
    ]);
    expect(mockGetAll).toHaveBeenCalledTimes(1);
    expect(mockGetAll.mock.calls[0]).toHaveLength(2);
    expect(map.get('g1')).toEqual({ likes: ['u1'], commentsCount: 2, venueData: { likes: ['u1'], commentsCount: 2, name: 'Cafe' } });
    expect(map.has('g2')).toBe(false);
  });
});

describe('buildAddedByUserMap', () => {
  beforeEach(() => { mockGet.mockReset(); mockDoc.mockClear(); });

  it('keys each user by doc id AND by the raw addedBy value, unwrapping provider.uid.suffix ids', async () => {
    mockGet.mockImplementation(async () => ({
      id: 'abc', exists: true, data: () => ({ displayName: 'Wes', profilePicture: 'pic' })
    }));
    const map = await svc.buildAddedByUserMap([{ addedBy: 'google.abc.1' }, { addedBy: 'google.abc.1' }, { addedBy: null }]);
    expect(mockDoc).toHaveBeenCalledWith('abc');
    expect(mockDoc).toHaveBeenCalledTimes(1);
    expect(map.get('abc')).toEqual({ id: 'abc', displayName: 'Wes', profilePicture: 'pic' });
    expect(map.get('google.abc.1')).toEqual(map.get('abc'));
  });

  it('skips users whose doc is missing', async () => {
    mockGet.mockResolvedValue({ exists: false });
    const map = await svc.buildAddedByUserMap([{ addedBy: 'ghost' }]);
    expect(map.size).toBe(0);
  });
});
