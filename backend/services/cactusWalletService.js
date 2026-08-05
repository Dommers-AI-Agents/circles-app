// backend/services/cactusWalletService.js
//
// Client for the cactus-network wallet RPC (Chia-fork) that settles FavCoin
// claims on-chain. Talks to Wesley's node over HTTPS with mutual TLS — the
// node's wallet RPC refuses connections without a client cert signed by its
// private CA, which is the entire access control.
//
// THE CONTRACT THAT PREVENTS DOUBLE-SENDS: sendCat() classifies every attempt
// as exactly one of three outcomes, and the caller treats them differently:
//
//   {outcome:'sent', txId}      RPC responded success — coins are in flight
//   {outcome:'rejected', reason} RPC responded with an in-protocol error —
//                                a response arrived, so nothing was broadcast;
//                                safe to refund
//   {outcome:'unknown', reason}  transport failure (timeout, reset, 5xx) —
//                                the spend MAY have broadcast. Never retried
//                                automatically; the claim is quarantined for
//                                human review. Ambiguity always parks.
//
// Chia-family RPC has no idempotency keys — a repeated cat_spend is a second
// real payment. This classification is what stands in for one.

const https = require('https');

const env = () => ({
  enabled: process.env.PIGGY_CLAIMS_ENABLED === 'true',
  rpcUrl: process.env.CACTUS_WALLET_RPC_URL || '',
  certB64: process.env.CACTUS_RPC_CERT_B64 || '',
  keyB64: process.env.CACTUS_RPC_KEY_B64 || '',
  assetId: process.env.CACTUS_ASSET_ID || '',
  catWalletId: parseInt(process.env.CACTUS_CAT_WALLET_ID || '0', 10),
  explorerBaseUrl: process.env.CACTUS_EXPLORER_BASE_URL || 'https://explorer.cactus-network.net/#/'
});

const isEnabled = () => {
  const e = env();
  return e.enabled && !!e.rpcUrl && !!e.certB64 && !!e.keyB64 && !!e.assetId && e.catWalletId > 0;
};

const explorerBaseUrl = () => env().explorerBaseUrl;

// Raw RPC call. Throws on transport problems; resolves with the parsed JSON
// body (which itself carries success:true/false) when a response arrived.
function rpc(path, body) {
  const e = env();
  const url = new URL(path, e.rpcUrl);
  const payload = JSON.stringify(body || {});
  const options = {
    method: 'POST',
    hostname: url.hostname,
    port: url.port || 443,
    path: url.pathname,
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
    cert: Buffer.from(e.certB64, 'base64'),
    key: Buffer.from(e.keyB64, 'base64'),
    // The node's RPC cert is signed by its own private CA, not a public one.
    // The mTLS client cert is the authentication; we accept the server cert.
    rejectUnauthorized: false,
    timeout: 30000
  };
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode !== 200) {
          return reject(new Error(`RPC HTTP ${res.statusCode}: ${data.slice(0, 200)}`));
        }
        try { resolve(JSON.parse(data)); } catch (parseError) {
          reject(new Error(`RPC unparseable response: ${data.slice(0, 200)}`));
        }
      });
    });
    req.on('timeout', () => { req.destroy(new Error('RPC timeout')); });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

// Send `mojos` of the FavCoins CAT to `address`. See classification contract
// at the top of this file. `memo` ties the on-chain tx back to the claim row.
async function sendCat({ address, mojos, memo }) {
  if (!isEnabled()) return { outcome: 'rejected', reason: 'claims_disabled' };
  let response;
  try {
    response = await rpc('/cat_spend', {
      wallet_id: env().catWalletId,
      inner_address: address,
      amount: mojos,
      fee: 0,
      memos: memo ? [memo] : []
    });
  } catch (transportError) {
    // The request may or may not have reached the wallet — quarantine.
    return { outcome: 'unknown', reason: transportError.message };
  }
  if (response.success === true) {
    const txId = response.transaction_id
      || (response.transaction && response.transaction.name)
      || null;
    if (!txId) return { outcome: 'unknown', reason: 'success_without_tx_id' };
    return { outcome: 'sent', txId };
  }
  // A well-formed error response means the wallet refused — nothing broadcast.
  return { outcome: 'rejected', reason: response.error || 'rpc_rejected' };
}

// True once the transaction is confirmed in a block; false while in flight.
// Throws on transport failure (caller just tries again next pass).
async function getTransactionConfirmed(txId) {
  const response = await rpc('/get_transaction', { transaction_id: txId });
  if (response.success !== true) {
    throw new Error(`get_transaction failed: ${response.error || 'unknown'}`);
  }
  return response.transaction && response.transaction.confirmed === true;
}

// Startup/smoke sanity: confirm the CAT wallet exists on the hot key.
async function getWallets() {
  const response = await rpc('/get_wallets', {});
  if (response.success !== true) {
    throw new Error(`get_wallets failed: ${response.error || 'unknown'}`);
  }
  return response.wallets || [];
}

module.exports = { isEnabled, explorerBaseUrl, sendCat, getTransactionConfirmed, getWallets };
