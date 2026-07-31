// Piggy bank ledger tests: idempotency, caps, pair-key symmetry, clearing
// validation, and bank/ledger arithmetic. Firestore is an in-memory mock —
// what's under test is the money logic, which must never drift or double-pay.

const stores = {};
const store = (name) => (stores[name] = stores[name] || new Map());

const isInc = (v) => v && typeof v === 'object' && v.__op === '__inc';

function applyMerge(target, value) {
  const out = { ...(target || {}) };
  for (const [k, v] of Object.entries(value)) {
    out[k] = isInc(v) ? (out[k] || 0) + v.n : v;
  }
  return out;
}

function makeDocRef(col, id) {
  return {
    __col: col, __id: id,
    get: async () => ({
      exists: store(col).has(id),
      data: () => store(col).get(id),
      ref: makeDocRef(col, id)
    }),
    set: async (value, opts) => {
      store(col).set(id, opts && opts.merge ? applyMerge(store(col).get(id), value) : value);
    }
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
    count: () => ({ get: async () => ({ data: () => ({ count: run().length }) }) }),
    get: async () => {
      const rows = run();
      return {
        empty: rows.length === 0,
        size: rows.length,
        docs: rows.map(({ id, data }) => ({
          id, exists: true, data: () => data, ref: makeDocRef(col, id)
        }))
      };
    }
  };
}

const mockDb = {
  collection: (col) => ({
    doc: (id) => makeDocRef(col, id),
    where: (f, op, v) => makeQuery(col, [[f, op, v]]),
    orderBy: (f, dir) => makeQuery(col, [], { field: f, dir }),
  }),
  runTransaction: async (fn) => {
    const ops = [];
    const tx = {
      get: async (ref) => ({
        exists: store(ref.__col).has(ref.__id),
        data: () => store(ref.__col).get(ref.__id)
      }),
      create: (ref, value) => {
        if (store(ref.__col).has(ref.__id)) {
          const err = new Error('already exists');
          err.code = 6;
          throw err;
        }
        ops.push(() => store(ref.__col).set(ref.__id, value));
      },
      set: (ref, value, opts) => {
        ops.push(() => store(ref.__col).set(
          ref.__id,
          opts && opts.merge ? applyMerge(store(ref.__col).get(ref.__id), value) : value
        ));
      },
      update: (ref, value) => {
        ops.push(() => store(ref.__col).set(
          ref.__id, applyMerge(store(ref.__col).get(ref.__id), value)
        ));
      }
    };
    await fn(tx);
    ops.forEach(op => op());
  }
};

jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  get FieldValue() {
    return { increment: (n) => ({ __op: '__inc', n }) };
  }
}));

const piggyBank = require('../piggyBankService');
const { derivePiggyDedupKey } = require('../../models/PiggyBankModels');
const config = require('../../config/piggyBankConfig');

const bankOf = (uid) => stores.piggyBanks?.get(uid) || {};
const ledgerRows = () => [...(stores.piggyLedger || new Map()).values()];
const backdateAll = () => {
  for (const [id, row] of stores.piggyLedger.entries()) {
    stores.piggyLedger.set(id, { ...row, clearAt: '2000-01-01T00:00:00.000Z' });
  }
};

beforeEach(() => { Object.keys(stores).forEach(k => stores[k].clear()); });

describe('derivePiggyDedupKey', () => {
  test('add_place venue identity: venueKey leads, then globalPlaceId, then placeId', () => {
    expect(derivePiggyDedupKey('add_place', { userId: 'u1', venueKey: 'google:x', globalPlaceId: 'g1', placeId: 'p1' }))
      .toBe('add_place:u1:google:x');
    expect(derivePiggyDedupKey('add_place', { userId: 'u1', globalPlaceId: 'g1', placeId: 'p1' }))
      .toBe('add_place:u1:g1');
    expect(derivePiggyDedupKey('add_place', { userId: 'u1', placeId: 'p1' }))
      .toBe('add_place:u1:p1');
    expect(derivePiggyDedupKey('add_place', { userId: 'u1' })).toBeNull();
  });

  test('add_place key is identical whether or not venue linking succeeded', () => {
    // Add #1: linking worked. Add #2 (delete -> re-add): linking failed, new
    // doc id. Same venueKey -> same key -> second add can never pay.
    const linked = derivePiggyDedupKey('add_place', {
      userId: 'u1', venueKey: 'google:abc', globalPlaceId: 'gDoc1', placeId: 'save1'
    });
    const unlinked = derivePiggyDedupKey('add_place', {
      userId: 'u1', venueKey: 'google:abc', globalPlaceId: null, placeId: 'save2'
    });
    expect(linked).toBe(unlinked);
  });

  test('connection key is order-independent per pair, distinct per beneficiary', () => {
    const aSide = derivePiggyDedupKey('connection_accepted', { userId: 'alice', otherUserId: 'bob' });
    const bSide = derivePiggyDedupKey('connection_accepted', { userId: 'bob', otherUserId: 'alice' });
    expect(aSide).toBe('connection:alice:bob:alice');
    expect(bSide).toBe('connection:alice:bob:bob');
    expect(aSide).not.toBe(bSide);
  });

  test('referral key is one-per-invitee regardless of referrer', () => {
    expect(derivePiggyDedupKey('referral_signup', { userId: 'ref1', inviteeId: 'newbie' }))
      .toBe('referral:newbie');
  });

  test('sanitizes slashes and dots in parts', () => {
    expect(derivePiggyDedupKey('suggestion_posted', { userId: 'u.1', suggestionId: 'a/b' }))
      .toBe('suggestion:u_1:a_b');
  });
});

