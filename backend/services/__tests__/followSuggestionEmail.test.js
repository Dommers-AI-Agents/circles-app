jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../../models/FirestoreModels', () => ({ COLLECTIONS: { USERS: 'users' } }));
jest.mock('../suggestionEngine', () => ({ buildIndexes: jest.fn(), suggestFor: jest.fn() }));
jest.mock('../emailService', () => ({ sendEmail: jest.fn() }));

process.env.JWT_SECRET = 'test-secret';
const service = require('../followSuggestionEmailService');

const now = new Date('2026-09-16T12:00:00Z');
const daysAgo = (n) => new Date(now.getTime() - n * 86400000).toISOString();
const user = (overrides) => ({
  id: 'u1', email: 'a@example.com', displayName: 'Ana Lopez', following: [], createdAt: daysAgo(3), ...overrides
});

describe('selectCandidates', () => {
  test('new accounts following fewer than three people with a usable email', () => {
    const { selected, skipped } = service.selectCandidates([
      user({ id: 'a' }),
      user({ id: 'b', following: ['x', 'y'] }),
      user({ id: 'c', following: ['x', 'y', 'z'] }),                       // enough
      user({ id: 'd', email: 'x@privaterelay.appleid.com' }),              // relay
      user({ id: 'e', email: '' }),                                        // none
      user({ id: 'f', createdAt: daysAgo(90) }),                           // old
      user({ id: 'g', emailPreferences: { followSuggestions: false } }),   // unsubscribed
      user({ id: 'h', followSuggestionEmail: { lastSentAt: daysAgo(2) } }), // sent this week
      user({ id: 'i', followSuggestionEmail: { lastSentAt: daysAgo(8) } }), // sent last week: ok
      user({ id: 'j', email: 'AppReview@favcircles.com' })                  // App Review demo account
    ], { now });
    expect(selected.map((u) => u.id)).toEqual(['a', 'b', 'i']);
    expect(selected[1].followingCount).toBe(2);
    expect(skipped).toEqual({ following_enough: 1, no_usable_email: 2, internal: 1, too_old: 1, opted_out: 1, sent_recently: 1 });
  });

  test('falls back to followingCount when the array is missing, and honours the age setting', () => {
    const { selected } = service.selectCandidates([user({ following: undefined, followingCount: 2, createdAt: daysAgo(100) })], { now, maxAgeDays: 120 });
    expect(selected).toHaveLength(1);
    expect(service.selectCandidates([user({ following: undefined, followingCount: 3 })], { now }).selected).toHaveLength(0);
  });
});

describe('presentable', () => {
  test('drops rows with no real name to show', () => {
    expect(service.presentable({ displayName: 'Dani Rivera' })).toBe(true);
    expect(service.presentable({ displayName: 'wesley@favcircles.com' })).toBe(false);
    expect(service.presentable({ displayName: '' })).toBe(false);
    expect(service.presentable({ displayName: 'Someone' })).toBe(false);
  });
});

describe('unsubscribe tokens', () => {
  test('round-trip and tamper resistance', () => {
    const token = service.unsubscribeToken('u1');
    expect(service.verifyUnsubscribeToken('u1', 'followSuggestions', token)).toBe(true);
    expect(service.verifyUnsubscribeToken('u2', 'followSuggestions', token)).toBe(false);
    expect(service.verifyUnsubscribeToken('u1', 'weeklyMapDigest', token)).toBe(false);
    expect(service.verifyUnsubscribeToken('u1', 'followSuggestions', token.slice(0, -1) + '0')).toBe(false);
    expect(service.unsubscribeUrl('u1')).toContain('/api/email/unsubscribe?uid=u1&kind=followSuggestions&sig=');
  });
});

describe('buildEmail', () => {
  const suggestions = [
    { userId: 'p1', displayName: 'Dani Rivera', reason: 'Also saved Café Mogador + 5 more', placesCount: 12, profilePicture: null },
    { userId: 'p2', displayName: 'Sam <Ok>', reason: 'Saves coffee & bars in Belmar', placesCount: 1, profilePicture: 'https://x/p.jpg' }
  ];

  test('names every person with the engine reason, links each profile, and carries the unsubscribe link', () => {
    const email = service.buildEmail({ user: user({ followingCount: 1 }), suggestions });
    expect(email.subject).toBe('2 people near you on FavCircles');
    expect(email.html).toContain('Hi Ana,');
    expect(email.html).toContain("You're following 1 person so far");
    expect(email.html).toContain('Dani Rivera');
    expect(email.html).toContain('Also saved Café Mogador + 5 more · 12 places');
    expect(email.html).toContain('Sam &lt;Ok&gt;');                       // escaped
    expect(email.html).toContain('https://api.favcircles.com/user/p1');
    expect(email.html).toContain('https://api.favcircles.com/user/p2');
    expect(email.html).toContain('/api/email/unsubscribe?uid=u1&kind=followSuggestions&sig=');
    expect(email.text).toContain('• Dani Rivera — Also saved Café Mogador + 5 more');
    expect(email.text).toContain("Don't want these emails?");
  });

  test('subject and greeting for a single suggestion and no name', () => {
    const email = service.buildEmail({ user: user({ displayName: '', followingCount: 0 }), suggestions: suggestions.slice(0, 1) });
    expect(email.subject).toBe('Someone near you is on FavCircles');
    expect(email.html).toContain('Hi there,');
    expect(email.html).toContain("You're not following anyone yet");
  });
});
