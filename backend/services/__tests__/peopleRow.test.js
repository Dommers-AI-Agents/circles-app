// The people row: one scale for connections and followed users, driven by
// what each person did lately. A brand account with many places and no
// activity ranks below anyone who did something this month.
const { scorePerson, RECENT_DAYS } = require('../peopleRowScore');
const { peopleRowStats } = require('../peopleRowStats');
const { rankRelationships } = require('../relationshipRanking');

const now = Date.parse('2026-09-25T12:00:00Z');
const day = 24 * 60 * 60 * 1000;
const ago = (days) => new Date(now - days * day);

describe('scorePerson', () => {
  test('places alone earn nothing but a hair of tie-break; activity earns the points', () => {
    const brand = scorePerson({ lastActivityAt: ago(60), totalPlaces: 20 }, now);
    const quiet = scorePerson({ totalPlaces: 144 }, now);
    const active = scorePerson({ lastActivityAt: ago(5), totalPlaces: 2 }, now);
    expect(brand.components.recency).toBe(0);
    expect(brand.score).toBeLessThan(1);
    expect(quiet.score).toBeLessThan(1);
    expect(quiet.score).toBeGreaterThan(brand.score); // more to look at, among the quiet
    expect(active.score).toBeGreaterThan(brand.score + 10);
    expect(active.hasRecentActivity).toBe(true);
    expect(brand.hasRecentActivity).toBe(false);
  });

  test('recency slides: more recent always scores higher, a month of silence is worth nothing', () => {
    expect(scorePerson({ lastActivityAt: ago(0) }, now).components.recency).toBe(40);
    expect(scorePerson({ lastActivityAt: ago(5) }, now).components.recency).toBe(34);
    expect(scorePerson({ lastActivityAt: ago(30) }, now).components.recency).toBe(4);
    expect(scorePerson({ lastActivityAt: ago(31) }, now).components.recency).toBe(0);
    // Sep 12 beats Sep 7 whatever the place counts (the band Knight ATV sat in).
    const sep12 = scorePerson({ lastActivityAt: ago(13), totalPlaces: 2 }, now).score;
    const sep7 = scorePerson({ lastActivityAt: ago(18), totalPlaces: 20 }, now).score;
    expect(sep12).toBeGreaterThan(sep7);
    expect(scorePerson({ lastActivityAt: 'not a date' }, now).components.recency).toBe(0);
    expect(scorePerson({ lastActivityAt: ago(RECENT_DAYS + 0.1) }, now).hasRecentActivity).toBe(false);
  });

  test('messages and unseen activity add a little; the components keep their shape', () => {
    const s = scorePerson({ lastActivityAt: ago(1), lastMessageAt: ago(2).toISOString(), hasUnviewedActivity: true, totalPlaces: 30 }, now);
    expect(s.components).toEqual({ messages: 10, engagement: 0, content: 5, recency: 38.8, total: 53.8 });
    expect(s.score).toBeCloseTo(53.83, 5);
    expect(scorePerson({ lastMessageAt: ago(20) }, now).components.messages).toBe(4);
    expect(scorePerson({}, now).components).toEqual({ messages: 0, engagement: 0, content: 0, recency: 0, total: 0 });
  });

  test('the row Wes saw: an idle brand account with 20 places sorts under a friend who added a place five days ago', () => {
    const rows = [
      { id: 'knight', connectionScore: scorePerson({ lastActivityAt: ago(70), totalPlaces: 20 }, now).score, connectedUser: { displayName: 'Knight ATV' } },
      { id: 'brit', connectionScore: scorePerson({ lastActivityAt: ago(5), totalPlaces: 144 }, now).score, connectedUser: { displayName: 'Brittany R' } },
      { id: 'sal', connectionScore: scorePerson({ lastActivityAt: ago(1), totalPlaces: 89 }, now).score, connectedUser: { displayName: 'Salvatore A Sgroi' } },
      { id: 'bill', connectionScore: scorePerson({ totalPlaces: 75 }, now).score, connectedUser: { displayName: 'Bill' } }
    ];
    expect(rankRelationships(rows).map((r) => r.id)).toEqual(['sal', 'brit', 'bill', 'knight']);
  });
});

describe('peopleRowStats', () => {
  // A fake Firestore: newest activity per actor, places per user; counts how
  // many queries overlap so the batching stays parallel.
  const fakeDb = (activityByUser, placesByUser) => {
    let inFlight = 0; let peak = 0;
    const settle = (value) => new Promise((resolve) => {
      inFlight += 1; peak = Math.max(peak, inFlight);
      setTimeout(() => { inFlight -= 1; resolve(value); }, 3);
    });
    const collection = (name) => ({
      where: (field, op, userId) => {
        const q = {
          orderBy: () => q, limit: () => q,
          get: () => {
            const at = activityByUser[userId];
            return settle(at ? { empty: false, docs: [{ data: () => ({ actorId: userId, timestamp: { toDate: () => at } }) }] } : { empty: true, docs: [] });
          },
          count: () => ({ get: () => settle({ data: () => ({ count: placesByUser[userId] || 0 }) }) })
        };
        return q;
      }
    });
    return { peak: () => peak, collection };
  };

  test('reads each person\'s newest activity and place count, and flags this week', async () => {
    const db = fakeDb({ active: ago(2), old: ago(40) }, { active: 3, old: 20, nobody: 0 });
    const stats = await peopleRowStats(db, ['active', 'old', 'nobody'], now);
    expect(stats.get('active')).toEqual({ lastActivityAt: ago(2), totalPlaces: 3, hasRecentPlace: true });
    expect(stats.get('old')).toEqual({ lastActivityAt: ago(40), totalPlaces: 20, hasRecentPlace: false });
    expect(stats.get('nobody')).toEqual({ lastActivityAt: null, totalPlaces: 0, hasRecentPlace: false });
  });

  test('runs a batch of users at once', async () => {
    const ids = Array.from({ length: 90 }, (_, i) => `u${i}`);
    const db = fakeDb({}, {});
    await peopleRowStats(db, ids, now);
    expect(db.peak()).toBeGreaterThanOrEqual(80);
  });
});