describe('credit', () => {
  test('pays the configured coins into pending and writes one ledger row', async () => {
    const r = await piggyBank.credit({
      userId: 'u1', eventType: 'add_place', sourceRef: { placeId: 'p1', globalPlaceId: 'g1' }
    });
    expect(r).toEqual({ credited: true, coins: config.COINS.ADD_PLACE, eventType: 'add_place' });
    expect(bankOf('u1').pendingCoins).toBe(config.COINS.ADD_PLACE);
    expect(ledgerRows()).toHaveLength(1);
    expect(ledgerRows()[0].status).toBe('pending');
    expect(ledgerRows()[0].ruleVersion).toBe(config.RULE_VERSION);
  });

  test('double credit for the same event is blocked and does not bump the bank', async () => {
    const ref = { placeId: 'p1', globalPlaceId: 'g1' };
    await piggyBank.credit({ userId: 'u1', eventType: 'add_place', sourceRef: ref });
    const second = await piggyBank.credit({ userId: 'u1', eventType: 'add_place', sourceRef: ref });
    expect(second.credited).toBe(false);
    expect(second.duplicate).toBe(true);
    expect(ledgerRows()).toHaveLength(1);
    expect(bankOf('u1').pendingCoins).toBe(config.COINS.ADD_PLACE);
  });

  test('delete -> re-add of the same venue never pays twice (new doc id, no link)', async () => {
    const first = await piggyBank.credit({
      userId: 'u1', eventType: 'add_place',
      sourceRef: { placeId: 'doc1', globalPlaceId: 'g1', venueKey: 'manual:salty donut:belmar' }
    });
    // Re-added later: brand-new save doc, linking failed this time
    const readd = await piggyBank.credit({
      userId: 'u1', eventType: 'add_place',
      sourceRef: { placeId: 'doc2', globalPlaceId: null, venueKey: 'manual:salty donut:belmar' }
    });
    expect(first.credited).toBe(true);
    expect(readd.credited).toBe(false);
    expect(readd.duplicate).toBe(true);
    expect(ledgerRows()).toHaveLength(1);
    expect(bankOf('u1').pendingCoins).toBe(config.COINS.ADD_PLACE);
  });

  test('a REVERSED row still blocks re-earning the same venue (append-only)', async () => {
    store('places').set('doc1', { deletedAt: '2026-07-31T00:00:00Z' }); // deleted during window
    await piggyBank.credit({
      userId: 'u1', eventType: 'add_place',
      sourceRef: { placeId: 'doc1', venueKey: 'google:abc' }
    });
    backdateAll();
    await piggyBank.runClearing(); // -> reversed, pending back to 0

    const again = await piggyBank.credit({
      userId: 'u1', eventType: 'add_place',
      sourceRef: { placeId: 'doc2', venueKey: 'google:abc' }
    });
    expect(again.duplicate).toBe(true);
    expect(ledgerRows()).toHaveLength(1);
    expect(bankOf('u1').pendingCoins).toBe(0);
  });

  test('daily cap: at the cap the action pays zero', async () => {
    for (let i = 0; i < config.DAILY_CAPS.SUGGESTION_POSTED; i++) {
      await piggyBank.credit({
        userId: 'u1', eventType: 'suggestion_posted', sourceRef: { suggestionId: `s${i}` }
      });
    }
    const over = await piggyBank.credit({
      userId: 'u1', eventType: 'suggestion_posted', sourceRef: { suggestionId: 'sX' }
    });
    expect(over).toEqual({ credited: false, eventType: 'suggestion_posted', reason: 'daily_cap' });
    expect(ledgerRows()).toHaveLength(config.DAILY_CAPS.SUGGESTION_POSTED);
  });

  test('connection pair: A→B and B→A collide per beneficiary; both sides earn once each', async () => {
    const first = await piggyBank.credit({
      userId: 'alice', eventType: 'connection_accepted',
      sourceRef: { otherUserId: 'bob', connectionId: 'c1' }
    });
    const replayOtherDirection = await piggyBank.credit({
      userId: 'alice', eventType: 'connection_accepted',
      sourceRef: { otherUserId: 'bob', connectionId: 'c1-dup' }
    });
    const bobsOwn = await piggyBank.credit({
      userId: 'bob', eventType: 'connection_accepted',
      sourceRef: { otherUserId: 'alice', connectionId: 'c1' }
    });
    expect(first.credited).toBe(true);
    expect(replayOtherDirection.duplicate).toBe(true);
    expect(bobsOwn.credited).toBe(true);
    expect(ledgerRows()).toHaveLength(2);
    expect(bankOf('alice').pendingCoins).toBe(config.COINS.CONNECTION_ACCEPTED);
    expect(bankOf('bob').pendingCoins).toBe(config.COINS.CONNECTION_ACCEPTED);
  });

  test('unknown event type is a no-op, never a throw', async () => {
    const r = await piggyBank.credit({ userId: 'u1', eventType: 'jackpot', sourceRef: {} });
    expect(r.credited).toBe(false);
    expect(ledgerRows()).toHaveLength(0);
  });
});

