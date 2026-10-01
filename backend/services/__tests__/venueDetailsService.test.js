jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../placePhotoService', () => ({ rightsFor: jest.fn(), venueForPlace: jest.fn() }));

const {
  buildDetailUpdates, cleanHours, changedDetailFields, pickDetailFields, DETAIL_FIELDS
} = require('../venueDetailsService');

describe('buildDetailUpdates', () => {
  test('name refreshes the search fields and the save cache', () => {
    const { venue, cache } = buildDetailUpdates({ name: '  Leroy Fox  ' });
    expect(venue.name).toBe('Leroy Fox');
    expect(venue.nameLower).toBe('leroy fox');
    expect(Array.isArray(venue.searchTokens)).toBe(true);
    expect(cache).toEqual({ name: 'Leroy Fox' });
  });

  test('location brings its geohash, on the venue and the cache', () => {
    const { venue, cache } = buildDetailUpdates({ location: { coordinates: [-80.86, 35.2] } });
    expect(venue.location).toEqual({ type: 'Point', coordinates: [-80.86, 35.2] });
    expect(typeof venue.geohash).toBe('string');
    expect(cache.geohash).toBe(venue.geohash);
  });

  test('phone, website and hours live under googleData; owner hours are marked', () => {
    const { venue, cache } = buildDetailUpdates({
      phone: ' 704-555-0100 ', website: 'https://leroyfox.com',
      openingHours: [{ day: 1, open: '11:00', close: '22:00' }]
    });
    expect(venue['googleData.phone']).toBe('704-555-0100');
    expect(venue['googleData.website']).toBe('https://leroyfox.com');
    expect(venue['googleData.hoursSource']).toBe('owner');
    expect(cache).toEqual({});
  });

  test('description drops embedded Phone:/Website: lines', () => {
    const { venue } = buildDetailUpdates({ description: 'Fried chicken.\nPhone: 555\nWebsite: x.com' });
    expect(venue.description).toBe('Fried chicken.');
  });

  test('refuses bad values with a plain message', () => {
    expect(() => buildDetailUpdates({ name: '  ' })).toThrow('A place needs a name.');
    expect(() => buildDetailUpdates({ category: 'spaceport' })).toThrow('Pick one of the listed categories.');
    expect(() => buildDetailUpdates({ location: { coordinates: [-180, -180] } })).toThrow('That location is not valid.');
  });
});

describe('cleanHours', () => {
  test('sorts by day and nulls the times of a closed day', () => {
    expect(cleanHours([{ day: 2, open: '09:00', close: '17:00' }, { day: 0, isClosed: true, open: '1', close: '2' }]))
      .toEqual([{ day: 0, open: null, close: null, isClosed: true }, { day: 2, open: '09:00', close: '17:00', isClosed: false }]);
  });
  test('rejects duplicates, bad days and bad times', () => {
    expect(() => cleanHours([{ day: 1, open: '9', close: '17:00' }])).toThrow();
    expect(() => cleanHours([{ day: 7, open: '09:00', close: '17:00' }])).toThrow();
    expect(() => cleanHours([{ day: 1, open: '09:00', close: '17:00' }, { day: 1, open: '10:00', close: '12:00' }])).toThrow();
    expect(() => cleanHours([])).toThrow();
  });
});

describe('changedDetailFields', () => {
  const venue = {
    name: 'Leroy Fox - South End', address: '1824 S Tryon St, Charlotte, NC 28203, USA', category: 'restaurant',
    description: 'Fried chicken.', location: { coordinates: [-80.86, 35.2] },
    googleData: { phone: '(704) 555-0100', website: 'https://leroyfox.com' }
  };

  test('what an older app echoes back unchanged is not an edit', () => {
    const echo = {
      name: 'Leroy Fox - South End', address: '1824, S Tryon St, Charlotte, NC, 28203, United States',
      category: 'restaurant', description: 'Fried chicken.', phone: '704-555-0100', website: 'https://leroyfox.com',
      location: { coordinates: [-80.860001, 35.2] }
    };
    expect(changedDetailFields(echo, venue)).toEqual([]);
  });

  test('a phone with or without +1 is the same number', () => {
    expect(changedDetailFields({ phone: '+1 704 555 0100' }, venue)).toEqual([]);
    expect(changedDetailFields({ phone: '1-704-555-0100' }, venue)).toEqual([]);
    expect(changedDetailFields({ phone: '704-555-0199' }, venue)).toEqual(['phone']);
  });

  test('a real change is caught', () => {
    expect(changedDetailFields({ name: 'Leroy Fox', category: 'restaurant' }, venue)).toEqual(['name']);
    expect(changedDetailFields({ location: { coordinates: [-80.9, 35.2] } }, venue)).toEqual(['location']);
  });
});

test('pickDetailFields keeps only shared details', () => {
  expect(pickDetailFields({ name: 'x', privateNotes: 'mine', privacy: 'public', phone: '1' })).toEqual({ name: 'x', phone: '1' });
  expect(DETAIL_FIELDS).not.toContain('privateNotes');
});
