#!/usr/bin/env node

/**
 * Phase 4 (Part A) — security verification against the DEPLOYED server.
 *
 *   node scripts/phase4-security-test.cjs
 *
 * Checks (MCP_HANDOFF.md Phase 4):
 *   1. Cross-user isolation — a synthetic test user's token cannot see, read,
 *      or write to another user's PRIVATE circle.
 *   2. Foreign-audience token is rejected with 401 (RFC 8707).
 *   3. HTTPS-only — plain http:// is redirected, never served.
 *
 * Creates a synthetic Firestore user + a private circle for the real dev
 * account, and deletes both afterwards (cleanup runs even on failure).
 */

const path = require('path');
const { createRequire } = require('module');

const backendDir = path.join(__dirname, '../../../backend');
const backendRequire = createRequire(path.join(backendDir, 'scripts/_resolver.js'));
backendRequire('dotenv').config({ path: path.join(backendDir, '.env') });

const { initializeApp, cert } = backendRequire('firebase-admin/app');
const { getFirestore } = backendRequire('firebase-admin/firestore');
const jwt = backendRequire('jsonwebtoken');

const MCP_URL = process.env.MCP_URL || 'https://mcp.favcircles.com/mcp';
const AUD = 'favcircles-mcp';
const SECRET = process.env.JWT_SECRET;
const OWNER_EMAIL = 'sgroiwes@gmail.com';
const TEST_UID = 'mcp-phase4-isolation-test';
const TEST_EMAIL = 'mcp-phase4-test@favcircles.com';

let failures = 0;
function check(label, condition, detail) {
  if (condition) console.log(`  PASS  ${label}`);
  else { failures++; console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}

// ---- minimal Streamable HTTP MCP client ----
async function mcpCall(token, toolName, args) {
  const headers = {
    'Content-Type': 'application/json',
    Accept: 'application/json, text/event-stream',
    Authorization: `Bearer ${token}`,
  };
  const post = async (body, extra = {}) => {
    const res = await fetch(MCP_URL, { method: 'POST', headers: { ...headers, ...extra }, body: JSON.stringify(body) });
    const sid = res.headers.get('mcp-session-id');
    const text = await res.text();
    let message = null;
    if ((res.headers.get('content-type') || '').includes('event-stream')) {
      for (const line of text.split('\n')) if (line.startsWith('data:')) { try { message = JSON.parse(line.slice(5)); } catch {} }
    } else if (text) { try { message = JSON.parse(text); } catch {} }
    return { status: res.status, message, sid };
  };
  const init = await post({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'p4', version: '0' } } });
  if (init.status !== 200) return { status: init.status, text: null };
  const sess = init.sid ? { 'Mcp-Session-Id': init.sid } : {};
  await post({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} }, sess);
  const call = await post({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: toolName, arguments: args } }, sess);
  return {
    status: call.status,
    isError: !!call.message?.result?.isError,
    text: call.message?.result?.content?.[0]?.text || '',
  };
}

