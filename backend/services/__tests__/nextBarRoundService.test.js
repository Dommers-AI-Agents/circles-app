// NextBar round tests: create-time validation, participant gating, the
// vote→auto-close transaction, tie-breaking, lazy expiry, host close, and the
// client shape that must never leak the uid-keyed votes map. Firestore is an
// in-memory mock (same shape as the piggy bank tests, plus array-contains);
// network/moderation helpers are mocked so the tests are about round logic.

const stores = {};
const store = (name) => (stores[name] = stores[name] || new Map());
let autoId = 0;

function applyMerge(target, value) {
  return { ...(target || {}), ...value };
}

function makeDocRef(col, id) {
  if (!id) id = `auto_${++autoId}`;
  return {
    __col: col, __id: id, id,
    get: async () => ({
      id, exists: store(col).has(id),
      data: () => store(col).get(id),
      ref: makeDocRef(col, id)
    }),
    set: async (value, opts) => {
      store(col).set(id, opts && opts.merge ? applyMerge(store(col).get(id), value) : value);
    },
    update: async (value) => { store(col).set(id, applyMerge(store(col).get(id), value)); }
  };
}

function makeQuery(col, filters = [], order = null, limitN = Infinity) {
  const run = () => {
    let rows = [...store(col).entries()].map(([id, data]) => ({ id, data }));
    for (const [field, op, value] of filters) {
      rows = rows.filter(({ data }) => {
        const v = data[field];
        if (op === '==') return v === value;
        if (op === '>=') return v >= value;
        if (op === '<=') return v <= value;
        if (op === '<') return v < value;
        if (op === 'array-contains') return Array.isArray(v) && v.includes(value);
        return false;
      });
    }
    if (order) rows.sort((a, b) => {
      const av = a.data[order.field]; const bv = b.data[order.field];
      const cmp = av < bv ? -1 : av > bv ? 1 : 0;
      return order.dir === 'desc' ? -cmp : cmp;
    });
    return rows.slice(0, limitN);
  };
  return {
    where: (f, op, v) => makeQuery(col, [...filters, [f, op, v]], order, limitN),
    orderBy: (f, dir = 'asc') => makeQuery(col, filters, { field: f, dir }, limitN),
    limit: (n) => makeQuery(col, filters, order, n),
    get: async () => {
      const rows = run();
      return {
        empty: rows.length === 0,
        size: rows.length,
        docs: rows.map(({ id, data }) => ({ id, exists: true, data: () => data, ref: makeDocRef(col, id) }))
      };
    }
  };
}

const mockDb = {
  collection: (col) => ({
    doc: (id) => makeDocRef(col, id),
    where: (f, op, v) => makeQuery(col, [[f, op, v]]),
    orderBy: (f, dir) => makeQuery(col, [], { field: f, dir })
  }),
  getAll: async (...refs) => refs.map(ref => ({
    id: ref.__id,
    exists: store(ref.__col).has(ref.__id),
    data: () => store(ref.__col).get(ref.__id)
  })),
  runTransaction: async (fn) => {
    const ops = [];
    const tx = {
      get: async (ref) => ({
        id: ref.__id,
        exists: store(ref.__col).has(ref.__id),
        data: () => store(ref.__col).get(ref.__id)
      }),
      set: (ref, value) => { ops.push(() => store(ref.__col).set(ref.__id, value)); },
      update: (ref, value) => {
        ops.push(() => store(ref.__col).set(ref.__id, applyMerge(store(ref.__col).get(ref.__id), value)));
      }
    };
    const result = await fn(tx); // a throw aborts: queued ops never run
    ops.forEach(op => op());
    return result;
  }
};

jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));
jest.mock('../notificationService', () => ({ sendToUser: jest.fn(), sendToUsers: jest.fn() }));

// Accepted connections of the host, settable per test.
let mockConnections = new Set();
jest.mock('../../utils/networkAccess', () => ({
  getConnectedUserIds: jest.fn(async () => mockConnections)
}));

const notificationService = require('../notificationService');
const service = require('../nextBarRoundService');
const { RoundError, toClientRound, pickWinner } = service;

const rounds = () => store('nextbarRounds');
const users = () => store('users');

