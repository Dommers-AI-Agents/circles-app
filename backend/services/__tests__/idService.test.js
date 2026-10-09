const { isSameUser, normalizeUserId } = require('../idService');

describe('isSameUser — one plain key per person', () => {
  test('equal ids match', () => {
    expect(isSameUser('111819744557116370195', '111819744557116370195')).toBe(true);
  });
  test('different ids do not', () => {
    expect(isSameUser('28ae89b4c9a54694b8ba24fa4d526bef', '114660021593746618908')).toBe(false);
    expect(isSameUser('000454.9b5eeac93282416c9bc6dcecbc49b40f.2127', '9b5eeac93282416c9bc6dcecbc49b40f')).toBe(false);
  });
  test('missing never matches', () => {
    expect(isSameUser(null, null)).toBe(false);
    expect(isSameUser('', '')).toBe(false);
    expect(isSameUser('a', undefined)).toBe(false);
  });
  test('sign-in still translates an old dotted Apple id', () => {
    expect(normalizeUserId('000454.9b5eeac93282416c9bc6dcecbc49b40f.2127')).toBe('9b5eeac93282416c9bc6dcecbc49b40f');
  });
});