describe('runClearing', () => {
  test('confirms a valid add_place and moves pending → confirmed + lifetime', async () => {
    store('places').set('p1', { deletedAt: null });
    await piggyBank.credit({ userId: 'u1', eventType: 'add_place', sourceRef: { placeId: 'p1' } });
    backdateAll();

    const summary = await piggyBank.runClearing();
    expect(summary).toMatchObject({ scanned: 1, confirmed: 1, reversed: 0 });
    expect(ledgerRows()[0].status).toBe('confirmed');
    const bank = bankOf('u1');
    expect(bank.pendingCoins).toBe(0);
    expect(bank.confirmedCoins).toBe(config.COINS.ADD_PLACE);
    expect(bank.lifetimeCoins).toBe(config.COINS.ADD_PLACE);
  });

  test('reverses when the place was deleted during the window', async () => {
    store('places').set('p1', { deletedAt: '2026-07-31T00:00:00Z' });
    await piggyBank.credit({ userId: 'u1', eventType: 'add_place', sourceRef: { placeId: 'p1' } });
    backdateAll();

    const summary = await piggyBank.runClearing();
    expect(summary.reversed).toBe(1);
    expect(ledgerRows()[0].status).toBe('reversed');
    expect(ledgerRows()[0].reverseReason).toBe('place_deleted');
    const bank = bankOf('u1');
    expect(bank.pendingCoins).toBe(0);
    expect(bank.confirmedCoins || 0).toBe(0);
  });

  test('create_circle below the minimum place count reverses', async () => {
    store('circles').set('c1', { placesCount: config.CREATE_CIRCLE_MIN_PLACES - 1 });
    await piggyBank.credit({ userId: 'u1', eventType: 'create_circle', sourceRef: { circleId: 'c1' } });
    backdateAll();

    const summary = await piggyBank.runClearing();
    expect(summary.reversed).toBe(1);
    expect(ledgerRows()[0].reverseReason).toBe('circle_below_min_places');
  });

  test('referral without invitee activation reverses; with activation confirms', async () => {
    store('users').set('newbie', { referredBy: 'ref1' });
    await piggyBank.credit({ userId: 'ref1', eventType: 'referral_signup', sourceRef: { inviteeId: 'newbie' } });
    backdateAll();
    let summary = await piggyBank.runClearing();
    expect(summary.reversed).toBe(1);
    expect(ledgerRows()[0].reverseReason).toBe('invitee_not_activated');

    // Second referral, activated invitee (has a place)
    store('users').set('newbie2', { referredBy: 'ref1' });
    store('places').set('np1', { addedBy: 'newbie2', deletedAt: null });
    await piggyBank.credit({ userId: 'ref1', eventType: 'referral_signup', sourceRef: { inviteeId: 'newbie2' } });
    backdateAll();
    summary = await piggyBank.runClearing();
    expect(summary.confirmed).toBe(1);
  });

  test('bank matches ledger after a mixed confirm/reverse batch', async () => {
    store('places').set('good', { deletedAt: null });
    store('places').set('gone', { deletedAt: '2026-07-31T00:00:00Z' });
    store('suggestions').set('s1', { text: 'hi' });
    await piggyBank.credit({ userId: 'u1', eventType: 'add_place', sourceRef: { placeId: 'good' } });
    await piggyBank.credit({ userId: 'u1', eventType: 'add_place', sourceRef: { placeId: 'gone' } });
    await piggyBank.credit({ userId: 'u1', eventType: 'suggestion_posted', sourceRef: { suggestionId: 's1' } });
    backdateAll();

    await piggyBank.runClearing();
    const recon = await piggyBank.reconcile('u1');
    expect(recon.drift).toBe(false);
    expect(recon.computed.confirmedCoins).toBe(config.COINS.ADD_PLACE + config.COINS.SUGGESTION_POSTED);
    expect(recon.computed.pendingCoins).toBe(0);
  });

  test('a not-yet-cleared row is untouched', async () => {
    store('places').set('p1', { deletedAt: null });
    await piggyBank.credit({ userId: 'u1', eventType: 'add_place', sourceRef: { placeId: 'p1' } });
    // no backdate — clearAt is 48h out
    const summary = await piggyBank.runClearing();
    expect(summary.scanned).toBe(0);
    expect(ledgerRows()[0].status).toBe('pending');
  });
});
