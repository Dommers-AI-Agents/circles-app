const docs = {};
const updates = [];
const mockDb = {
  collection: () => ({
    doc: (id) => ({
      get: async () => ({ id, exists: !!docs[id], data: () => docs[id] }),
      update: async (data) => { updates.push({ id, data }); }
    }),
    select: () => ({ get: async () => ({ docs: Object.keys(docs).map((id) => ({ id, data: () => docs[id] })) }) })
  })
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
const mockUpload = jest.fn();
jest.mock('../storage', () => ({ downloadAndUploadImage: (...a) => mockUpload(...a) }));

const { rehostGooglePhotos } = require('../googlePhotoRehost');
const { isGooglePhotoLink } = require('../placePhoto');

const storage = (name) => `https://firebasestorage.googleapis.com/v0/b/app/o/${name}.jpg?alt=media`;
const google = (ref) => `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${ref}&key=k`;

beforeEach(() => {
  Object.keys(docs).forEach((k) => delete docs[k]);
  updates.length = 0;
  mockUpload.mockReset();
});

describe('isGooglePhotoLink', () => {
  test('either shape, never throws on odd entries (the 2026-11-02 crash)', () => {
    expect(isGooglePhotoLink(google('a'))).toBe(true);
    expect(isGooglePhotoLink({ url: google('a'), uploadedBy: 'u' })).toBe(true);
    expect(isGooglePhotoLink({ url: storage('a'), uploadedAt: 'x', uploadedBy: 'u' })).toBe(false);
    expect(isGooglePhotoLink(storage('a'))).toBe(false);
    [null, undefined, 7, {}, { url: 3 }].forEach((p) => expect(isGooglePhotoLink(p)).toBe(false));
  });
});

describe('rehostGooglePhotos', () => {
  test('re-hosts what Google serves, drops dead links, keeps every other photo in place', async () => {
    docs.p1 = { name: 'Fresh Monkee', photos: [google('live'), { url: storage('own'), uploadedBy: 'u' }, google('dead')] };
    docs.p2 = { name: 'Clean', photos: [storage('x')] };
    mockUpload.mockImplementation(async (url) => { if (url.includes('dead')) throw new Error('400'); return storage('rehosted'); });

    const [row, ...rest] = await rehostGooglePhotos();

    expect(rest).toHaveLength(0);
    expect(row).toMatchObject({ placeId: 'p1', googleLinks: 2, rehosted: 1, dropped: 1 });
    expect(updates).toHaveLength(1);
    expect(updates[0].data.photos).toEqual([storage('rehosted'), { url: storage('own'), uploadedBy: 'u' }]);
  });

  test('dry run reports and writes nothing', async () => {
    docs.p1 = { name: 'A', photos: [{ url: google('a') }] };
    const rows = await rehostGooglePhotos({ dryRun: true });
    expect(rows).toHaveLength(1);
    expect(mockUpload).not.toHaveBeenCalled();
    expect(updates).toHaveLength(0);
  });

  test('one save by id', async () => {
    docs.p1 = { name: 'A', photos: [google('a')] };
    docs.p2 = { name: 'B', photos: [google('b')] };
    mockUpload.mockResolvedValue(storage('r'));
    const rows = await rehostGooglePhotos({ placeId: 'p2' });
    expect(rows.map((r) => r.placeId)).toEqual(['p2']);
    expect(updates.map((u) => u.id)).toEqual(['p2']);
  });
});
