const { serializeDates } = require('../wireDates');

const ts = (seconds, nanos = 0) => ({
  _seconds: seconds,
  _nanoseconds: nanos,
  toDate: () => new Date(seconds * 1000 + nanos / 1e6),
});

describe('serializeDates', () => {
  test('turns Timestamp instances and their plain shape into ISO strings', () => {
    expect(serializeDates(ts(1753958324, 574000000))).toBe('2025-07-31T10:38:44.574Z');
    expect(serializeDates({ _seconds: 1753889878, _nanoseconds: 996000000 })).toBe('2025-07-30T15:37:58.996Z');
    expect(serializeDates(new Date('2026-09-22T20:47:49.392Z'))).toBe('2026-09-22T20:47:49.392Z');
  });

  test('recurses into objects and arrays, leaving everything else alone', () => {
    const row = {
      id: 'c1',
      status: 'accepted',
      acceptedAt: ts(1753958324),
      createdAt: '2025-07-31T01:18:52.858Z',
      history: [{ at: ts(1), note: 'x' }, ts(2)],
      count: 3,
      flag: false,
      nothing: null,
    };
    expect(serializeDates(row)).toEqual({
      id: 'c1',
      status: 'accepted',
      acceptedAt: '2025-07-31T10:38:44.000Z',
      createdAt: '2025-07-31T01:18:52.858Z',
      history: [{ at: '1970-01-01T00:00:01.000Z', note: 'x' }, '1970-01-01T00:00:02.000Z'],
      count: 3,
      flag: false,
      nothing: null,
    });
  });

  test('leaves GeoPoints and class instances untouched', () => {
    class GeoPoint { constructor() { this._latitude = 1; this._longitude = 2; } }
    const point = new GeoPoint();
    expect(serializeDates({ location: point }).location).toBe(point);
    expect(JSON.stringify(serializeDates({ a: { b: ts(5) } }))).not.toContain('_seconds');
  });
});
