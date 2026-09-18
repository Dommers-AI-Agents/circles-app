// Who gets TOLD about something in a circle. Deliberately stricter than the
// read gate: a push or an SSE event cannot be taken back, so anything we are
// unsure about is not sent.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  admin: { firestore: { FieldValue: { arrayUnion: (v) => v } } }
}));

const { circleAudience } = require('../activity/audience');

const put = (col, id, data) => mockDb.rows(col).set(id, data);

beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
  put('users', 'owner', { displayName: 'Owner', innerCircle: ['insider'] });
});

describe('circleAudience', () => {
  test('public and connections circles reach every connection', async () => {
    for (const privacy of ['public', 'myNetwork']) {
      const audience = await circleAudience({ owner: 'owner', privacy }, 'owner');
      expect(audience.emits).toBe(true);
      expect(audience.allows('anyone')).toBe(true);
    }
  });

  test('an inner circle circle reaches only the owner\'s list', async () => {
    const audience = await circleAudience({ owner: 'owner', privacy: 'innerCircle' }, 'owner');
    expect(audience.emits).toBe(true);
    expect(audience.allows('insider')).toBe(true);
    expect(audience.allows('some-other-connection')).toBe(false);
  });

  // The list lives on the user, not the circle, so an owner with an empty list
  // has nobody to tell — don't write a row nobody will ever read.
  test('an inner circle circle with an empty list emits nothing', async () => {
    put('users', 'owner', { displayName: 'Owner', innerCircle: [] });
    const audience = await circleAudience({ owner: 'owner', privacy: 'innerCircle' }, 'owner');
    expect(audience.emits).toBe(false);
  });

  test('private reaches nobody unless the circle has its own guest list', async () => {
    const closed = await circleAudience({ owner: 'owner', privacy: 'private' }, 'owner');
    expect(closed.emits).toBe(false);
    expect(closed.allows('insider')).toBe(false);

    const shared = await circleAudience({ owner: 'owner', privacy: 'private', sharedWith: ['guest'] }, 'owner');
    expect(shared.emits).toBe(true);
    expect(shared.allows('guest')).toBe(true);
    expect(shared.allows('insider')).toBe(false);
  });

  test('a per-circle guest is told about an inner circle circle too', async () => {
    const audience = await circleAudience(
      { owner: 'owner', privacy: 'innerCircle', sharedWith: ['guest'] }, 'owner');
    expect(audience.allows('guest')).toBe(true);
    expect(audience.allows('insider')).toBe(true);
  });

  // A circle doc written before the privacy field existed must not be treated
  // as public just because the field is missing.
  test('a missing or unrecognised privacy value tells nobody', async () => {
    expect((await circleAudience({ owner: 'owner' }, 'owner')).emits).toBe(false);
    expect((await circleAudience({ owner: 'owner', privacy: 'restricted' }, 'owner')).emits).toBe(false);
  });

  test('legacy spellings still resolve to their tier', async () => {
    const snake = await circleAudience({ owner: 'owner', privacy: 'my_network' }, 'owner');
    expect(snake.emits).toBe(true);
    expect(snake.allows('anyone')).toBe(true);
  });
});
