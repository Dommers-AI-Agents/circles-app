jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const scoringService = require('../scoringService');

const me = 'viewer';
const them = 'friend';
const hoursAgo = (h) => new Date(Date.now() - h * 60 * 60 * 1000).toISOString();
const score = (connection) => scoringService.calculateConnectionScore(connection, me);

describe('calculateConnectionScore counts what the other person did', () => {
  test('the viewer\'s own fanned-out activity earns nothing', () => {
    const mine = { type: 'place', actorId: me, createdAt: hoursAgo(2), viewedBy: [me] };
    const s = score({ recentActivity: [mine], viewCount: 1047, lastViewedAt: hoursAgo(1) });
    expect(s.components).toEqual({ messages: 0, engagement: 0, content: 0, recency: 0, total: 0 });
    expect(s.score).toBe(0);
  });

  test('their unviewed place this morning scores content and recency, then multiplies', () => {
    const theirs = { type: 'place', actorId: them, createdAt: hoursAgo(2), viewedBy: [them] };
    const s = score({ recentActivity: [theirs] });
    expect(s.components.content).toBe(25);
    expect(s.components.recency).toBe(20);
    expect(s.multiplier).toBe(2.5);
    expect(Math.floor(s.score)).toBe(Math.round(45 * 2.5));
  });

  test('a legacy entry without actorId resolves its creator from viewedBy', () => {
    const legacyMine = { type: 'place', createdAt: hoursAgo(2), viewedBy: [me] };
    const legacyTheirs = { type: 'place', createdAt: hoursAgo(2), viewedBy: [them, me] };
    expect(score({ recentActivity: [legacyMine] }).score).toBe(0);
    const s = score({ recentActivity: [legacyTheirs] });
    expect(s.components.content).toBe(0); // already seen by the viewer
    expect(s.components.recency).toBe(20); // but it is still their recent activity
  });

  test('view counts and lastViewedAt never move the score', () => {
    const base = score({ totalPlaces: 12 });
    const viewed = score({ totalPlaces: 12, viewCount: 500, lastViewedAt: hoursAgo(1) });
    expect(viewed.score).toBe(base.score);
    expect(viewed.components.engagement).toBe(0);
  });

  test('real place counts and a place this week score without any activity entry', () => {
    const s = score({ totalPlaces: 12, hasRecentPlace: true });
    expect(s.components.content).toBe(8);
    expect(s.components.recency).toBe(7);
  });

  test('messages stay mutual signal', () => {
    const s = score({ lastMessageAt: hoursAgo(3) });
    expect(s.components.messages).toBe(25);
    expect(s.components.recency).toBe(20);
  });
});