const HOST = { uid: 'host', displayName: 'Wes' };
const OPTIONS = [
  { placeId: 'p1', name: 'Bar One', address: '1 Main St', source: 'saved', savers: ['Amy'], distanceMeters: 120, lat: 40.7, lng: -74.0, isGlobal: false },
  { placeId: 'p2', name: 'Bar Two', address: '2 Main St', source: 'network', savers: [], distanceMeters: 340.5, lat: 40.71, lng: -74.01, isGlobal: true },
  { placeId: 'p3', name: 'Bar Three' }
];

const seedUsers = () => {
  users().set('host', { displayName: 'Wes' });
  users().set('u1', { displayName: 'Amy' });
  users().set('u2', { displayName: 'Ben' });
  users().set('u3', { displayName: 'Cal' });
};

async function createRound(participantIds = ['u1', 'u2'], extra = {}) {
  return service.createRound(HOST, { participantIds, options: OPTIONS, ...extra });
}

const rejects = (promise, status, code) =>
  expect(promise).rejects.toMatchObject({ status, code });

beforeEach(() => {
  Object.keys(stores).forEach(k => stores[k].clear());
  autoId = 0;
  mockConnections = new Set(['u1', 'u2', 'u3']);
  seedUsers();
  notificationService.sendToUsers.mockClear();
  notificationService.sendToUsers.mockResolvedValue([]);
});

describe('createRound', () => {
  test('stores the round with host first, defaults, and pushes to everyone but the host', async () => {
    const before = Date.now();
    const round = await createRound();
    expect(round).toMatchObject({
      hostId: 'host', hostName: 'Wes', status: 'open', winnerPlaceId: null, closedAt: null,
      isHost: true, myVote: null
    });
    expect(round.participants).toEqual([
      { id: 'host', name: 'Wes', voted: false },
      { id: 'u1', name: 'Amy', voted: false },
      { id: 'u2', name: 'Ben', voted: false }
    ]);
    expect(round.options.map(o => o.placeId)).toEqual(['p1', 'p2', 'p3']);
    expect(round.options[0]).toMatchObject({ ...OPTIONS[0], votes: 0, voters: [] });
    expect(round.options[2]).toMatchObject({
      placeId: 'p3', name: 'Bar Three', address: null, source: null, savers: [],
      distanceMeters: null, lat: null, lng: null, isGlobal: false, votes: 0, voters: []
    });
    // Default expiry: 180 minutes after createdAt
    expect(Date.parse(round.expiresAt) - Date.parse(round.createdAt)).toBe(180 * 60 * 1000);
    expect(Date.parse(round.createdAt)).toBeGreaterThanOrEqual(before);

    const stored = rounds().get(round.id);
    expect(stored.participantIds).toEqual(['host', 'u1', 'u2']);
    expect(stored.votes).toEqual({});

    expect(notificationService.sendToUsers).toHaveBeenCalledTimes(1);
    const [recipients, push] = notificationService.sendToUsers.mock.calls[0];
    expect(recipients).toEqual(['u1', 'u2']);
    expect(push).toEqual({
      type: 'nextbar_round',
      title: '🍸 Wes started a bar vote',
      body: 'Tap to vote on where you\'re going next',
      data: { type: 'nextbar_round', roundId: round.id }
    });
  });

  test('participants: must be 1..10, not self, deduped, normalized', async () => {
    await rejects(createRound([]), 400, 'invalid_participants');
    await rejects(createRound('u1'), 400, 'invalid_participants');
    await rejects(createRound(['host']), 400, 'invalid_participants');
    await rejects(createRound(['u1', 'x.host.y']), 400, 'invalid_participants');
    const eleven = Array.from({ length: 11 }, (_, i) => `n${i}`);
    await rejects(createRound(eleven), 400, 'invalid_participants');
    expect(rounds().size).toBe(0);

    const round = await createRound(['u1', 'u1', 'abc.u2.def']);
    expect(round.participants.map(p => p.id)).toEqual(['host', 'u1', 'u2']);
  });

  test('unknown participant → 404, non-connection → 403 naming the offender, blocked → 403', async () => {
    await rejects(createRound(['u1', 'ghost']), 404, 'user_not_found');

    mockConnections = new Set(['u1']);
    await expect(createRound(['u1', 'u2'])).rejects.toMatchObject({
      status: 403, code: 'not_connected', userId: 'u2', message: expect.stringContaining('Ben')
    });

    mockConnections = new Set(['u1', 'u2']);
    users().set('host', { displayName: 'Wes', blockedBy: ['u2'] });
    await rejects(createRound(['u1', 'u2']), 403, 'blocked');
    expect(rounds().size).toBe(0);
    expect(notificationService.sendToUsers).not.toHaveBeenCalled();
  });

  test('options: 2..5, placeId/name strings required, savers ≤10 strings, numbers finite, unique placeIds', async () => {
    const opt = (over) => ({ placeId: 'p9', name: 'Bar', ...over });
    const bad = [
      [OPTIONS.slice(0, 1)],
      [[...OPTIONS, opt({ placeId: 'p4' }), opt({ placeId: 'p5' }), opt({ placeId: 'p6' })]],
      [[OPTIONS[0], 'nope']],
      [[OPTIONS[0], opt({ placeId: 7 })]],
      [[OPTIONS[0], opt({ name: '' })]],
      [[OPTIONS[0], opt({ savers: 'Amy' })]],
      [[OPTIONS[0], opt({ savers: [1] })]],
      [[OPTIONS[0], opt({ savers: Array(11).fill('a') })]],
      [[OPTIONS[0], opt({ distanceMeters: '12' })]],
      [[OPTIONS[0], opt({ lat: NaN })]],
      [[OPTIONS[0], opt({ lng: Infinity })]],
      [[OPTIONS[0], opt({ placeId: 'p1' })]]
    ];
    for (const [options] of bad) {
      await rejects(createRound(['u1'], { options }), 400, 'invalid_options');
    }
    expect(rounds().size).toBe(0);
  });

  test('expiresInMinutes: 15..1440 integer when given', async () => {
    for (const v of [14, 1441, 30.5, '60']) {
      await rejects(createRound(['u1'], { expiresInMinutes: v }), 400, 'invalid_expiry');
    }
    const round = await createRound(['u1'], { expiresInMinutes: 15 });
    expect(Date.parse(round.expiresAt) - Date.parse(round.createdAt)).toBe(15 * 60 * 1000);
  });

  test('a push failure never fails the create', async () => {
    notificationService.sendToUsers.mockRejectedValueOnce(new Error('fcm down'));
    const round = await createRound();
    expect(rounds().has(round.id)).toBe(true);
  });
});

