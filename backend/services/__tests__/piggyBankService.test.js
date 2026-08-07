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
    },
    update: async (value) => {
      store(col).set(id, applyMerge(store(col).get(id), value));
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
    const result = await fn(tx);
    ops.forEach(op => op());
    return result;
  }
};

jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  get FieldValue() {
    return { increment: (n) => ({ __op: '__inc', n }) };
  }
}));

// Controllable stand-in for the broker client. Settlement tests script its
// outcomes; claim-only tests disable it so the inline settlement kick returns
// immediately and can't race the assertions.
const mockCactusWallet = {
  enabled: false,
  sendResult: { outcome: 'sent', txId: 'tx_test_1' },
  confirmedTxs: new Set(),
  health: { ok: true },
  isEnabled: jest.fn(() => mockCactusWallet.enabled),
  explorerBaseUrl: jest.fn(() => 'https://explorer.cactus-network.net/#/'),
  explorerCoinUrl: jest.fn((coinId) => coinId
    ? `https://explorer.cactus-network.net/#/coin/${coinId}` : null),
  computeCoinId: jest.fn(() => 'coin_test_1'),
  sendCat: jest.fn(async () => mockCactusWallet.sendResult),
  getTransaction: jest.fn(async (txId) => ({
    confirmed: mockCactusWallet.confirmedTxs.has(txId),
    confirmedAtHeight: mockCactusWallet.confirmedTxs.has(txId) ? 123456 : null,
    additions: []
  })),
  getTransactionConfirmed: jest.fn(async (txId) => mockCactusWallet.confirmedTxs.has(txId)),
  getWallets: jest.fn(async () => []),
  healthz: jest.fn(async () => mockCactusWallet.health)
};
jest.mock('../cactusWalletService', () => mockCactusWallet);

const piggyBank = require('../piggyBankService');
const { derivePiggyDedupKey, createPiggyClaimEntry } = require('../../models/PiggyBankModels');
const config = require('../../config/piggyBankConfig');

const bankOf = (uid) => stores.piggyBanks?.get(uid) || {};
const ledgerRows = () => [...(stores.piggyLedger || new Map()).values()];
const backdateAll = () => {
  for (const [id, row] of stores.piggyLedger.entries()) {
    stores.piggyLedger.set(id, { ...row, clearAt: '2000-01-01T00:00:00.000Z' });
  }
};

beforeEach(() => {
  Object.keys(stores).forEach(k => stores[k].clear());
  mockCactusWallet.enabled = false;
  mockCactusWallet.sendResult = { outcome: 'sent', txId: 'tx_test_1' };
  mockCactusWallet.confirmedTxs.clear();
  mockCactusWallet.health = { ok: true };
  mockCactusWallet.sendCat.mockClear();
  mockCactusWallet.getTransaction.mockClear();
  mockCactusWallet.getTransactionConfirmed.mockClear();
  mockCactusWallet.healthz.mockClear();
});

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

// ---- Claims (Phase 4: on-chain settlement) ---------------------------------

const seedBank = (uid, fields) => store('piggyBanks').set(uid, fields);
const claimRowOf = (uid, seq = 1) => stores.piggyLedger.get(`claim:${uid}:${seq}`);

