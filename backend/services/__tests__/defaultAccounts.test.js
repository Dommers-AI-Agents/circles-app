jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const { chosenFollowCount } = require('../defaultAccounts');
const { selectCandidates } = require('../followSuggestionEmailService');

test('the default follows (Wes, Brittany) never count as people they chose', () => {
  const defaults = new Set(['wes', 'brit']);
  expect(chosenFollowCount(['wes', 'brit'], defaults)).toBe(0);
  expect(chosenFollowCount(['wes', 'brit', 'amy'], defaults)).toBe(1);
  expect(chosenFollowCount(undefined, defaults)).toBe(0);
});

test('one real follow no longer switches the people-you-may-know email off', () => {
  const now = new Date('2026-10-09T12:00:00Z');
  const user = { id: 'u', email: 'u@example.com', createdAt: '2026-10-05T12:00:00Z', following: ['wes', 'brit', 'amy'] };
  expect(selectCandidates([user], { now }).selected).toHaveLength(0);
  expect(selectCandidates([user], { now, defaultIds: new Set(['wes', 'brit']) }).selected).toHaveLength(1);
});
