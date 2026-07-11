#!/usr/bin/env node

/**
 * Streamable HTTP smoke test for the Worker MCP server.
 *
 *   MCP_URL=http://localhost:8787/mcp FAVCIRCLES_TOKEN=... node scripts/http-smoke.cjs
 *
 * Checks:
 *   1. GET  /.well-known/oauth-protected-resource -> 200 + resource field
 *   2. POST /mcp with no token                    -> 401 + WWW-Authenticate
 *   3. POST /mcp with a bad-signature token       -> 401
 *   4. initialize                                 -> 200, serverInfo favcircles
 *   5. tools/list                                 -> 5 tools
 *   6. tools/call list_circles                    -> live circles text
 */

const MCP_URL = process.env.MCP_URL || 'http://localhost:8787/mcp';
const TOKEN = process.env.FAVCIRCLES_TOKEN;
const base = new URL(MCP_URL).origin;

let failures = 0;
function check(label, condition, detail) {
  if (condition) console.log(`  PASS  ${label}`);
  else { failures++; console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`); }
}

let sessionId = null;

/** POST a JSON-RPC message; parse either application/json or SSE response. */
async function rpc(body, { token = TOKEN } = {}) {
  const headers = {
    'Content-Type': 'application/json',
    Accept: 'application/json, text/event-stream',
  };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (sessionId) headers['Mcp-Session-Id'] = sessionId;

  const res = await fetch(MCP_URL, { method: 'POST', headers, body: JSON.stringify(body) });
  const sid = res.headers.get('mcp-session-id');
  if (sid) sessionId = sid;

  const contentType = res.headers.get('content-type') || '';
  let message = null;
  const text = await res.text();
  if (contentType.includes('text/event-stream')) {
    for (const line of text.split('\n')) {
      if (line.startsWith('data:')) {
        try { message = JSON.parse(line.slice(5).trim()); } catch {}
      }
    }
  } else if (text) {
    try { message = JSON.parse(text); } catch {}
  }
  return { status: res.status, headers: res.headers, message, raw: text };
}

async function main() {
  if (!TOKEN) { console.error('FAVCIRCLES_TOKEN not set'); process.exit(1); }
  console.log(`Target: ${MCP_URL}\n`);

  console.log('1. protected-resource metadata');
  const meta = await fetch(`${base}/.well-known/oauth-protected-resource`);
  const metaJson = await meta.json().catch(() => ({}));
  check('200', meta.status === 200, `got ${meta.status}`);
  check('has resource field', typeof metaJson.resource === 'string', JSON.stringify(metaJson));
  check('has scopes_supported', Array.isArray(metaJson.scopes_supported) && metaJson.scopes_supported.length > 0, JSON.stringify(metaJson.scopes_supported));
  const metaPath = await fetch(`${base}/.well-known/oauth-protected-resource/mcp`);
  const metaPathJson = await metaPath.json().catch(() => ({}));
  check('path-aware PRM 200', metaPath.status === 200, `got ${metaPath.status}`);
  check('path-aware resource ends /mcp', typeof metaPathJson.resource === 'string' && metaPathJson.resource.endsWith('/mcp'), JSON.stringify(metaPathJson.resource));

  console.log('2. no token -> 401');
  const noAuth = await rpc({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 's', version: '0' } } }, { token: null });
  check('401', noAuth.status === 401, `got ${noAuth.status}`);
  // (fetch a fresh response for the header since rpc consumed it)
  const noAuthRaw = await fetch(MCP_URL, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' }, body: '{}' });
  check('WWW-Authenticate present', (noAuthRaw.headers.get('www-authenticate') || '').includes('resource_metadata'));

  console.log('3. bad token -> 401');
  const badTok = await rpc({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 's', version: '0' } } }, { token: 'eyJhbGciOiJIUzI1NiJ9.eyJ1aWQiOiJ4In0.invalidsig' });
  check('401', badTok.status === 401, `got ${badTok.status}`);

  console.log('4. initialize');
  sessionId = null;
  const init = await rpc({ jsonrpc: '2.0', id: 2, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'http-smoke', version: '0.0.1' } } });
  check('200', init.status === 200, `got ${init.status}: ${init.raw.slice(0, 200)}`);
  check('serverInfo favcircles', init.message?.result?.serverInfo?.name === 'favcircles', JSON.stringify(init.message?.result?.serverInfo));
  check('has instructions', typeof init.message?.result?.instructions === 'string' && init.message.result.instructions.length > 0);
  await rpc({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} }).catch(() => {});

  console.log('5. tools/list (Apps SDK surface)');
  const list = await rpc({ jsonrpc: '2.0', id: 3, method: 'tools/list', params: {} });
  const tools = list.message?.result?.tools || [];
  check('26 tools', tools.length === 26, `got ${tools.length}: ${tools.map(t => t.name).join(', ')}`);
  const missingOut = tools.filter(t => !t.outputSchema).map(t => t.name);
  check('all tools have outputSchema', missingOut.length === 0, missingOut.join(', '));
  const missingAnn = tools.filter(t => !t.annotations || typeof t.annotations.readOnlyHint !== 'boolean').map(t => t.name);
  check('all tools have annotations', missingAnn.length === 0, missingAnn.join(', '));
  const missingMeta = tools.filter(t => !t._meta || !t._meta['openai/toolInvocation/invoking']).map(t => t.name);
  check('all tools have invocation strings', missingMeta.length === 0, missingMeta.join(', '));
  for (const name of ['get_current_user', 'list_connections', 'get_friend_circles', 'get_network_recommendations', 'find_shared_favorites',
                      'get_network_suggestions', 'post_suggestion', 'discover_places', 'search_users', 'send_connection_request',
                      'respond_to_connection_request', 'get_network_activity']) {
    check(`tool present: ${name}`, tools.some(t => t.name === name));
  }

  console.log('6. tools/call list_circles (live backend)');
  const call = await rpc({ jsonrpc: '2.0', id: 4, method: 'tools/call', params: { name: 'list_circles', arguments: {} } });
  const text = call.message?.result?.content?.[0]?.text || '';
  check('returned text', text.length > 0, JSON.stringify(call.message?.error) || call.raw.slice(0, 200));
  check('not an error', !call.message?.result?.isError, text.slice(0, 200));
  check('mentions circle ids', /\(id: /.test(text), text.slice(0, 120));
  const sc = call.message?.result?.structuredContent;
  check('has structuredContent', !!sc && typeof sc.count === 'number' && Array.isArray(sc.circles), JSON.stringify(sc || null).slice(0, 120));
  console.log('     preview: ' + text.split('\n')[0]);

  console.log('7. tools/call get_current_user (live backend)');
  const me = await rpc({ jsonrpc: '2.0', id: 5, method: 'tools/call', params: { name: 'get_current_user', arguments: {} } });
  const meSc = me.message?.result?.structuredContent;
  check('not an error', !me.message?.result?.isError, (me.message?.result?.content?.[0]?.text || '').slice(0, 200));
  check('has user + circles', !!meSc && !!meSc.user && typeof meSc.user.id === 'string' && Array.isArray(meSc.circles), JSON.stringify(meSc || null).slice(0, 150));

  console.log('8. tools/call list_connections (live backend)');
  const conns = await rpc({ jsonrpc: '2.0', id: 6, method: 'tools/call', params: { name: 'list_connections', arguments: {} } });
  const connSc = conns.message?.result?.structuredContent;
  check('not an error', !conns.message?.result?.isError, (conns.message?.result?.content?.[0]?.text || '').slice(0, 200));
  check('has connections array', !!connSc && Array.isArray(connSc.connections), JSON.stringify(connSc || null).slice(0, 150));

  console.log('9. tools/call get_network_recommendations (live backend)');
  const recs = await rpc({ jsonrpc: '2.0', id: 7, method: 'tools/call', params: { name: 'get_network_recommendations', arguments: {} } });
  const recSc = recs.message?.result?.structuredContent;
  check('not an error', !recs.message?.result?.isError, (recs.message?.result?.content?.[0]?.text || '').slice(0, 200));
  check('has recommendations array', !!recSc && Array.isArray(recSc.recommendations), JSON.stringify(recSc || null).slice(0, 150));
  console.log('     count: ' + (recSc ? recSc.count : '?'));

  console.log('10. tools/call get_network_suggestions (live backend)');
  const sugg = await rpc({ jsonrpc: '2.0', id: 8, method: 'tools/call', params: { name: 'get_network_suggestions', arguments: {} } });
  const suggSc = sugg.message?.result?.structuredContent;
  check('not an error', !sugg.message?.result?.isError, (sugg.message?.result?.content?.[0]?.text || '').slice(0, 200));
  check('has suggestions array', !!suggSc && Array.isArray(suggSc.suggestions), JSON.stringify(suggSc || null).slice(0, 150));

  console.log('11. tools/call discover_places (live backend)');
  const disc = await rpc({ jsonrpc: '2.0', id: 9, method: 'tools/call', params: { name: 'discover_places', arguments: { query: 'pizza' } } });
  const discSc = disc.message?.result?.structuredContent;
  check('not an error', !disc.message?.result?.isError, (disc.message?.result?.content?.[0]?.text || '').slice(0, 200));
  check('has places array', !!discSc && Array.isArray(discSc.places), JSON.stringify(discSc || null).slice(0, 150));
  console.log('     count: ' + (discSc ? discSc.count : '?'));

  console.log('12. tools/call get_network_activity (live backend)');
  const act = await rpc({ jsonrpc: '2.0', id: 10, method: 'tools/call', params: { name: 'get_network_activity', arguments: {} } });
  const actSc = act.message?.result?.structuredContent;
  check('not an error', !act.message?.result?.isError, (act.message?.result?.content?.[0]?.text || '').slice(0, 200));
  check('has activities array', !!actSc && Array.isArray(actSc.activities), JSON.stringify(actSc || null).slice(0, 150));

  console.log('13. tools/call search_users (live backend)');
  const su = await rpc({ jsonrpc: '2.0', id: 11, method: 'tools/call', params: { name: 'search_users', arguments: { query: 'Dan' } } });
  const suSc = su.message?.result?.structuredContent;
  check('not an error', !su.message?.result?.isError, (su.message?.result?.content?.[0]?.text || '').slice(0, 200));
  check('has users array', !!suSc && Array.isArray(suSc.users), JSON.stringify(suSc || null).slice(0, 150));
  console.log('     count: ' + (suSc ? suSc.count : '?'));

  console.log(failures === 0 ? '\nHTTP SMOKE TEST PASSED' : `\nHTTP SMOKE TEST FAILED (${failures} failures)`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => { console.error('smoke error:', e.message); process.exit(1); });
