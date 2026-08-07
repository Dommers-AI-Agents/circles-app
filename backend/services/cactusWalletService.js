// backend/services/cactusWalletService.js
//
// Client for the FavCoin settlement broker (node.cactus-network.net:12444),
// which fronts the Cactus wallet RPC and settles FavCoin claims on-chain.
// Transport is mTLS (client cert signed by the broker's private CA, server
// cert verified against that same CA) plus a bearer token on every request.
//
// THE CONTRACT THAT PREVENTS DOUBLE-SENDS: the broker keys every spend by
// `claim_id` — an idempotency key minted once per claim and reused verbatim
// on every retry. A repeated claim_id can never produce a second spend; the
// broker replays the original transaction_id instead. Retrying an ambiguous
// failure with a FRESH claim_id is the only way to double-pay through this
// system, so callers must always pass the claim row's own id.
//
// sendCat() classifies every attempt as exactly one of four outcomes:
//
//   {outcome:'sent', txId, replayed}  broker broadcast the spend (or replayed
//                                     a previous success) — coins in flight
//   {outcome:'rejected', reason}      broker refused and NOTHING was broadcast
//                                     (400 bad request, 502 broadcast:false) —
//                                     safe to fail the claim and refund
//   {outcome:'retriable', reason}     broker is temporarily unable (401 config,
//                                     429 daily cap, 503 wallet not ready) —
//                                     nothing was sent; retry the SAME claim_id
//                                     on a later pass
//   {outcome:'unknown', reason}       the spend MAY have gone out (504, 409
//                                     claim held as sending/failed, transport
//                                     failure) — never retried automatically;
//                                     quarantine for human review

const https = require('https');
const { createHash } = require('crypto');

const env = () => ({
  enabled: process.env.PIGGY_CLAIMS_ENABLED === 'true',
  baseUrl: process.env.CACTUS_BROKER_URL || process.env.CACTUS_WALLET_RPC_URL || '',
  certB64: process.env.CACTUS_RPC_CERT_B64 || '',
  keyB64: process.env.CACTUS_RPC_KEY_B64 || '',
  caB64: process.env.CACTUS_BROKER_CA_B64 || '',
  token: process.env.CACTUS_BROKER_TOKEN || '',
  assetId: process.env.CACTUS_ASSET_ID || '',
  explorerBaseUrl: process.env.CACTUS_EXPLORER_BASE_URL || 'https://explorer.cactus-network.net/#/'
});

const isEnabled = () => {
  const e = env();
  return e.enabled && !!e.baseUrl && !!e.certB64 && !!e.keyB64 && !!e.caB64 && !!e.token;
};

const explorerBaseUrl = () => env().explorerBaseUrl;

// The explorer has no /tx/ route, and CAT puzzle-hash wrapping means the coin
// never shows on the recipient's address page — the only stable link is the
// created coin itself.
const explorerCoinUrl = (coinId) => coinId ? `${env().explorerBaseUrl}coin/${coinId}` : null;

// coin_id = sha256(parent_coin_info + puzzle_hash + int_to_bytes(amount)),
// amount serialized as Chia's minimal big-endian SIGNED int (empty for 0).
function computeCoinId(parentCoinInfo, puzzleHash, amount) {
  const hex = (h) => Buffer.from(String(h).replace(/^0x/, ''), 'hex');
  let amountBytes = Buffer.alloc(0);
  if (amount) {
    amountBytes = Buffer.alloc(Math.floor((BigInt(amount).toString(2).length + 8) / 8));
    let v = BigInt(amount);
    for (let i = amountBytes.length - 1; i >= 0; i--) {
      amountBytes[i] = Number(v & 0xffn);
      v >>= 8n;
    }
  }
  return createHash('sha256')
    .update(Buffer.concat([hex(parentCoinInfo), hex(puzzleHash), amountBytes]))
    .digest('hex');
}

// Raw broker call. Throws on transport problems (timeout, reset, TLS);
// resolves with { status, body } when any HTTP response arrived — status-code
// semantics are load-bearing and classified by the caller.
function brokerRequest(path, body) {
  const e = env();
  const url = new URL(path, e.baseUrl);
  const payload = body === undefined ? null : JSON.stringify(body);
  const options = {
    method: payload === null ? 'GET' : 'POST',
    // CACTUS_BROKER_CONNECT_HOST dials an alternate address (e.g. the node's
    // LAN IP when the router won't hairpin the public one) while `servername`
    // keeps TLS verifying against the real hostname. Local testing only —
    // deploy.sh does not forward it.
    hostname: process.env.CACTUS_BROKER_CONNECT_HOST || url.hostname,
    servername: url.hostname,
    port: url.port || 443,
    path: url.pathname,
    headers: {
      Host: url.host,
      Authorization: `Bearer ${e.token}`,
      ...(payload !== null && {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload)
      })
    },
    cert: Buffer.from(e.certB64, 'base64'),
    key: Buffer.from(e.keyB64, 'base64'),
    // The broker's server cert is issued by its private CA, not a public one —
    // pin that CA explicitly and verify.
    ca: Buffer.from(e.caB64, 'base64'),
    rejectUnauthorized: true,
    // Overridable for ambiguity drills (Phase 5): a tiny timeout cuts the
    // connection mid-request to exercise the unknown/quarantine path.
    timeout: parseInt(process.env.CACTUS_BROKER_TIMEOUT_MS || '30000', 10)
  };
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        let parsed = null;
        try { parsed = JSON.parse(data); } catch (_) { /* body may be empty/plain */ }
        resolve({ status: res.statusCode, body: parsed, raw: data.slice(0, 200) });
      });
    });
    req.on('timeout', () => { req.destroy(new Error('broker timeout')); });
    req.on('error', reject);
    // Ambiguity drill (Phase 5): kill the connection right after the request
    // has fully flushed — the broker receives and processes the spend, but the
    // response is lost. Deterministic "money may have moved". Drill-only.
    if (process.env.CACTUS_BROKER_CUT_AFTER_SEND === 'true' && path === '/cat_spend') {
      req.on('finish', () => setTimeout(
        () => req.destroy(new Error('drill: connection cut after send')), 10));
    }
    if (payload !== null) req.write(payload);
    req.end();
  });
}

