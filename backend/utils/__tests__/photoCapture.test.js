const { parsePhotoCapture, distanceMeters, PHOTO_PLACE_RADIUS_M } = require('../photoCapture');
const { createPlaceVideo } = require('../../models/FirestoreModels');

describe('where a photo was taken (Wes, 2026-10-09)', () => {
  const now = Date.parse('2026-10-09T12:00:00Z');
  test('keeps a real spot and time; drops anything that does not parse', () => {
    expect(parsePhotoCapture({ lat: 35.2271, lng: -80.8431, takenAt: '2026-10-04T18:10:05Z' }, now))
      .toEqual({ lat: 35.2271, lng: -80.8431, takenAt: '2026-10-04T18:10:05.000Z' });
    expect(parsePhotoCapture({}, now)).toEqual({ lat: null, lng: null, takenAt: null });
    expect(parsePhotoCapture({ lat: 0, lng: 0 }, now)).toMatchObject({ lat: null, lng: null });
    expect(parsePhotoCapture({ lat: 95, lng: 1 }, now)).toMatchObject({ lat: null, lng: null });
    expect(parsePhotoCapture({ takenAt: '1999-12-31T00:00:00Z' }, now).takenAt).toBeNull();
    expect(parsePhotoCapture({ takenAt: '2026-10-12T00:00:00Z' }, now).takenAt).toBeNull();
  });
  test('distance and the radius a photo counts as "at" a place', () => {
    expect(distanceMeters(35.2271, -80.8431, 35.2276, -80.8431)).toBeCloseTo(55.6, 0);
    expect(PHOTO_PLACE_RADIUS_M).toBe(150);
  });
  test('a photo moment stores where/when; a video stores nulls', () => {
    const photo = createPlaceVideo({ placeId: 'p', placeName: 'Midnight Diner', contentType: 'photo',
      takenAt: '2026-10-04T18:10:05.000Z', takenLocation: { lat: 35.2271, lng: -80.8431 } }, 'wes');
    expect(photo).toMatchObject({ takenAt: '2026-10-04T18:10:05.000Z', takenLocation: { lat: 35.2271, lng: -80.8431 } });
    expect(createPlaceVideo({ placeId: 'p', placeName: 'X' }, 'wes')).toMatchObject({ takenAt: null, takenLocation: null });
  });
});