describe('claim (T1)', () => {
  test('dedup key shape', () => {
    expect(derivePiggyDedupKey('claim', { userId: 'u1', seq: 3 })).toBe('claim:u1:3');
    expect(derivePiggyDedupKey('claim', { userId: 'u1' })).toBeNull();
  });

  test('no wallet linked → no_wallet', async () => {
    seedBank('u1', { confirmedCoins: 600 });
    expect((await piggyBank.claim('u1')).code).toBe('no_wallet');
  });

  test('below minimum → below_minimum with amounts', async () => {
    // Derived from config so a re-priced minimum can't silently invert this
    const justBelow = config.CLAIM.MIN_CONFIRMED_TO_CLAIM - 1;
    seedBank('u1', { confirmedCoins: justBelow, walletAddress: 'cac1qtest' });
    const res = await piggyBank.claim('u1');
    expect(res.code).toBe('below_minimum');
    expect(res.minimum).toBe(config.CLAIM.MIN_CONFIRMED_TO_CLAIM);
    expect(res.confirmed).toBe(justBelow);
  });

  test('happy path snapshots the full balance and locks the bank', async () => {
    seedBank('u1', { confirmedCoins: 600, lifetimeCoins: 600, walletAddress: 'cac1qtest' });
    const res = await piggyBank.claim('u1');
    expect(res.ok).toBe(true);
    expect(res.claim.coins).toBe(600);
    expect(res.claim.mojos).toBe(600 * config.CLAIM.MOJOS_PER_CAT);
    const bank = bankOf('u1');
    expect(bank.confirmedCoins).toBe(0);
    expect(bank.activeClaimId).toBe('claim:u1:1');
    expect(bank.claimCount).toBe(1);
    const row = claimRowOf('u1');
    expect(row.status).toBe('claim_pending');
    expect(row.address).toBe('cac1qtest');
  });

  test('second claim while one is in flight → claim_in_flight', async () => {
    seedBank('u1', { confirmedCoins: 1200, walletAddress: 'cac1qtest' });
    await piggyBank.claim('u1');
    seedBank('u1', { ...bankOf('u1'), confirmedCoins: 800 }); // earns arrived later
    expect((await piggyBank.claim('u1')).code).toBe('claim_in_flight');
  });

  test('dedup-key collision (activeClaimId race) → claim_in_flight, bank untouched', async () => {
    // Simulates the loser of a concurrent double-tap: activeClaimId not yet
    // visible, but the claim:u1:1 row already exists.
    seedBank('u1', { confirmedCoins: 600, claimCount: 0, walletAddress: 'cac1qtest' });
    stores.piggyLedger.set('claim:u1:1', { userId: 'u1', eventType: 'claim', status: 'claim_pending', coins: 600 });
    const res = await piggyBank.claim('u1');
    expect(res.code).toBe('claim_in_flight');
    expect(bankOf('u1').confirmedCoins).toBe(600);
  });

  test('fee math freezes onto the row', () => {
    const origFee = config.CLAIM.CLAIM_FEE_COINS;
    config.CLAIM.CLAIM_FEE_COINS = 10;
    try {
      const entry = createPiggyClaimEntry({ userId: 'u1', confirmedCoins: 600, address: 'cac1q' });
      expect(entry.coins).toBe(600);
      expect(entry.feeCoins).toBe(10);
      expect(entry.netCoins).toBe(590);
      expect(entry.catAmount).toBe(590);
      expect(entry.mojos).toBe(590000);
    } finally {
      config.CLAIM.CLAIM_FEE_COINS = origFee;
    }
  });
});

