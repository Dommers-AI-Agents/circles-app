# FavCircles ⇄ Cactus Node — Setup Handoff

**To: Claude running on the cactus-network node machine.**
**From: Claude working on the FavCircles app (backend on Google Cloud Run).**

FavCircles is shipping a "Claim" feature: users convert in-app FavCoins into the
already-minted FavCoins CAT, sent to their own Cactus wallet addresses. The
FavCircles backend will call **this machine's wallet RPC** to do the sending.
Nothing in cactus-blockchain itself needs to change — this is exposure,
credentials, and wallet prep only.

The backend will call exactly three wallet RPC endpoints:
- `cat_spend` — send FavCoins CAT to a user's address (one send per claim)
- `get_transaction` — poll a sent transaction until confirmed
- `get_wallets` — startup sanity check (find the CAT wallet)

Volume is tiny for now (single-digit claims per week). Sends are one-at-a-time,
never concurrent bursts.

---

## What to do on this machine

### 1. Expose the wallet RPC to the internet

The FavCircles backend runs on Cloud Run (no stable egress IP today), so the
wallet RPC port must be reachable from any IP — **mutual TLS is the gate**:
Chia-family RPC refuses any connection without a client cert signed by this
node's private CA, so exposure is cert-gated, not open.

- Port-forward / firewall-allow the **wallet RPC port** (9256-family default —
  confirm the actual port from this fork's config) to this machine.
- If this machine is on a residential connection without a static IP, set up a
  DDNS hostname (or tell us the static IP if there is one).
- Confirm the wallet service and node run 24/7 (auto-start on reboot). If the
  machine goes offline, FavCircles claims queue safely and settle when it
  returns — nothing breaks, but users wait.
- Optional hardening later: FavCircles can move to a static egress IP (Cloud
  NAT) so you can IP-restrict. Not needed for v1.

### 2. Prepare the hot wallet

- The wallet the RPC serves should be the **hot settlement wallet** (NOT the
  cold treasury key — never put the treasury mnemonic on a networked service).
- Add/confirm the FavCoins CAT wallet (by asset ID) on that key.
- Fund it with **50,000 FavCoins** from treasury (agreed initial float) plus a
  small amount of CAC for transaction fees.

### 3. Send back the connection bundle

Fill this in and return it to Wesley (values only he should carry between
machines — treat the cert/key as secrets):

> **Superseded (Aug 2026):** the backend no longer talks to the wallet RPC
> directly — a settlement broker fronts it (see
> `FAVCIRCLES_E2E_TESTING.md` for the API contract). The bundle is now:

```
CACTUS_BROKER_URL=https://node.cactus-network.net:12444
CACTUS_BROKER_TOKEN=<bearer token from the broker's env — single shared secret>
CACTUS_BROKER_CA_B64=<base64 broker_ca.crt — private CA, pinned by the backend>
CACTUS_RPC_CERT_B64=<base64 client.crt — client cert issued by that CA>
CACTUS_RPC_KEY_B64=<base64 client.key>
CACTUS_ASSET_ID=3c33e7f3fe78576292b3afe0a4aa1a426219077c4bc11e5e9f0ffe326316131c
CACTUS_FINGERPRINT=1244870717  (hot wallet key; healthz asserts it)
HOT_WALLET_ADDRESS=<cac1… receive address, for our records>
HOT_WALLET_FUNDED=<yes — 50,000 FavCoins + CAC for fees>
```

(`CACTUS_CAT_WALLET_ID` is no longer needed — the broker owns wallet
selection. Explorer deep links go to `#/coin/{coin_id}`, not `/tx/…`; the
backend computes the coin id at confirmation.)

Notes:
- Base64 the PEMs as single lines (`base64 -w0` on Linux, `base64 -i file` on
  macOS) — they'll travel as env vars.
- **Do NOT send**: any mnemonic, the treasury key, or the CA private key. Only
  the wallet client cert + key above.

### 4. Verify before handing back

From this machine, prove the RPC works end-to-end (self-call first, then via
the public hostname to prove the port-forward):

```
# expect {"success": true, ...} listing the CAT wallet:
curl -sk --cert .../private_wallet.crt --key .../private_wallet.key \
  https://<public-host>:<port>/get_wallets -d '{}' -H 'Content-Type: application/json'
```

Also do one **1-coin `cat_spend` to a wallet Wesley controls** and confirm it
lands and shows on https://explorer.cactus-network.net/#/ — that's the smoke
test that de-risks everything downstream.

---

## Questions? 

Route them through Wesley. Once the bundle above comes back, the FavCircles
side wires the env vars, runs its own 1-coin smoke test, and turns claiming on.
