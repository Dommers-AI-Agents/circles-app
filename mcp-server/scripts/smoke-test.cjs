#!/usr/bin/env node

/**
 * Scripted stdio smoke test for the FavCircles MCP server.
 *
 * Spawns `node dist/server.js`, speaks JSON-RPC over stdio:
 *   initialize -> tools/list -> tools/call list_circles -> tools/call search_places
 * and asserts the responses. Requires FAVCIRCLES_TOKEN in the environment
 * (or pass via: FAVCIRCLES_TOKEN=$(node scripts/mint-token.cjs) npm run smoke).
 */

const { spawn } = require('child_process');
const path = require('path');

const serverPath = path.join(__dirname, '../dist/server.js');
const child = spawn('node', [serverPath], {
  env: process.env,
  stdio: ['pipe', 'pipe', 'inherit']
});

let nextId = 1;
const pending = new Map();
let buffer = '';

child.stdout.on('data', (chunk) => {
  buffer += chunk.toString();
  let idx;
  while ((idx = buffer.indexOf('\n')) !== -1) {
    const line = buffer.slice(0, idx).trim();
    buffer = buffer.slice(idx + 1);
    if (!line) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    if (msg.id != null && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  }
});

function rpc(method, params) {
  const id = nextId++;
  const msg = { jsonrpc: '2.0', id, method, params };
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`timeout waiting for ${method}`)), 30000);
    pending.set(id, (response) => { clearTimeout(timer); resolve(response); });
    child.stdin.write(JSON.stringify(msg) + '\n');
  });
}

function notify(method, params) {
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method, params }) + '\n');
}

let failures = 0;
function check(label, condition, detail) {
  if (condition) {
    console.log(`  PASS  ${label}`);
  } else {
    failures++;
    console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

async function main() {
  if (!process.env.FAVCIRCLES_TOKEN) {
    console.error('FAVCIRCLES_TOKEN not set. Run: FAVCIRCLES_TOKEN=$(node scripts/mint-token.cjs) npm run smoke');
    process.exit(1);
  }

  console.log('1. initialize');
  const init = await rpc('initialize', {
    protocolVersion: '2025-06-18',
    capabilities: {},
    clientInfo: { name: 'smoke-test', version: '0.0.1' }
  });
  check('server responds to initialize', !!init.result?.serverInfo, JSON.stringify(init.error));
  check('server name is favcircles', init.result?.serverInfo?.name === 'favcircles');
  notify('notifications/initialized', {});

  console.log('2. tools/list');
  const list = await rpc('tools/list', {});
  const tools = list.result?.tools || [];
  const names = tools.map((t) => t.name).sort();
  check('14 tools registered', tools.length === 14, `got: ${names.join(', ')}`);
  for (const expected of ['add_place', 'create_circle', 'delete_circle', 'delete_place', 'get_circle', 'list_circles', 'list_trash', 'permanently_delete_circle', 'permanently_delete_place', 'restore_circle', 'restore_place', 'search_places', 'update_circle', 'update_place']) {
    check(`tool present: ${expected}`, names.includes(expected));
  }

  console.log('3. tools/call list_circles (live backend)');
  const circles = await rpc('tools/call', { name: 'list_circles', arguments: {} });
  const circlesText = circles.result?.content?.[0]?.text || '';
  check('list_circles returned text', circlesText.length > 0, JSON.stringify(circles.error));
  check('list_circles not an error', !circles.result?.isError, circlesText.slice(0, 200));
  check('response mentions circle ids', /\(id: /.test(circlesText), circlesText.slice(0, 200));
  console.log('     preview: ' + circlesText.split('\n').slice(0, 3).join(' | '));

  console.log('4. tools/call search_places (live backend)');
  const search = await rpc('tools/call', { name: 'search_places', arguments: { query: 'a' } });
  const searchText = search.result?.content?.[0]?.text || '';
  check('search_places returned text', searchText.length > 0, JSON.stringify(search.error));
  check('search_places not an error', !search.result?.isError, searchText.slice(0, 200));
  console.log('     preview: ' + searchText.split('\n')[0]);

  console.log(failures === 0 ? '\nSMOKE TEST PASSED' : `\nSMOKE TEST FAILED (${failures} failures)`);
  child.kill();
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error('Smoke test error:', err.message);
  child.kill();
  process.exit(1);
});
