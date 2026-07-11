#!/usr/bin/env node

/**
 * Phase 2 auth test suite — exercises verifyToken() (dist/auth.js) directly:
 *   1. valid token (correct secret + aud)      -> accepted, uid extracted
 *   2. missing aud claim                        -> rejected (RFC 8707)
 *   3. foreign aud                              -> rejected
 *   4. expired token                            -> rejected
 *   5. wrong signing secret                     -> rejected
 *   6. garbage string                           -> rejected
 *   7. missing token                            -> rejected
 *
 * Signs test tokens locally with the real JWT_SECRET from backend/.env
 * (nothing is printed, nothing leaves the process).
 */

const path = require('path');
const { createRequire } = require('module');

const backendDir = path.join(__dirname, '../../backend');
const backendRequire = createRequire(path.join(backendDir, 'scripts/_resolver.js'));
backendRequire('dotenv').config({ path: path.join(backendDir, '.env') });
const jwt = backendRequire('jsonwebtoken');

const SECRET = process.env.JWT_SECRET;
if (!SECRET) { console.error('JWT_SECRET missing from backend/.env'); process.exit(1); }

const AUD = 'favcircles-mcp';
const claims = { uid: 'test-user-123', email: 'test@example.com' };

let failures = 0;
function check(label, condition, detail) {
  if (condition) console.log(`  PASS  ${label}`);
  else { failures++; console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}

async function expectReject(verifyToken, label, token, messageFragment) {
  try {
    await verifyToken(token);
    check(label, false, 'token was accepted but should have been rejected');
  } catch (e) {
    const okType = e.name === 'AuthError';
    const okMsg = !messageFragment || e.message.toLowerCase().includes(messageFragment);
    check(label, okType && okMsg, `${e.name}: ${e.message}`);
  }
}

async function main() {
  const { verifyToken } = await import(path.join(__dirname, '../dist/auth.js'));

  console.log('1. valid token');
  const good = jwt.sign({ ...claims, aud: AUD }, SECRET, { expiresIn: '5m' });
  const auth = await verifyToken(good);
  check('accepted', !!auth);
  check('uid extracted', auth.userId === 'test-user-123', `got ${auth.userId}`);
  check('email extracted', auth.email === 'test@example.com');
  check('token passed through', auth.token === good);

  console.log('2. missing aud claim');
  await expectReject(verifyToken, 'rejected', jwt.sign(claims, SECRET, { expiresIn: '5m' }), 'aud');

  console.log('3. foreign aud');
  await expectReject(
    verifyToken, 'rejected',
    jwt.sign({ ...claims, aud: 'some-other-service' }, SECRET, { expiresIn: '5m' }), 'aud'
  );

  console.log('4. expired token');
  await expectReject(
    verifyToken, 'rejected',
    jwt.sign({ ...claims, aud: AUD }, SECRET, { expiresIn: '-10s' }), 'expired'
  );

  console.log('5. wrong signing secret');
  await expectReject(
    verifyToken, 'rejected',
    jwt.sign({ ...claims, aud: AUD }, 'not-the-real-secret', { expiresIn: '5m' }), 'signature'
  );

  console.log('6. garbage token');
  await expectReject(verifyToken, 'rejected', 'not.a.jwt');

  console.log('7. missing token');
  await expectReject(verifyToken, 'rejected', undefined, 'no bearer token');

  console.log(failures === 0 ? '\nAUTH TESTS PASSED' : `\nAUTH TESTS FAILED (${failures} failures)`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => { console.error('auth test error:', e); process.exit(1); });