describe('runSettlement (T2–T7)', () => {
  const setupClaim = async (uid = 'u1', coins = 600) => {
    seedBank(uid, { confirmedCoins: coins, walletAddress: 'cac1qtest' });
    await piggyBank.claim(uid); // wallet disabled in beforeEach → no inline send
  };

  test('disabled wallet → inert summary', async () => {
    await setupClaim();
    const summary = await piggyBank.runSettlement();
    expect(summary.disabled).toBe(true);
    expect(claimRowOf('u1').status).toBe('claim_pending');
  });

  test('happy path: pending → sent → settled with bank math', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;

    let summary = await piggyBank.runSettlement();
    expect(summary.sent).toBe(1);
    let row = claimRowOf('u1');
    expect(row.status).toBe('claim_sent');
    expect(row.txId).toBe('tx_test_1');
    expect(mockCactusWallet.sendCat).toHaveBeenCalledTimes(1);
    expect(mockCactusWallet.sendCat.mock.calls[0][0].mojos).toBe(600000);

    // Not confirmed yet → stays sent
    summary = await piggyBank.runSettlement();
    expect(summary.settled).toBe(0);
    expect(mockCactusWallet.sendCat).toHaveBeenCalledTimes(1); // never re-sent

    mockCactusWallet.confirmedTxs.add('tx_test_1');
    summary = await piggyBank.runSettlement();
    expect(summary.settled).toBe(1);
    row = claimRowOf('u1');
    expect(row.status).toBe('settled');
    const bank = bankOf('u1');
    expect(bank.settledOnChain).toBe(600);
    expect(bank.activeClaimId).toBeNull();
  });

  test('rejected send → refund and terminal claim_failed', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;
    mockCactusWallet.sendResult = { outcome: 'rejected', reason: 'insufficient_funds' };

    const summary = await piggyBank.runSettlement();
    expect(summary.refunded).toBe(1);
    const row = claimRowOf('u1');
    expect(row.status).toBe('claim_failed');
    expect(row.failReason).toBe('insufficient_funds');
    const bank = bankOf('u1');
    expect(bank.confirmedCoins).toBe(600);
    expect(bank.activeClaimId).toBeNull();
  });

  test('unknown outcome → quarantined in claim_sending, never re-sent', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;
    mockCactusWallet.sendResult = { outcome: 'unknown', reason: 'RPC timeout' };

    let summary = await piggyBank.runSettlement();
    expect(summary.flagged).toBe(1);
    const row = claimRowOf('u1');
    expect(row.status).toBe('claim_sending');
    expect(row.needsReview).toBe(true);
    // Coins stay debited — refunding an ambiguous send could double-pay.
    expect(bankOf('u1').confirmedCoins).toBe(0);

    // Later passes must not touch it again.
    mockCactusWallet.sendResult = { outcome: 'sent', txId: 'tx_test_2' };
    summary = await piggyBank.runSettlement();
    expect(mockCactusWallet.sendCat).toHaveBeenCalledTimes(1);
    expect(claimRowOf('u1').status).toBe('claim_sending');
  });

  test('retriable outcome → back to pending, retried later with SAME broker claim_id', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;
    mockCactusWallet.sendResult = { outcome: 'retriable', reason: 'daily_cap_reached' };

    let summary = await piggyBank.runSettlement();
    expect(summary.deferred).toBe(1);
    const row = claimRowOf('u1');
    expect(row.status).toBe('claim_pending');
    // Coins stay debited — nothing was sent, but the claim is still live.
    expect(bankOf('u1').confirmedCoins).toBe(0);

    mockCactusWallet.sendResult = { outcome: 'sent', txId: 'tx_test_2' };
    summary = await piggyBank.runSettlement();
    expect(summary.sent).toBe(1);
    expect(mockCactusWallet.sendCat).toHaveBeenCalledTimes(2);
    // Idempotency: both attempts carried the identical claim_id.
    expect(mockCactusWallet.sendCat.mock.calls[0][0].claimId)
      .toBe(mockCactusWallet.sendCat.mock.calls[1][0].claimId);
  });

  test('broker claim_id is the ledger id sanitized to the broker charset', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;
    await piggyBank.runSettlement();
    const sent = mockCactusWallet.sendCat.mock.calls[0][0];
    expect(sent.claimId).toBe('claim_u1_1'); // from ledger doc 'claim:u1:1'
    expect(sent.claimId).toMatch(/^[A-Za-z0-9_-]{8,128}$/);
    expect(claimRowOf('u1').brokerClaimId).toBe('claim_u1_1');
  });

  test('broker not ready → send pass deferred, nothing sent', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;
    mockCactusWallet.health = { ok: false };

    const summary = await piggyBank.runSettlement();
    expect(summary.deferred).toBe(1);
    expect(mockCactusWallet.sendCat).not.toHaveBeenCalled();
    expect(claimRowOf('u1').status).toBe('claim_pending');
  });

  test('settle stamps explorer coin link from the amount-matching addition', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;
    await piggyBank.runSettlement(); // → claim_sent
    mockCactusWallet.confirmedTxs.add('tx_test_1');
    mockCactusWallet.getTransaction.mockImplementationOnce(async () => ({
      confirmed: true,
      confirmedAtHeight: 123456,
      additions: [
        { amount: 600000, parent_coin_info: '0xaa', puzzle_hash: '0xbb' },
        { amount: 999, parent_coin_info: '0xcc', puzzle_hash: '0xdd' } // change
      ]
    }));

    await piggyBank.runSettlement();
    const row = claimRowOf('u1');
    expect(row.status).toBe('settled');
    expect(row.coinId).toBe('coin_test_1');
    expect(row.explorerUrl).toBe('https://explorer.cactus-network.net/#/coin/coin_test_1');
    expect(mockCactusWallet.computeCoinId).toHaveBeenCalledWith('0xaa', '0xbb', 600000);
  });

  test('stale claim_sending (crash artifact) gets flagged, not retried', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;
    const row = claimRowOf('u1');
    stores.piggyLedger.set('claim:u1:1', {
      ...row, status: 'claim_sending', sendingAt: '2000-01-01T00:00:00.000Z'
    });
    const summary = await piggyBank.runSettlement();
    expect(summary.flagged).toBe(1);
    expect(claimRowOf('u1').needsReview).toBe(true);
    expect(mockCactusWallet.sendCat).not.toHaveBeenCalled();
  });

  test('sent but unconfirmed past timeout → flagged, kept polling, no refund', async () => {
    await setupClaim();
    mockCactusWallet.enabled = true;
    await piggyBank.runSettlement(); // → claim_sent
    stores.piggyLedger.set('claim:u1:1', {
      ...claimRowOf('u1'), sentAt: '2000-01-01T00:00:00.000Z'
    });
    const summary = await piggyBank.runSettlement();
    expect(summary.flagged).toBe(1);
    const row = claimRowOf('u1');
    expect(row.status).toBe('claim_sent');
    expect(row.needsReview).toBe(true);
    expect(bankOf('u1').confirmedCoins).toBe(0); // no refund
  });
});