async function main() {
  if (!SECRET) throw new Error('JWT_SECRET missing');

  const serviceAccount = require(path.join(backendDir, 'config/firebase-service-account.json'));
  initializeApp({ credential: cert(serviceAccount), projectId: 'circles-app-83b67' });
  const db = getFirestore();

  // tokens
  const owners = await db.collection('users').where('email', '==', OWNER_EMAIL).limit(1).get();
  const ownerUid = owners.docs[0].id;
  const tokenA = jwt.sign({ uid: ownerUid, email: OWNER_EMAIL, aud: AUD }, SECRET, { expiresIn: '15m' });
  const tokenB = jwt.sign({ uid: TEST_UID, email: TEST_EMAIL, aud: AUD }, SECRET, { expiresIn: '15m' });
  const tokenForeignAud = jwt.sign({ uid: ownerUid, email: OWNER_EMAIL, aud: 'some-other-service' }, SECRET, { expiresIn: '15m' });

  let privateCircleId = null;
  try {
    // synthetic user B
    await db.collection('users').doc(TEST_UID).set({
      email: TEST_EMAIL, displayName: 'MCP Isolation Test', createdAt: new Date().toISOString(),
    });

    console.log('setup: user A creates a PRIVATE circle with one place');
    const created = await mcpCall(tokenA, 'create_circle', {
      name: 'Phase4 Isolation Secret', description: 'private data for isolation test', privacy: 'private',
    });
    privateCircleId = (created.text.match(/id: ([A-Za-z0-9]+)/) || [])[1];
    if (!privateCircleId) throw new Error(`could not create private circle: ${created.text}`);
    await mcpCall(tokenA, 'add_place', {
      circleId: privateCircleId, name: 'Secret Speakeasy', address: '1 Hidden Ln', category: 'bar',
      latitude: 40.18, longitude: -74.02,
    });

    console.log('\n1. cross-user isolation (user B = synthetic test user)');
    const bList = await mcpCall(tokenB, 'list_circles', {});
    check("B's list_circles omits A's private circle", !bList.text.includes(privateCircleId) && !bList.text.includes('Phase4 Isolation Secret'), bList.text.slice(0, 150));

    const bGet = await mcpCall(tokenB, 'get_circle', { circleId: privateCircleId });
    check("B cannot read A's private circle", bGet.isError, bGet.text.slice(0, 150));

    const bAdd = await mcpCall(tokenB, 'add_place', {
      circleId: privateCircleId, name: 'Intruder Cafe', address: '2 Nope St', category: 'cafe',
      latitude: 40.18, longitude: -74.02,
    });
    check("B cannot add places to A's circle", bAdd.isError, bAdd.text.slice(0, 150));

    const bSearch = await mcpCall(tokenB, 'search_places', { query: 'Secret Speakeasy' });
    check("B's search cannot see A's private place", !bSearch.text.includes('Secret Speakeasy'), bSearch.text.slice(0, 150));

    const bUpdate = await mcpCall(tokenB, 'update_circle', { circleId: privateCircleId, name: 'Hacked' });
    check("B cannot edit A's circle", bUpdate.isError, bUpdate.text.slice(0, 150));

    const bDelete = await mcpCall(tokenB, 'delete_circle', { circleId: privateCircleId, confirm: true });
    check("B cannot delete A's circle (even with confirm)", bDelete.isError, bDelete.text.slice(0, 150));

    // sanity: A CAN see everything (proves the denials above are authz, not breakage)
    const aGet = await mcpCall(tokenA, 'get_circle', { circleId: privateCircleId });
    check('sanity: A reads own private circle fine', !aGet.isError && aGet.text.includes('Secret Speakeasy'), aGet.text.slice(0, 150));

    console.log('\n2. foreign-audience token (RFC 8707)');
    const foreign = await mcpCall(tokenForeignAud, 'list_circles', {});
    check('foreign-aud token rejected with 401', foreign.status === 401, `got ${foreign.status}`);

    console.log('\n3. HTTPS-only');
    const plain = await fetch('http://mcp.favcircles.com/health', { redirect: 'manual' }).catch(() => null);
    const redirected = plain && plain.status >= 301 && plain.status <= 308 && (plain.headers.get('location') || '').startsWith('https://');
    check('http:// redirects to https (never served plain)', !!redirected, plain ? `status ${plain.status}` : 'no response');
  } finally {
    console.log('\ncleanup');
    if (privateCircleId) {
      const del = await fetch(`https://api.favcircles.com/api/circles/${privateCircleId}`, {
        method: 'DELETE', headers: { Authorization: `Bearer ${tokenA}` },
      });
      console.log(`  test circle deleted: HTTP ${del.status}`);
    }
    await db.collection('users').doc(TEST_UID).delete();
    console.log('  synthetic user deleted');
  }

  console.log(failures === 0 ? '\nPHASE 4 SECURITY TESTS PASSED' : `\nPHASE 4 SECURITY TESTS FAILED (${failures})`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => { console.error('phase4 test error:', e.message); process.exit(1); });
