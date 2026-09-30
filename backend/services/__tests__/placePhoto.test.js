jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));

const { firstPhotoUrl, venuePhotoUrl } = require('../placePhoto');

const storage = (name) => `https://firebasestorage.googleapis.com/v0/b/app/o/${name}.jpg?alt=media`;
const google = 'https://maps.googleapis.com/maps/api/place/photo?photoreference=abc&key=k';

describe('firstPhotoUrl', () => {
  test('reads bare URL strings (save records)', () => {
    expect(firstPhotoUrl([storage('a'), storage('b')])).toBe(storage('a'));
  });

  test('reads attributed photo objects (venue records) — the Walmart case', () => {
    expect(firstPhotoUrl([{ id: 'p1', url: storage('a'), uploadedBy: 'u1' }])).toBe(storage('a'));
  });

  test('skips raw Google Places URLs, which bill per render', () => {
    expect(firstPhotoUrl([google, { url: google }, storage('c')])).toBe(storage('c'));
    expect(firstPhotoUrl([google])).toBeNull();
  });

  test('empty, missing or malformed → null', () => {
    expect(firstPhotoUrl([])).toBeNull();
    expect(firstPhotoUrl(undefined)).toBeNull();
    expect(firstPhotoUrl([null, {}, { url: 7 }, ''])).toBeNull();
  });
});

describe('venuePhotoUrl', () => {
  test('the cover photo comes first', () => {
    expect(venuePhotoUrl({ coverPhotoUrl: storage('cover'), photos: [{ url: storage('a') }] })).toBe(storage('cover'));
  });

  test('falls back to the first usable photo', () => {
    expect(venuePhotoUrl({ coverPhotoUrl: google, photos: [{ url: storage('a') }] })).toBe(storage('a'));
    expect(venuePhotoUrl({ photos: [{ url: storage('a') }] })).toBe(storage('a'));
  });

  test('no venue or nothing usable → null', () => {
    expect(venuePhotoUrl(null)).toBeNull();
    expect(venuePhotoUrl({ photos: [] })).toBeNull();
  });
});