describe('resolveClaim (T8)', () => {
  const quarantine = async () => {
    seedBank('u1', { confirmedCoins: 600, walletAddress: 'cac1qtest' });
    await piggyBank.claim('u1');
    stores.piggyLedger.set('claim:u1:1', {
      ...claimRowOf('u1'), status: 'claim_sending', needsReview: true
    });
  };

  test('resolution failed → refund', async () => {
    await quarantine();
    const res = await piggyBank.resolveClaim({ claimId: 'claim:u1:1', resolution: 'failed' });
    expect(res.ok).toBe(true);
    expect(claimRowOf('u1').status).toBe('claim_failed');
    expect(bankOf('u1').confirmedCoins).toBe(600);
    expect(bankOf('u1').activeClaimId).toBeNull();
  });

  test('resolution sent requires txId, then settles via polling', async () => {
    await quarantine();
    expect((await piggyBank.resolveClaim({ claimId: 'claim:u1:1', resolution: 'sent' })).code)
      .toBe('tx_id_required');
    const res = await piggyBank.resolveClaim({
      claimId: 'claim:u1:1', resolution: 'sent', txId: 'tx_manual'
    });
    expect(res.ok).toBe(true);
    expect(claimRowOf('u1').status).toBe('claim_sent');

    mockCactusWallet.enabled = true;
    mockCactusWallet.confirmedTxs.add('tx_manual');
    await piggyBank.runSettlement();
    expect(claimRowOf('u1').status).toBe('settled');
    expect(bankOf('u1').settledOnChain).toBe(600);
  });

  test('settled claims are not resolvable', async () => {
    stores.piggyLedger.set('claim:u1:1', {
      userId: 'u1', eventType: 'claim', status: 'settled', coins: 500
    });
    const res = await piggyBank.resolveClaim({ claimId: 'claim:u1:1', resolution: 'failed' });
    expect(res.code).toBe('not_resolvable_from_settled');
  });
});

describe('reconcile with claim rows', () => {
  test('claims subtract from confirmed; settled adds to on-chain', async () => {
    stores.piggyLedger.set('e1', { userId: 'u1', eventType: 'add_place', coins: 400, status: 'confirmed' });
    stores.piggyLedger.set('e2', { userId: 'u1', eventType: 'add_place', coins: 200, status: 'confirmed' });
    stores.piggyLedger.set('claim:u1:1', { userId: 'u1', eventType: 'claim', coins: 500, status: 'settled' });
    stores.piggyLedger.set('claim:u1:2', { userId: 'u1', eventType: 'claim', coins: 90, status: 'claim_failed' });
    seedBank('u1', { pendingCoins: 0, confirmedCoins: 100, lifetimeCoins: 600, settledOnChain: 500 });

    const { drift, computed } = await piggyBank.reconcile('u1');
    expect(drift).toBe(false);
    expect(computed).toEqual({
      pendingCoins: 0, confirmedCoins: 100, lifetimeCoins: 600, settledOnChain: 500
    });
  });

  test('in-flight claim holds coins out of confirmed', async () => {
    stores.piggyLedger.set('e1', { userId: 'u1', eventType: 'add_place', coins: 600, status: 'confirmed' });
    stores.piggyLedger.set('claim:u1:1', { userId: 'u1', eventType: 'claim', coins: 600, status: 'claim_sent' });
    const { computed } = await piggyBank.reconcile('u1');
    expect(computed.confirmedCoins).toBe(0);
    expect(computed.settledOnChain).toBe(0);
  });
});