// Send `mojos` of FavCoin to `address`, idempotent on `claimId` (8–128 chars,
// [A-Za-z0-9_-] only — callers sanitize). See classification contract above.
async function sendCat({ claimId, address, mojos, memo }) {
  if (!isEnabled()) return { outcome: 'rejected', reason: 'claims_disabled' };
  let res;
  try {
    res = await brokerRequest('/cat_spend', {
      claim_id: claimId,
      address,
      amount_mojos: mojos,
      memo: memo || undefined
    });
  } catch (transportError) {
    // The request may or may not have reached the broker — quarantine.
    return { outcome: 'unknown', reason: transportError.message };
  }
  const { status, body } = res;
  if (status === 200 && body && body.success === true) {
    if (!body.transaction_id) return { outcome: 'unknown', reason: 'success_without_tx_id' };
    return { outcome: 'sent', txId: body.transaction_id, replayed: body.replayed === true };
  }
  const reason = (body && (body.error || body.message)) || `broker HTTP ${status}`;
  switch (status) {
    case 400: // bad address / over per-send cap / malformed claim_id — nothing sent
    case 422: // same class — the broker emits 422 for validation errors in practice
      return { outcome: 'rejected', reason };
    case 401: // bad bearer token — config problem, nothing sent
      return { outcome: 'retriable', reason: `auth: ${reason}` };
    case 409: // claim_id already used and held as sending/failed — money may have moved
      return { outcome: 'unknown', reason: `claim_id conflict: ${reason}` };
    case 429: // rolling 24h cap — back-pressure, nothing sent
      return { outcome: 'retriable', reason: 'daily_cap_reached' };
    case 502: // wallet rejected before broadcast
      if (body && body.broadcast === false) return { outcome: 'rejected', reason };
      return { outcome: 'unknown', reason };
    case 503: // wallet on wrong key / not synced — transient, nothing sent
      return { outcome: 'retriable', reason };
    case 504: // timed out mid-request — the spend may have gone out
    default:
      return { outcome: 'unknown', reason };
  }
}

// Poll a broadcast transaction. Returns { confirmed, confirmedAtHeight,
// additions } — additions carry {amount, parent_coin_info, puzzle_hash} for
// explorer coin links. Throws on transport failure or unknown tx (caller
// just tries again next pass).
async function getTransaction(txId) {
  const { status, body, raw } = await brokerRequest('/get_transaction', { transaction_id: txId });
  if (status !== 200 || !body || body.success !== true) {
    throw new Error(`get_transaction HTTP ${status}: ${(body && body.error) || raw}`);
  }
  return {
    confirmed: body.confirmed === true,
    confirmedAtHeight: body.confirmed_at_height || null,
    additions: body.additions || []
  };
}

// Back-compat shim for callers that only need the boolean.
async function getTransactionConfirmed(txId) {
  return (await getTransaction(txId)).confirmed;
}

// Startup/smoke sanity: the broker reports whether its CAT wallet matches the
// FavCoin asset id. Throws if unreachable or mismatched.
async function getWallets() {
  const { status, body, raw } = await brokerRequest('/get_wallets', {});
  if (status !== 200 || !body || body.success !== true) {
    throw new Error(`get_wallets HTTP ${status}: ${(body && body.error) || raw}`);
  }
  if (body.asset_id_matches === false) {
    throw new Error('get_wallets: broker CAT wallet asset id does NOT match FavCoin');
  }
  return body.wallets || [];
}

// Broker readiness — gate send passes on ok:true. Returns null when the
// broker can't be reached (callers treat that as not-ok).
async function healthz() {
  try {
    const { status, body } = await brokerRequest('/healthz');
    return status === 200 && body ? body : null;
  } catch (_) {
    return null;
  }
}

module.exports = {
  isEnabled,
  explorerBaseUrl,
  explorerCoinUrl,
  computeCoinId,
  sendCat,
  getTransaction,
  getTransactionConfirmed,
  getWallets,
  healthz
};
