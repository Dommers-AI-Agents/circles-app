// Profile names after signup (security audit 2026-10-01): real names in any
// script keep saving; links, markup and control/bidi characters don't.
const { displayNameProblem, validateProfileUpdate } = require('../validation');

test('real names pass, including non-ASCII and punctuation', () => {
  for (const name of ['Wes', 'José Núñez', 'Brittany S.', "Seán O'Brien", '李小龙', 'Dr. Smith', 'Knight ATV']) {
    expect(displayNameProblem(name)).toBeNull();
  }
});

test('links, markup, control characters and bad lengths are refused', () => {
  expect(displayNameProblem('Visit https://spam.example')).toMatch(/link/);
  expect(displayNameProblem('www.cheap-pills')).toMatch(/link/);
  expect(displayNameProblem('free-coins.xyz')).toMatch(/link/);
  expect(displayNameProblem('<a href=x>Wes</a>')).toMatch(/< or >/);
  expect(displayNameProblem('Wes\nBcc: x')).toMatch(/aren't allowed/);
  expect(displayNameProblem('Wes‮moc.lapyap')).toMatch(/aren't allowed/);
  expect(displayNameProblem('   ')).toMatch(/empty/);
  expect(displayNameProblem('x'.repeat(51))).toMatch(/50/);
  expect(displayNameProblem(12)).toMatch(/text/);
  // Optional fields may be cleared
  expect(displayNameProblem('', { field: 'Last name', required: false })).toBeNull();
});

// Runs the express-validator chain the routes use.
async function run(body) {
  const req = { body, path: '/me' };
  const res = { statusCode: 200, payload: null };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (payload) => { res.payload = payload; return res; };
  let passed = false;
  for (const mw of validateProfileUpdate) {
    let nextCalled = false;
    await mw(req, res, () => { nextCalled = true; });
    if (!nextCalled) return { passed, res, req };
  }
  passed = true;
  return { passed, res, req };
}

test('middleware: absent fields pass, names are trimmed, bad names get a 400', async () => {
  expect((await run({ bio: 'hi' })).passed).toBe(true);

  const ok = await run({ displayName: '  Wes  ', lastName: '' });
  expect(ok.passed).toBe(true);
  expect(ok.req.body.displayName).toBe('Wes');

  const bad = await run({ displayName: 'Click http://x.co' });
  expect(bad.passed).toBe(false);
  expect(bad.res.statusCode).toBe(400);
  expect(bad.res.payload.message).toMatch(/displayName/);
});