describe('vote', () => {
  test('non-participant → 403, unknown round → 404, non-option → 400', async () => {
    const round = await createRound(['u1']);
    await rejects(service.vote('u3', round.id, 'p1'), 403, 'not_participant');
    await rejects(service.vote('u1', 'nope', 'p1'), 404, 'round_not_found');
    await rejects(service.vote('u1', round.id, 'p9'), 400, 'invalid_option');
    await rejects(service.vote('u1', round.id, ''), 400, 'invalid_option');
    expect(rounds().get(round.id).votes).toEqual({});
  });

  test('records and can change a vote; round stays open until everyone voted', async () => {
    const round = await createRound(['u1', 'u2']);
    let r = await service.vote('u1', round.id, 'p1');
    expect(r.status).toBe('open');
    expect(r.myVote).toBe('p1');
    expect(r.participants.find(p => p.id === 'u1').voted).toBe(true);
    r = await service.vote('u1', round.id, 'p2');
    expect(r.myVote).toBe('p2');
    expect(rounds().get(round.id).votes).toEqual({ u1: 'p2' });
    expect(notificationService.sendToUsers).toHaveBeenCalledTimes(1); // only the start push
  });

  test('last vote auto-closes with the right winner and pushes the result to all', async () => {
    const round = await createRound(['u1', 'u2']);
    await service.vote('host', round.id, 'p2');
    await service.vote('u1', round.id, 'p2');
    const final = await service.vote('u2', round.id, 'p1');
    expect(final.status).toBe('closed');
    expect(final.winnerPlaceId).toBe('p2');
    expect(final.closedAt).toBeTruthy();
    expect(final.options.find(o => o.placeId === 'p2')).toMatchObject({ votes: 2, voters: ['Wes', 'Amy'] });
    expect(final.options.find(o => o.placeId === 'p1')).toMatchObject({ votes: 1, voters: ['Ben'] });

    const stored = rounds().get(round.id);
    expect(stored).toMatchObject({ status: 'closed', winnerPlaceId: 'p2', votes: { host: 'p2', u1: 'p2', u2: 'p1' } });

    const resultCalls = notificationService.sendToUsers.mock.calls.filter(([, n]) => n.type === 'nextbar_result');
    expect(resultCalls).toHaveLength(1);
    expect(resultCalls[0][0]).toEqual(['host', 'u1', 'u2']);
    expect(resultCalls[0][1]).toEqual({
      type: 'nextbar_result',
      title: '🍸 It\'s Bar Two!',
      body: '3 of 3 voted',
      data: { type: 'nextbar_round', roundId: round.id }
    });
  });

  test('a tie picks one of the tied options', async () => {
    const round = await createRound(['u1']);
    await service.vote('host', round.id, 'p1');
    const final = await service.vote('u1', round.id, 'p3');
    expect(final.status).toBe('closed');
    expect(['p1', 'p3']).toContain(final.winnerPlaceId);
  });

  test('voting on a closed round → 409 and the result is not re-sent', async () => {
    const round = await createRound(['u1']);
    await service.vote('host', round.id, 'p1');
    await service.vote('u1', round.id, 'p1');
    await rejects(service.vote('u1', round.id, 'p2'), 409, 'round_closed');
    expect(rounds().get(round.id).votes).toEqual({ host: 'p1', u1: 'p1' });
    const resultCalls = notificationService.sendToUsers.mock.calls.filter(([, n]) => n.type === 'nextbar_result');
    expect(resultCalls).toHaveLength(1);
  });

  test('a vote on an expired-but-open round closes it (persisted) and is rejected', async () => {
    const round = await createRound(['u1']);
    rounds().set(round.id, { ...rounds().get(round.id), expiresAt: '2000-01-01T00:00:00.000Z' });
    await rejects(service.vote('u1', round.id, 'p1'), 409, 'round_closed');
    const stored = rounds().get(round.id);
    expect(stored.status).toBe('closed');
    expect(['p1', 'p2', 'p3']).toContain(stored.winnerPlaceId);
    expect(stored.votes).toEqual({});
  });
});

