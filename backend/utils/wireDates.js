/**
 * Convert every Firestore Timestamp (class instance or its plain
 * `{ _seconds, _nanoseconds }` form) and JS Date inside a value to an ISO
 * string, recursively. Use it on anything spread straight from `doc.data()`
 * before it goes out over the wire: the iOS decoder only accepts ISO strings
 * for dates, and one raw Timestamp fails the whole array it sits in.
 *
 * GeoPoints and other objects are left as they are.
 */
const isTimestampShape = (value) =>
  typeof value._seconds === 'number' && typeof value._nanoseconds === 'number';

const serializeDates = (value) => {
  if (value === null || value === undefined) return value;
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(serializeDates);
  if (typeof value !== 'object') return value;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (isTimestampShape(value)) return new Date(value._seconds * 1000 + Math.floor(value._nanoseconds / 1e6)).toISOString();
  if (Object.getPrototypeOf(value) !== Object.prototype) return value;
  const out = {};
  for (const [key, inner] of Object.entries(value)) out[key] = serializeDates(inner);
  return out;
};

module.exports = { serializeDates };
