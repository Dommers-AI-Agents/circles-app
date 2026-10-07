// Every service method a scheduled task calls must really be exported.
// The task controller tests mock their services, so a missing export (the
// reengagement job: "sendReengagementNotifications is not a function",
// broken from 2026-09-19 to 2026-10-07) never showed up in them.
const fs = require('fs');
const path = require('path');

jest.mock('../../../config/firebase', () => {
  const { FakeFieldValue } = require('../../../__fixtures__/fakeFirestore');
  const anything = new Proxy(function () {}, { get: () => anything, apply: () => anything });
  return { getFirestore: () => anything, getMessaging: () => anything, getAuth: () => anything,
           getStorage: () => anything, admin: anything, FieldValue: FakeFieldValue, initializeFirebase: () => {} };
});

const dir = path.join(__dirname, '..');
const calls = [];
for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.js'))) {
  const src = fs.readFileSync(path.join(dir, file), 'utf8');
  const services = [...src.matchAll(/const (\w+) = require\('(\.\.\/\.\.\/services\/[\w/]+)'\)/g)];
  for (const [, name, mod] of services) {
    const used = new Set([...src.matchAll(new RegExp(`\\b${name}\\.(\\w+)\\(`, 'g'))].map(m => m[1]));
    for (const method of used) calls.push([file, mod, method]);
  }
}

describe('scheduled tasks call real service exports', () => {
  test('found calls to check', () => expect(calls.length).toBeGreaterThan(5));
  test.each(calls)('%s → %s.%s', (file, mod, method) => {
    const service = require(path.join(dir, mod));
    expect(typeof service[method]).toBe('function');
  });
});