describe('listRounds / getRound', () => {
  test('lists only my rounds, newest first, capped at 20', async () => {
    for (let i = 0; i < 22; i++) {
      const data = {
        hostId: 'host', hostName: 'Wes', participantIds: ['host', 'u1'],
        participants: [{ id: 'host', name: 'Wes' }, { id: 'u1', name: 'Amy' }],
        options: OPTIONS.slice(0, 2), votes: {}, status: 'closed', winnerPlaceId: 'p1',
        createdAt: new Date(Date.UTC(2026, 0, 1 + i)).toISOString(),
        expiresAt: new Date(Date.UTC(2026, 0, 2 + i)).toISOString(), closedAt: null
      };
      rounds().set(`r${i}`, data);
    }
    rounds().set('other', { ...rounds().get('r0'), participantIds: ['u2', 'u3'], createdAt: '2027-01-01T00:00:00.000Z' });

    const mine = await service.listRounds('u1');
    expect(mine).toHaveLength(20);
    expect(mine[0].id).toBe('r21');
    expect(mine[19].id).toBe('r2');
    expect(mine.map(r => r.id)).not.toContain('other');
    expect(mine[0].isHost).toBe(false);

    expect(await service.listRounds('u3')).toEqual(expect.arrayContaining([expect.objectContaining({ id: 'other' })]));
  });

  test('an expired open round is closed by the list call (winner persisted, result pushed)', async () => {
    const round = await createRound(['u1', 'u2']);
    await service.vote('u1', round.id, 'p3');
    rounds().set(round.id, { ...rounds().get(round.id), expiresAt: '2000-01-01T00:00:00.000Z' });
    const live = await createRound(['u1']);

    const list = await service.listRounds('u1');
    const expired = list.find(r => r.id === round.id);
    expect(expired.status).toBe('closed');
    expect(expired.winnerPlaceId).toBe('p3');
    expect(expired.closedAt).toBeTruthy();
    expect(list.find(r => r.id === live.id).status).toBe('open');

    expect(rounds().get(round.id)).toMatchObject({ status: 'closed', winnerPlaceId: 'p3' });
    const resultCalls = notificationService.sendToUsers.mock.calls.filter(([, n]) => n.type === 'nextbar_result');
    expect(resultCalls).toHaveLength(1);
    expect(resultCalls[0][1].body).toBe('1 of 3 voted');

    // A second list doesn't re-close or re-push
    await service.listRounds('u1');
    expect(notificationService.sendToUsers.mock.calls.filter(([, n]) => n.type === 'nextbar_result')).toHaveLength(1);
  });

  test('getRound: participants only, 404 when missing', async () => {
    const round = await createRound(['u1']);
    expect((await service.getRound('u1', round.id)).id).toBe(round.id);
    await rejects(service.getRound('u2', round.id), 403, 'not_participant');
    await rejects(service.getRound('u1', 'nope'), 404, 'round_not_found');
  });
});

