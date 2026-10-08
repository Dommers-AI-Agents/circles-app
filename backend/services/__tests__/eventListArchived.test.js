// Archived events never reach apps that don't know to file them away
// (Brittany on 1.3.7 saw the archived Party Bus as live, 2026-10-08).
const docs = [
  { id: 'live', data: () => ({ name: 'Emily’s Party Bus', hostId: 'wes', memberIds: ['wes', 'brit'], members: {}, createdAt: '2026-10-06' }) },
  { id: 'old', data: () => ({ name: 'Party Bus', hostId: 'wes', memberIds: ['wes', 'brit'], members: {}, archivedAt: '2026-10-07', createdAt: '2026-10-04' }) },
  { id: 'mine', data: () => ({ name: 'Mine', hostId: 'wes', memberIds: ['wes', 'brit'], members: { brit: { archivedAt: '2026-10-07' } }, createdAt: '2026-10-03' }) },
  { id: 'gone', data: () => ({ name: 'Gone', hostId: 'wes', memberIds: ['brit'], deletedAt: '2026-10-01', createdAt: '2026-10-01' }) }
];
const query = { where: () => query, orderBy: () => query, limit: () => query, get: async () => ({ docs }) };
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({ collection: () => query }) }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: () => {} }));
const svc = require('../eventService');

test('older apps: archived (for everyone or by me) and deleted events are left out', async () => {
  expect((await svc.listEvents('brit', { hideArchived: true })).map(e => e.id)).toEqual(['live']);
});

test('apps that file archived events get them, flagged', async () => {
  const all = await svc.listEvents('brit');
  expect(all.map(e => [e.id, e.archived])).toEqual([['live', false], ['old', true], ['mine', true]]);
});
