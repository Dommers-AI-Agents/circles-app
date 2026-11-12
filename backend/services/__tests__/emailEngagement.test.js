const { record } = require('../emailEngagement');

const fakeDb = ({ uid = null } = {}) => {
  const adds = []; const sets = []; const updates = [];
  const privateDoc = { set: async (d, o) => sets.push([d, o]), update: async (u) => updates.push(u) };
  const db = {
    collection: (name) => {
      if (name === 'emailEvents') return { add: async (row) => { adds.push(row); return { id: 'ev1' }; } };
      if (name === 'users') return {
        where: () => ({ limit: () => ({ get: async () => (uid ? { empty: false, docs: [{ id: uid }] } : { empty: true, docs: [] }) }) }),
        doc: () => ({ collection: () => ({ doc: () => privateDoc }) })
      };
      throw new Error('unexpected ' + name);
    }
  };
  return { db, adds, sets, updates };
};

jest.mock('firebase-admin/firestore', () => ({ FieldValue: { increment: (n) => ({ inc: n }) } }), { virtual: true });

describe('emailEngagement.record', () => {
  const now = () => new Date('2026-11-12T10:00:00.000Z');

  test('a click by a known person: one event row and the per-kind rollup', async () => {
    const f = fakeDb({ uid: 'john' });
    const out = await record('click', { sendId: 's1', to: 'John@Example.com', kind: 'welcome', url: 'https://favcircles.com/x' }, { db: f.db, now, userAgent: 'Mail/1' });
    expect(out).toEqual({ uid: 'john', at: '2026-11-12T10:00:00.000Z' });
    expect(f.adds[0]).toEqual(expect.objectContaining({ event: 'click', email: 'john@example.com', uid: 'john', kind: 'welcome', url: 'https://favcircles.com/x', userAgent: 'Mail/1' }));
    expect(f.updates[0]).toEqual(expect.objectContaining({ 'welcome.clicks': { inc: 1 }, 'welcome.lastClickAt': '2026-11-12T10:00:00.000Z', 'welcome.lastUrl': 'https://favcircles.com/x' }));
  });

  test('an open by an email with no account is kept by email only', async () => {
    const f = fakeDb();
    const out = await record('open', { sendId: 's2', to: 'guest@example.com', kind: 'event_invite' }, { db: f.db, now });
    expect(out.uid).toBeNull();
    expect(f.adds[0]).toEqual(expect.objectContaining({ event: 'open', uid: null, url: null }));
    expect(f.updates).toHaveLength(0);
  });
});