describe('closeRound', () => {
  test('host only', async () => {
    const round = await createRound(['u1']);
    await rejects(service.closeRound('u1', round.id), 403, 'not_host');
    await rejects(service.closeRound('u3', round.id), 403, 'not_host');
    expect(rounds().get(round.id).status).toBe('open');
  });

  test('with zero votes picks some option and pushes the result to all', async () => {
    const round = await createRound(['u1', 'u2']);
    const closed = await service.closeRound('host', round.id);
    expect(closed.status).toBe('closed');
    expect(['p1', 'p2', 'p3']).toContain(closed.winnerPlaceId);
    expect(rounds().get(round.id).winnerPlaceId).toBe(closed.winnerPlaceId);
    const resultCalls = notificationService.sendToUsers.mock.calls.filter(([, n]) => n.type === 'nextbar_result');
    expect(resultCalls).toHaveLength(1);
    expect(resultCalls[0][0]).toEqual(['host', 'u1', 'u2']);
    expect(resultCalls[0][1].body).toBe('0 of 3 voted');
  });

  test('respects partial votes; a second close is a no-op without a second push', async () => {
    const round = await createRound(['u1', 'u2']);
    await service.vote('u2', round.id, 'p3');
    const closed = await service.closeRound('host', round.id);
    expect(closed.winnerPlaceId).toBe('p3');
    const again = await service.closeRound('host', round.id);
    expect(again).toEqual(closed);
    expect(notificationService.sendToUsers.mock.calls.filter(([, n]) => n.type === 'nextbar_result')).toHaveLength(1);
  });
});

describe('pickWinner', () => {
  test('most votes wins; ties and no-votes stay within the candidates', () => {
    const opts = OPTIONS;
    expect(pickWinner(opts, { a: 'p1', b: 'p2', c: 'p2' })).toBe('p2');
    for (let i = 0; i < 20; i++) {
      expect(['p1', 'p2']).toContain(pickWinner(opts, { a: 'p1', b: 'p2' }));
      expect(['p1', 'p2', 'p3']).toContain(pickWinner(opts, {}));
    }
    // Stray votes for non-options are ignored
    expect(pickWinner(opts, { a: 'zzz', b: 'p3' })).toBe('p3');
  });
});

describe('toClientRound', () => {
  const doc = {
    id: 'r1', hostId: 'host', hostName: 'Wes', status: 'open', winnerPlaceId: null,
    createdAt: '2026-09-13T00:00:00.000Z', expiresAt: '2026-09-13T03:00:00.000Z', closedAt: null,
    participantIds: ['host', 'u1', 'u2'],
    participants: [{ id: 'host', name: 'Wes' }, { id: 'u1', name: 'Amy' }, { id: 'u2', name: 'Ben' }],
    options: OPTIONS.slice(0, 2),
    votes: { host: 'p1', u1: 'p2' }
  };

  test('hides other users\' uids: no votes map, voters are names, myVote is only mine', () => {
    const asBen = toClientRound(doc, 'u2');
    expect(asBen).not.toHaveProperty('votes');
    expect(asBen).not.toHaveProperty('participantIds');
    expect(asBen.myVote).toBeNull();
    expect(asBen.isHost).toBe(false);
    expect(asBen.options).toEqual([
      { ...OPTIONS[0], votes: 1, voters: ['Wes'] },
      { ...OPTIONS[1], votes: 1, voters: ['Amy'] }
    ]);
    expect(asBen.participants).toEqual([
      { id: 'host', name: 'Wes', voted: true },
      { id: 'u1', name: 'Amy', voted: true },
      { id: 'u2', name: 'Ben', voted: false }
    ]);
    expect(JSON.stringify(asBen.options)).not.toMatch(/"host"|"u1"/);

    const asAmy = toClientRound(doc, 'u1');
    expect(asAmy.myVote).toBe('p2');
    expect(toClientRound(doc, 'host').isHost).toBe(true);
  });

  test('accepts a Firestore snapshot as well as a plain object', () => {
    const snap = { id: 'r1', exists: true, data: () => doc };
    expect(toClientRound(snap, 'u1').id).toBe('r1');
    expect(toClientRound(null, 'u1')).toBeNull();
  });
});
