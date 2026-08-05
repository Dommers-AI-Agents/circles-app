# Piggy Bank / FavCoin Implementation Plan

**Handoff doc for Claude Code (terminal).** Written 2026-07-31 after a design session with Wesley. This is the complete, decided plan — implement Phases 1–3 now; Phase 4 (blockchain) is deliberately deferred.

---

## 1. Product summary & decisions already made (do not re-litigate)

Users earn **FavCoins** (a virtual coin) for contributing to FavCircles: adding places, sharing, referrals, etc. Coins drop into a per-user **piggy bank** with a deposit animation. Later (Phase 4, NOT NOW) confirmed coins become claimable as a real fixed-supply **CAT token (10B, single-issuance) on the cactus-network blockchain** (a live Chia fork Wesley owns — proof of space/time, UTXO coin-set model, NOT EVM; repo: https://github.com/Cactus-Network/cactus-blockchain).

Decisions locked during the design session:

- **Off-chain ledger is the source of truth.** The chain is settlement-only, batched, claim-triggered. Never a per-action on-chain write.
- **Two-stage clearing:** earns land as `pending` (animation plays immediately), a worker promotes to `confirmed` after a **48h clearing window**, re-validating the underlying fact. Only confirmed coins will ever settle on-chain. Failures become reversal records — history is append-only, never mutated.
- **Non-transferable in v1.** No user-to-user gifting.
- **Include `place_adopted`** (someone else saves a place you shared) — the quality-aligned flagship earn.
- **Claim threshold** (Phase 4): min 500 confirmed coins to claim; conversion coins→CAT default 1:1 (tunable).
- **Config-driven economy:** point values, caps, windows all live in a versioned config file, not scattered in code. Every ledger row records the rule version that priced it.
- ~~Coins are deliberately **valueless** (no purchase, no trade, walled-garden chain later). This is a legal posture — don't add anything implying monetary value.~~ **SUPERSEDED 2026-08-03 by Wesley — see §8.1.** FavCoins are now presented as crypto coins on the Cactus blockchain whose value is whatever users assign them.
- UI: the existing **'$' section gets a second tab "myPiggyBank"** next to the existing store-loyalty Rewards. The add-place background-progress feedback gets replaced/augmented with a piggy-bank coin-deposit animation.

**Keep the piggy bank system SEPARATE from the existing sticker rewards system** (`rewardService.js` / `rewardPoints` on users / `rewardEvents` collection). That's the store-loyalty program — different product, stays as-is. Parallel systems, two tabs in the same '$' section.

---

## 2. Codebase facts (verified 2026-07-31)

Repo root: `/Users/wesleysgroi/circles-app`. Backend: Node/Express + Firestore (`backend/`), deployed on Cloud Run. iOS: Swift/UIKit (`ios/`), ~271 files. Read `CLAUDE.md` first — mandatory iOS patterns (BaseViewController, AlertPresenter, UIButton factories).

### Patterns to copy

- **Idempotency pattern** (exists, proven): Firestore **doc ID = dedup key** + `ref.create()` which throws `ALREADY_EXISTS` (error.code 6) on duplicates. See `rewardService.awardPoints()` in `backend/services/rewardService.js:238`. Key sanitizer `sanitizeKeyPart` in `backend/models/StickerModels.js:223` (strips `/` and `.`).
- **Service style:** singleton class with `get db() { return getFirestore(); }`, exported via `module.exports = new X()`. See `rewardService.js`, `milestoneService.js`.
- **Config style:** plain module in `backend/config/` — see `backend/config/rewardConfig.js`.
- **Models/factories:** `backend/models/StickerModels.js` (collection names + `create*` factories + validators). Core collection names in `backend/models/FirestoreModels.js` (`COLLECTIONS`).
- **Scheduled workers:** Cloud Scheduler → `POST /api/tasks/<job>` in `backend/routes/taskRoutes.js`, guarded by `verifyScheduler` middleware (OIDC or `SCHEDULER_SECRET` bearer). Add the clearing job here.
- **Route mounting:** `backend/server.js` — rewards mounted at line ~368 (`app.use('/api/rewards', ...)`). Mount piggy bank similarly.
- **Auth:** most controllers use `req.user.uid` (from `middleware/firebaseAuth.js` `protect`); referralController uses `req.userId`. Match whichever the file you're editing uses.
- **Fire-and-forget hook style:** see the sticker share-conversion hook at `backend/controllers/firebasePlaceController.js:1348-1351` — non-blocking, try/catch inside the service, never fails the parent request. All piggy-bank hooks must follow this: **an earning failure must never break the user action.**
- **Tests:** jest; Firestore mocked via `jest.mock('../../config/firebase', ...)`. Example: `backend/services/__tests__/circleAdvisorQuota.test.js`. `FieldValue` is exported as a getter from `backend/config/firebase.js`.

### Earning hook locations (exact)

| Event | File | Where |
|---|---|---|
| `add_place` | `backend/controllers/firebasePlaceController.js` | `createPlace`, after `ensureGlobalPlaceLink` (~line 1298) — you need `globalPlaceId` for the dedup key. Response is sent at line ~1333; hook can run after (fire-and-forget) but the client wants the earn in the create response if cheap — see §5 API note. |
| `place_adopted` | same file | the existing `req.body.refUserId` block at ~1348 (piggy-bank version alongside the sticker `awardShareConversion`) |
| `create_circle` | `backend/controllers/firebaseCircleController.js` | `exports.createCircle` (~line 410), after `circleRef` created |
| `share_circle` | `backend/controllers/circleSharingController.js` | `shareCircle` (line ~17), after share persisted |
| `connection_accepted` | `backend/controllers/connectionController.js` | TWO paths: `acceptConnection` (~line 579) and the auto-accept branch inside `sendConnectionRequest` (~line 454–540) |
| `referral_signup` | `backend/controllers/referralController.js` | `applyReferralCode` (~line 96), after batch commit — credit the **referrer** (`referrerId`); invitee is `userId` |
| `suggestion_posted` | `backend/controllers/suggestionController.js` | `createNewSuggestion` (line ~19) |

### iOS side (needs a quick locate pass — not fully mapped)

An exploration of `ios/` for these was still in flight when this doc was written. Locate before Phase 3:
1. The '$' section view controller (store-loyalty Rewards UI — search `Reward`, `Loyalty`, sticker/offers screens) and whether it has a tab/segmented control to extend.
2. The add-place save flow controller + its in-flight/background progress feedback (the thing to replace with the piggy-bank deposit animation). Note: add-place controller was split into core + `+Map`/`+Search`/etc. sibling files (Wave 4 refactor).
3. `APIService` networking layer — follow its endpoint/decoding idiom for new endpoints.
4. Any existing celebration/confetti/milestone animation utilities to reuse (there's a milestone celebration triggered off `totalPlaces` in the create-place response — find its client handler).
5. Models location/idiom (Codable structs).

---

## 3. New Firestore collections

### `piggyLedger` — append-only, doc ID = dedup key
```
userId        string
eventType     'add_place' | 'create_circle' | 'share_circle' | 'connection_accepted'
              | 'referral_signup' | 'place_adopted' | 'suggestion_posted'
coins         int           // positive earn; reversals flip status, not sign
status        'pending' | 'confirmed' | 'reversed' | 'held'
sourceRef     map           // { placeId?, globalPlaceId?, circleId?, targetUserId?, inviteeId?, suggestionId? }
ruleVersion   string
createdAt     ISO string
clearAt       ISO string    // createdAt + CLEARING_WINDOW_HOURS
confirmedAt   ISO string | null
reversedAt    ISO string | null
reverseReason string | null
```

### `piggyBanks` — materialized balance, doc ID = userId
```
pendingCoins    int
confirmedCoins  int
lifetimeCoins   int    // incremented at CONFIRM time
settledOnChain  int    // always 0 until Phase 4
updatedAt       ISO string
```

**Atomicity rule:** ledger write + bank increment happen in one `db.runTransaction`: `tx.create(ledgerRef)` (throws on duplicate → swallow as no-op) + `tx.set(bankRef, {..FieldValue.increment..}, {merge:true})`. Same for clearing (status flip + pending→confirmed move). The bank doc must never drift from the ledger.

### Dedup keys (via `sanitizeKeyPart` on each part)
```
add_place:{uid}:{globalPlaceId || placeDocId}      // globalPlaceId preferred: re-adding same venue never pays twice
create_circle:{uid}:{circleId}
share_circle:{uid}:{circleId}:{targetUserId}
connection:{min(uidA,uidB)}:{max(uidA,uidB)}        // order-independent — request/accept cycles can't farm it
referral:{inviteeUserId}                            // one payout per new human ever
adopted:{sharerUid}:{globalPlaceId || googlePlaceId}:{adderUid}
suggestion:{uid}:{suggestionId}
```

### Firestore indexes (add to `backend/firestore.indexes.json`, deploy with `backend/deploy-indexes.sh`)
- `piggyLedger`: (`userId` ASC, `createdAt` DESC) — history reads
- `piggyLedger`: (`userId` ASC, `eventType` ASC, `createdAt` DESC) — daily-cap counts
- `piggyLedger`: (`status` ASC, `clearAt` ASC) — clearing worker scan

---

## 4. New backend files

### `backend/config/piggyBankConfig.js`
```js
module.exports = {
  RULE_VERSION: '2026.07-a',
  CLEARING_WINDOW_HOURS: 48,
  COINS: {
    ADD_PLACE: 10, CREATE_CIRCLE: 25, SHARE_CIRCLE: 15,
    CONNECTION_ACCEPTED: 20, REFERRAL_SIGNUP: 200,
    PLACE_ADOPTED: 30, SUGGESTION_POSTED: 5
  },
  DAILY_CAPS: {              // earns past the cap: action still succeeds, pays 0
    ADD_PLACE: 20, CREATE_CIRCLE: 5, SHARE_CIRCLE: 15,
    CONNECTION_ACCEPTED: 20, REFERRAL_SIGNUP: 5,
    PLACE_ADOPTED: 30, SUGGESTION_POSTED: 10
  },
  CREATE_CIRCLE_MIN_PLACES: 3,   // enforced at CLEARING time, not earn time
  CLAIM: { MIN_CONFIRMED_TO_CLAIM: 500, COINS_PER_CAT: 1 },  // Phase 4 placeholders
  CLEARING_BATCH_SIZE: 200,
  HISTORY_PAGE_SIZE: 25
};
```

### `backend/models/PiggyBankModels.js`
`PIGGY_COLLECTIONS` (`piggyLedger`, `piggyBanks`), `PIGGY_EVENT_TYPES`, `createPiggyLedgerEntry(data)` factory, `derivePiggyDedupKey(eventType, parts)` — the pure key builder above (unit-test this hard), re-export/reuse `sanitizeKeyPart`.

### `backend/services/piggyBankService.js`
Singleton, mirroring `rewardService` style:

- **`credit({ userId, eventType, sourceRef })`** — the single entry point every hook calls. Steps:
  1. Look up coins for eventType in config; 0/unknown → no-op.
  2. `deriveDedupKey`; **daily-cap check**: Firestore `count()` on today's ledger rows for (userId, eventType); at/over cap → `{ credited:false, reason:'daily_cap' }`.
  3. Transaction: `tx.create(ledgerRef, entry)` + bank `pendingCoins`/`updatedAt` increment (merge-set).
  4. `ALREADY_EXISTS` → `{ credited:false, duplicate:true }`. Any error: log, never throw to caller (fire-and-forget contract).
  5. Return `{ credited:true, coins, eventType }` so hooks that want to include it in a response can.
- **`getPiggyBank(userId)`** — bank doc (zeros if absent) + last `HISTORY_PAGE_SIZE` ledger entries + display config (coin values, claim threshold) so iOS renders without hardcoding.
- **`runClearing()`** — the Phase 2 worker:
  1. Query `status=='pending' && clearAt <= now`, limit `CLEARING_BATCH_SIZE`; loop until empty or a max-batches guard.
  2. Re-validate per type: `add_place` → place doc exists, `deletedAt == null` · `create_circle` → circle exists + `placesCount >= CREATE_CIRCLE_MIN_PLACES` · `share_circle` → circle still exists · `connection_accepted` → connection doc still `status=='accepted'` · `referral_signup` → invitee exists, `referredBy` matches, **activation**: invitee has ≥1 non-deleted place or ≥1 connection · `place_adopted` → adopter's place still exists · `suggestion_posted` → suggestion still exists.
  3. Pass → transaction: status `confirmed`, `confirmedAt`; bank `pendingCoins -N, confirmedCoins +N, lifetimeCoins +N`.
  4. Fail → transaction: status `reversed` + `reverseReason`; bank `pendingCoins -N`.
  5. Return summary `{ scanned, confirmed, reversed }` for the task response/log.
- **`reconcile()`** (nice-to-have): recompute one user's bank from ledger, report drift.

### `backend/routes/piggyBankRoutes.js` + controller
Mount in `server.js` next to rewards: `app.use('/api/piggy-bank', require('./routes/piggyBankRoutes'))`.
- `GET /api/piggy-bank` (protect) → `{ success, bank: {pendingCoins, confirmedCoins, lifetimeCoins, settledOnChain}, events: [...], config: {coinValues, minConfirmedToClaim} }`
- `GET /api/piggy-bank/history?before=<iso>` (protect) → paginated ledger.
- Claim endpoint: **do not build** (Phase 4). Reserve `POST /api/piggy-bank/claim` returning 501 if you want the route stubbed.

### Clearing task endpoint
In `backend/routes/taskRoutes.js`: `POST /api/tasks/piggy-bank-clearing` with `verifyCloudScheduler`, calls `piggyBankService.runClearing()`, returns the summary. Add to the `/health` endpoint list. Cloud Scheduler cadence: hourly (`0 * * * *`) — see `backend/setup-cloud-scheduler.sh` for how existing jobs were registered.

### Earning hooks
Add to the seven locations in §2, each in the fire-and-forget style, e.g. in `createPlace` after `ensureGlobalPlaceLink`:
```js
piggyBankService.credit({
  userId: req.user.uid,
  eventType: 'add_place',
  sourceRef: { placeId: placeRef.id, globalPlaceId: globalPlaceId || null, circleId }
}).then(r => { /* optionally attach to response — see below */ }).catch(() => {});
```
**Response contract for the animation:** the iOS piggy-bank deposit animation should trigger off the create-place response. Await the `credit()` call (it's 1 count query + 1 transaction, cheap) **before** `res.status(201).json(...)` in `createPlace` only, and include `piggyBank: { credited, coins }` in the response. All other hooks stay fully fire-and-forget. Both connection-accept paths must use the same pair-key so only one credit per pair; credit **both** users (two ledger rows, one per userId — key must therefore include the beneficiary: use `connection:{min}:{max}:{beneficiaryUid}`).

> Note this refines §3's pair key: `connection:{min}:{max}:{uid}` — still order-independent per pair, one row per beneficiary.

### Tests — `backend/services/__tests__/piggyBankService.test.js`
Mock `../../config/firebase` (copy the `circleAdvisorQuota.test.js` harness; you'll need to extend the mock with `create` (throws code-6 on existing id), `count()`, and a transaction supporting `create`/`set`/`update`). Must cover: double-credit blocked (same event twice → one row) · daily cap → zero-credit · connection pair-key symmetry (A→B and B→A collide; A's and B's own rows both exist) · clearing confirms a valid add_place · clearing reverses a deleted place · create_circle below min places reverses · referral without activation reverses · bank arithmetic matches ledger after mixed confirm/reverse. Run: `cd backend && npx jest piggyBank`.

---

## 5. Phase 3 — iOS

1. **Locate** the items in §2 "iOS side" first.
2. **Models + API:** `PiggyBank`, `PiggyLedgerEvent` Codable structs; APIService methods for `GET /api/piggy-bank` (+history). Parse the new `piggyBank` field on the create-place response (optional field — must not break if absent).
3. **Deposit animation:** on create-place success with `piggyBank.credited == true`, show a piggy bank receiving a FavCoin (replaces/augments the current background-working feedback). Reuse the milestone-celebration plumbing if it fits. Keep it short (~1.5s), non-blocking, with the coin amount ("+10").
4. **myPiggyBank tab:** in the '$' section alongside Rewards (segmented control or tab pair — follow whatever container that section already uses; follow BaseViewController/AlertPresenter/button-factory rules from CLAUDE.md). Content: big confirmed balance + piggy bank art · "pending" line with count ("clears within 48h") · lifetime earned · recent activity list (event type, coins, status, date) from `events` · "How to earn" footer from `config.coinValues` · an inert/disabled "Claim to cactus wallet" affordance gated by `minConfirmedToClaim` (copy: "coming soon") — NO claim network call.
5. Pending vs confirmed must be visually distinct (e.g. muted/“clearing” badge on pending rows).

---

## 6. Phase 4 — blockchain settlement (DO NOT BUILD NOW; context for later)

When the piggy bank is proven: issue the 10B single-issuance CAT on cactus-network (Chia CAT2 standard; fixed supply enforced by the TAIL); run a cactus full node + wallet service; custodial per-user wallets (derived keys, encrypted server-side); a settlement worker converts `confirmed` → on-chain CAT transfers (batched, threshold-gated via `CLAIM` config) and stamps `settledOnChain`; myPiggyBank shows the explorer link. Chia UTXO dust → always consolidate per-user transfers. The `status` vocabulary reserves `claimed`/`settled` extensions; `settledOnChain` field already exists.

---

## 7. Build order & verification

1. Config + models + dedup key builder (+ key unit tests).
2. `piggyBankService.credit` + tests (idempotency, caps, atomicity).
3. Hooks in all seven controllers (six fire-and-forget + awaited add_place) — verify no user action can fail because of a credit error.
4. Firestore indexes → deploy.
5. `runClearing` + tests → task route → Cloud Scheduler job (hourly).
6. Balance/history endpoints.
7. iOS: locate pass → models/API → myPiggyBank tab → deposit animation.
8. E2E smoke: add place → 201 includes `piggyBank.credited` → `GET /api/piggy-bank` shows pending → run clearing manually (`POST /api/tasks/piggy-bank-clearing` with `SCHEDULER_SECRET`, after temporarily shrinking `CLEARING_WINDOW_HOURS` in a dev env or backdating `clearAt` on a test row) → confirmed moves → visible in tab.

**Definition of done (Phases 1–3):** all jest suites green; iOS builds; a real add-place on a dev build animates a coin into the piggy bank, the balance appears under myPiggyBank as pending, and flips to confirmed after clearing runs.

---

## 8. Phase 4 decisions addendum (2026-08-03)

Drafted with Wesley 2026-08-03. Items marked **DECIDED** are settled; items marked **(recommended)** are Claude's proposals baked in as defaults — they govern implementation unless Wesley overrides them before Phase 4 build starts.

### 8.1 Positioning — DECIDED (supersedes §1's "valueless" bullet)

FavCoins are crypto coins on the cactus-network blockchain. Their value is whatever users assign them; store owners may choose to offer prizes for them. In-app copy (PiggyBankViewController ⓘ explainer) already says this and links to cactus-blockchain.net. On-chain claiming remains "coming soon" until Phase 4 ships — copy must never claim coins are on-chain before the mint actually happens. Note for release planning: earnable-crypto positioning invites Apple review scrutiny (guideline 3.1.1 area) — re-read the current crypto rules before the App Store submission that ships claiming.

### 8.2 Supply & custody

- **10B single-issuance CAT2, TAIL-enforced fixed supply — DECIDED** (unchanged from §1/§6).
- The full 10B mints into the **issuer wallet Wesley controls**. Immediately split (recommended):
  - **Cold treasury** — bulk of supply. Mnemonic generated and stored offline (never touches a server; hardware or paper, with a second copy in a separate physical location).
  - **Hot settlement wallet** — backend-controlled, topped up manually from treasury. A server compromise then risks the float, not the supply.
  - **Hot-wallet sizing rule (2026-08-05):** fund with `max(2× total outstanding coins, ~6 months projected earning)`; top up when it falls below 1.2× outstanding. Initial funding at Phase 4 launch: **50,000 coins** (sized against 2026-08-05 reality: 8 users / 310 outstanding / ~80 coins/day — recompute from `piggyBanks` at mint time if that's grown).
- Publish the CAT **asset ID (TAIL hash)** on cactus-blockchain.net and in-app once minted, so third-party wallets can display FavCoins.

### 8.3 Allocation earmarks (recommended)

Bookkeeping earmarks, not on-chain constraints — movable by Wesley at will, but every distribution program must name which bucket it draws from so the fixed supply can't be over-promised:

| Bucket | Amount | Purpose |
|---|---|---|
| Earn settlement reserve | 8.0B | Backing every FavCoin earned in-app (the only bucket users draw from) |
| Partnerships & events | 1.5B | Sponsorships, event drops, marketing programs |
| Store-owner prizes & promos | 0.5B | Prize pools, owner-side reward experiments |

New earn types / spend programs are off-chain config+code changes (same pattern as the seven existing hooks) — the chain never constrains *how* coins are distributed, only *how many exist*.

### 8.4 Claims & wallets

- **Custodial by default (recommended):** HD-derived keys — ONE master seed (encrypted; §8.2 discipline applies) deterministically derives a child keypair per user by index. The only stored mapping is `firebaseUid → derivationIndex(+address)` (no per-user secrets in the DB; keys re-derived in memory at spend time). Keyed to the immutable Firebase UID, never email/username (those mutate — see account-fragmentation history). Users do nothing; per-user UTXO consolidation to avoid dust.
- **Self-custody as opt-in withdraw:** user installs a Cactus wallet, adds the FavCoins asset ID, pastes their `cac…` receive address into a "my wallet address" field in myPiggyBank. App validates address format; UI must warn that self-custody transfers are irreversible and mnemonic loss is unrecoverable. Custodial remains the default so non-crypto users are never forced through wallet setup.
- Claims are **user-triggered**, min **500 confirmed**, conversion **1:1 default** via `COINS_PER_CAT` (§1, unchanged). `COINS_PER_CAT` is the supply-stretch lever if the reserve runs down.
- **Transaction fees: paid by the user — DECIDED (Wesley, 2026-08-03).** Mechanics: cactus fees are denominated in CAC (native coin), which users won't hold, so the fee is charged as a FavCoin surcharge **withheld from the claim** (config: `CLAIM_FEE_COINS`, versioned like everything else; e.g. claim 500 → receive 500 − fee). The hot wallet fronts the CAC at broadcast and is made whole by the withheld coins — no net fee liability for FavCircles. Cactus fees are near-zero today, so the surcharge may start at 0; the policy that users bear it is what's locked.

### 8.5 Transferability

Once claimed on-chain, CATs are inherently transferable — accepted consequence of the 8.1 positioning (this replaces §1's "non-transferable" as far as *claimed* coins go). Unclaimed in-app balances remain non-transferable (no gifting) as before.

### 8.6 Post-settlement integrity

Clearing (48h re-validation) remains the fraud gate and runs **before** anything settles. Settled coins are bearer assets: no clawback, no burn-on-ban. If abuse is discovered after settlement, the account is banned but the coins stand — the cost of this policy is bounded by the claim threshold and clearing window. (A voluntary burn address may exist later for prize redemptions; not designed yet.)

### 8.7 Build order when Phase 4 is greenlit

1. Mint ceremony: TAIL + 10B issuance on cactus-network; treasury/hot split; publish asset ID.
2. Cactus full node + wallet service alongside the backend; hot-wallet ops runbook.
3. Settlement worker: `confirmed` → batched CAT transfers, `settledOnChain` stamping, `claimed`/`settled` ledger statuses (§6).
4. `POST /api/piggy-bank/claim` goes 501 → live; myPiggyBank claim button activates; explorer link on settled rows.
5. Self-custody address field + withdraw path.
6. App Store review prep per 8.1.
