#!/usr/bin/env node

/**
 * Social sign-in OAuth E2E — proves the FULL pipeline a ChatGPT/Claude
 * connector uses, with a Google/Firebase-style credential and no password:
 *
 *   admin SDK custom token -> real Firebase ID token (identitytoolkit REST)
 *   -> DCR /register -> GET /authorize (login page has social buttons)
 *   -> POST /authorize with idToken (the social path; no email/password)
 *   -> 302 redirect with code -> POST /token (PKCE) -> access token
 *   -> POST /mcp tools/call list_circles with the OAuth token
 *
 * Also negative-checks that a garbage idToken is rejected.
 * No secrets are printed. Uses backend/.env + the Firebase service account.
 */

const path = require('path');
const crypto = require('crypto');
const { createRequire } = require('module');

const BASE = (process.env.BASE || 'https://mcp.favcircles.com').replace(/\/$/, '');
const backendDir = path.join(__dirname, '../../../backend');
const backendRequire = createRequire(path.join(backendDir, 'scripts/_resolver.js'));
backendRequire('dotenv').config({ path: path.join(backendDir, '.env') });

const { initializeApp, cert } = backendRequire('firebase-admin/app');
const { getAuth } = backendRequire('firebase-admin/auth');

let failures = 0;
function check(label, condition, detail) {
  if (condition) console.log(`  PASS  ${label}`);
  else { failures++; console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}
const b64url = (buf) => buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

async function mintFirebaseIdToken() {
  const serviceAccount = require(path.join(backendDir, 'config/firebase-service-account.json'));
  initializeApp({ credential: cert(serviceAccount), projectId: 'circles-app-83b67' });

  // Same uid the dev account's users doc uses (looked up by email).
  const { getFirestore } = backendRequire('firebase-admin/firestore');
  const users = await getFirestore().collection('users').where('email', '==', 'sgroiwes@gmail.com').limit(1).get();
  const uid = users.docs[0].id;

  const customToken = await getAuth().createCustomToken(uid);
  const apiKey = process.env.FIREBASE_API_KEY;
  if (!apiKey) throw new Error('FIREBASE_API_KEY missing from backend/.env');
  const res = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
  });
  const data = await res.json();
  if (!res.ok || !data.idToken) throw new Error(`custom-token exchange failed: ${data?.error?.message || res.status}`);
  return data.idToken; // a REAL Firebase ID token, like the Google popup returns
}

async function main() {
  console.log(`Target: ${BASE}\n`);
  const idToken = await mintFirebaseIdToken();
  console.log('0. minted real Firebase ID token for dev user (in-process)\n');

  console.log('1. register OAuth client');
  const redirectUri = 'http://localhost:19292/callback';
  const reg = await fetch(`${BASE}/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      client_name: 'social-e2e-test', redirect_uris: [redirectUri],
      token_endpoint_auth_method: 'none', grant_types: ['authorization_code'], response_types: ['code'],
    }),
  });
  const client = await reg.json();
  check('client registered', !!client.client_id, JSON.stringify(client).slice(0, 120));

  console.log('2. GET /authorize — page offers social sign-in');
  const verifier = b64url(crypto.randomBytes(32));
  const challenge = b64url(crypto.createHash('sha256').update(verifier).digest());
  const params = new URLSearchParams({
    response_type: 'code', client_id: client.client_id, redirect_uri: redirectUri,
    scope: '', state: 'st123', code_challenge: challenge, code_challenge_method: 'S256',
  });
  const page = await fetch(`${BASE}/authorize?${params}`);
  const html = await page.text();
  check('login page 200', page.status === 200, `${page.status}`);
  check('Google button present', html.includes('Continue with Google'));
  check('Facebook button present', html.includes('Continue with Facebook'));
  const oauthReq = (html.match(/name="oauthReq" value="([^"]+)"/) || [])[1];
  check('oauth state present', !!oauthReq);

  console.log('3. POST /authorize with a GARBAGE idToken -> rejected');
  const bad = await fetch(`${BASE}/authorize`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ oauthReq, idToken: 'not-a-real-token' }),
    redirect: 'manual',
  });
  check('no redirect for bad token', bad.status !== 302, `status ${bad.status}`);

  console.log('4. POST /authorize with the REAL Firebase ID token (social path)');
  const auth = await fetch(`${BASE}/authorize`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ oauthReq, idToken }),
    redirect: 'manual',
  });
  const location = auth.headers.get('location') || '';
  check('302 redirect issued', auth.status === 302, `status ${auth.status}: ${(await auth.text()).slice(0, 150)}`);
  const redirect = location ? new URL(location) : null;
  const code = redirect?.searchParams.get('code');
  check('redirects to registered redirect_uri', location.startsWith(redirectUri), location.slice(0, 100));
  check('authorization code present', !!code);
  check('state echoed', redirect?.searchParams.get('state') === 'st123');

  console.log('5. exchange code at /token (PKCE)');
  const tok = await fetch(`${BASE}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code', code, redirect_uri: redirectUri,
      client_id: client.client_id, code_verifier: verifier,
    }),
  });
  const tokens = await tok.json();
  check('access token issued', tok.status === 200 && !!tokens.access_token, JSON.stringify(tokens).slice(0, 150));

  console.log('6. call /mcp with the OAuth access token');
  let sessionId = null;
  let rpcId = 0;
  async function rpc(body) {
    const headers = {
      'Content-Type': 'application/json', Accept: 'application/json, text/event-stream',
      Authorization: `Bearer ${tokens.access_token}`,
    };
    if (sessionId) headers['Mcp-Session-Id'] = sessionId;
    const res = await fetch(`${BASE}/mcp`, { method: 'POST', headers, body: JSON.stringify(body) });
    const sid = res.headers.get('mcp-session-id');
    if (sid) sessionId = sid;
    const text = await res.text();
    let message = null;
    if ((res.headers.get('content-type') || '').includes('event-stream')) {
      for (const line of text.split('\n')) if (line.startsWith('data:')) { try { message = JSON.parse(line.slice(5)); } catch {} }
    } else if (text) { try { message = JSON.parse(text); } catch {} }
    return { status: res.status, message };
  }
  const init = await rpc({ jsonrpc: '2.0', id: ++rpcId, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'social-e2e', version: '0' } } });
  check('initialize 200 with OAuth token', init.status === 200, `${init.status}`);
  await rpc({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} });
  const call = await rpc({ jsonrpc: '2.0', id: ++rpcId, method: 'tools/call', params: { name: 'list_circles', arguments: {} } });
  const text = call.message?.result?.content?.[0]?.text || '';
  check('list_circles works', !call.message?.result?.isError && /circle/i.test(text), text.slice(0, 120));
  console.log('     preview: ' + text.split('\n')[0]);

  console.log(failures === 0 ? '\nSOCIAL OAUTH E2E PASSED' : `\nSOCIAL OAUTH E2E FAILED (${failures})`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => { console.error('social e2e error:', e.message); process.exit(1); });
