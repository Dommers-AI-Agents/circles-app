#!/usr/bin/env node

/**
 * Phase 4 (Part B) — OAuth 2.1 authorization-server tests.
 *
 *   BASE=https://mcp.favcircles.com node scripts/oauth-flow-test.cjs
 *
 * Exercises everything that can be verified without a human logging in:
 *   1. AS metadata discovery + protected-resource metadata links the AS
 *   2. Dynamic Client Registration (RFC 7591)
 *   3. /authorize with an UNREGISTERED redirect_uri -> rejected (no login form)
 *   4. /authorize with the registered redirect_uri + PKCE -> login form served
 *   5. login POST with wrong credentials -> rejected (backend bridge works)
 *   6. /mcp with a made-up OAuth token -> 401 + WWW-Authenticate
 *   7. /token with a garbage code -> error, no token issued
 */

const crypto = require('crypto');
const BASE = (process.env.BASE || 'https://mcp.favcircles.com').replace(/\/$/, '');

let failures = 0;
function check(label, condition, detail) {
  if (condition) console.log(`  PASS  ${label}`);
  else { failures++; console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}

function b64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function main() {
  console.log(`Target: ${BASE}\n`);

  console.log('1. metadata discovery');
  const asMeta = await fetch(`${BASE}/.well-known/oauth-authorization-server`);
  const as = await asMeta.json().catch(() => ({}));
  check('AS metadata 200', asMeta.status === 200, `got ${asMeta.status}`);
  check('authorization_endpoint', (as.authorization_endpoint || '').endsWith('/authorize'), as.authorization_endpoint);
  check('token_endpoint', (as.token_endpoint || '').endsWith('/token'), as.token_endpoint);
  check('registration_endpoint', (as.registration_endpoint || '').endsWith('/register'), as.registration_endpoint);
  check('PKCE S256 supported', (as.code_challenge_methods_supported || []).includes('S256'));
  const prMeta = await (await fetch(`${BASE}/.well-known/oauth-protected-resource`)).json();
  check('protected-resource lists the AS', (prMeta.authorization_servers || []).includes(BASE), JSON.stringify(prMeta.authorization_servers));

  console.log('2. dynamic client registration');
  const goodRedirect = 'http://localhost:19191/callback';
  const reg = await fetch(`${BASE}/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_name: 'phase4-flow-test',
      redirect_uris: [goodRedirect],
      token_endpoint_auth_method: 'none',
      grant_types: ['authorization_code'],
      response_types: ['code'],
    }),
  });
  const client = await reg.json().catch(() => ({}));
  check('registered (201/200)', reg.status === 201 || reg.status === 200, `got ${reg.status}: ${JSON.stringify(client).slice(0, 150)}`);
  check('client_id issued', typeof client.client_id === 'string', JSON.stringify(client).slice(0, 150));

  const verifier = b64url(crypto.randomBytes(32));
  const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
  const authParams = (redirectUri) =>
    new URLSearchParams({
      response_type: 'code',
      client_id: client.client_id,
      redirect_uri: redirectUri,
      scope: '',
      state: 'xyz',
      code_challenge: challenge,
      code_challenge_method: 'S256',
    });

  console.log('3. authorize with UNREGISTERED redirect_uri');
  const evil = await fetch(`${BASE}/authorize?${authParams('https://evil.example.com/steal')}`, { redirect: 'manual' });
  const evilBody = await evil.text();
  const evilRejected = evil.status >= 400 || (!evilBody.includes('<form') && evil.status < 300);
  check('rejected (no login form, no redirect)', evilRejected && evil.status !== 302, `status ${evil.status}`);

  console.log('4. authorize with registered redirect_uri + PKCE');
  const good = await fetch(`${BASE}/authorize?${authParams(goodRedirect)}`);
  const goodBody = await good.text();
  check('login form served', good.status === 200 && goodBody.includes('<form') && goodBody.includes('FavCircles'), `status ${good.status}`);
  const oauthReqB64 = (goodBody.match(/name="oauthReq" value="([^"]+)"/) || [])[1];
  check('form carries oauth state', !!oauthReqB64);

  console.log('5. login bridge rejects bad credentials');
  const badLogin = await fetch(`${BASE}/authorize`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ oauthReq: oauthReqB64 || '', email: 'sgroiwes@gmail.com', password: 'definitely-wrong-password-12345' }),
    redirect: 'manual',
  });
  const badLoginBody = await badLogin.text();
  check('no redirect issued (still on login page)', badLogin.status !== 302, `status ${badLogin.status}`);
  check('error shown', badLoginBody.includes('Invalid email or password'), badLoginBody.slice(0, 120));

  console.log('6. /mcp with a fake OAuth token');
  const fake = await fetch(`${BASE}/mcp`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json, text/event-stream',
      Authorization: 'Bearer fake_oauth_token_that_was_never_issued',
    },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'x', version: '0' } } }),
  });
  check('401', fake.status === 401, `got ${fake.status}`);
  check('WWW-Authenticate present', (fake.headers.get('www-authenticate') || '').includes('resource_metadata'), fake.headers.get('www-authenticate') || '(none)');

  console.log('7. token endpoint rejects garbage code');
  const tok = await fetch(`${BASE}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code: 'garbage-code',
      redirect_uri: goodRedirect,
      client_id: client.client_id,
      code_verifier: verifier,
    }),
  });
  const tokJson = await tok.json().catch(() => ({}));
  check('error, no token', tok.status >= 400 && !tokJson.access_token, `status ${tok.status}: ${JSON.stringify(tokJson).slice(0, 120)}`);

  console.log(failures === 0 ? '\nOAUTH FLOW TESTS PASSED' : `\nOAUTH FLOW TESTS FAILED (${failures})`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => { console.error('oauth flow test error:', e.message); process.exit(1); });
