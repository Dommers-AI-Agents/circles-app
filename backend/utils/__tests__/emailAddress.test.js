// One recipient per address field (security audit 2026-10-01): lists,
// header-injection newlines and display-name forms are all refused.
const { isValidEmailAddress, normalizeEmail } = require('../emailAddress');

test('accepts ordinary single addresses', () => {
  for (const ok of ['wes@favcircles.com', 'First.Last+tag@sub.example.co.uk', '  Mixed@Case.COM  ']) {
    expect(isValidEmailAddress(ok)).toBe(true);
  }
  expect(normalizeEmail('  Mixed@Case.COM ')).toBe('mixed@case.com');
});

test('refuses lists, newlines, display names and junk', () => {
  for (const bad of [
    'a@x.com,b@y.com',
    'a@x.com; b@y.com',
    'a@x.com b@y.com',
    'a@x.com\nBcc: c@z.com',
    'a,b@x.com',
    'Wes <wes@x.com>',
    '"wes"@x.com',
    'no-at-sign',
    'a@b',
    'a@b.c',
    '',
    null,
    42,
    `${'a'.repeat(250)}@x.com`
  ]) {
    expect(isValidEmailAddress(bad)).toBe(false);
  }
});
