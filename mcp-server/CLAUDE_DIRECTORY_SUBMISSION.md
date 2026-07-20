# FavCircles → Anthropic Connectors Directory Submission Guide

Status as of July 13, 2026: the MCP server at `https://mcp.favcircles.com/mcp` is
**technically ready** for the Claude Connectors Directory — all server-side
requirements verified (see "Server readiness" below). What remains is one
account-level blocker, two uploads, a test account, and the portal walkthrough.

References:
- Submission process: https://claude.com/docs/connectors/building/submission
- Pre-submission checklist: https://claude.com/docs/connectors/building/review-criteria
- Submission portal: https://claude.ai/admin-settings/directory/submissions/new
- Escalations: mcp-review@anthropic.com

Sister doc: `CHATGPT_APP_SUBMISSION.md` (same server, OpenAI directory).

---

## ⚠️ Blocker: Team or Enterprise Claude.ai organization required

The submission portal lives in **Claude.ai admin settings**, which only exist on
Team/Enterprise plans. Individual (Free/Pro/Max) accounts cannot submit.

- Only organization **Owners / Primary owners** can submit by default.
- Options: upgrade sgroiwes@gmail.com (or a favcircles.com workspace) to a
  Claude **Team** plan, or submit through any Team/Enterprise org you have
  Owner access to. The org is the *submitter of record*; the listing's company
  info is entered separately (FavCircles).
- There is no email/form fallback for remote servers (the separate form is for
  desktop extensions only).

## Server readiness (done, deployed, verified)

- **Transport**: Streamable HTTP at `https://mcp.favcircles.com/mcp`, public
  HTTPS, same URL for every user.
- **26 tools**, every one with `title` + `readOnlyHint`/`destructiveHint`
  (plus `idempotentHint`/`openWorldHint`) — verified in `worker/src/tools.ts`
  (READ/CREATE/UPDATE/DESTRUCTIVE annotation presets). This is the portal's
  auto-scanned "Tools" step; nothing should be flagged.
- **Read/write separation**: purpose-built tools per action; no catch-all
  `api_request`-style tool. Trash model: `delete_*` (recoverable) vs
  `permanently_delete_*` (both marked destructive).
- **OAuth 2.1**: authorization-code + PKCE, **DCR** at `/register`, **CIMD**
  enabled, AS metadata + path-aware protected-resource metadata, RFC 9728
  challenges, RFC 8707 resource binding. Claude's portal supports DCR and CIMD
  out of the box — no static client registration with Anthropic needed.
- **First-party API**: mcp.favcircles.com fronts our own Cloud Run backend;
  domain matches the service. ✓ API-ownership criterion.
- **Privacy policy**: live at https://favcircles.com/privacy.html (terms at
  /terms.html). Missing/incomplete privacy policy = immediate rejection, so
  double-check it still enumerates collection, usage/storage, third-party
  sharing, retention, and contact info before submitting.
- **No unsupported use cases**: no financial transfers, no AI media
  generation. Premium stays in the iOS app (do not mention in-connector
  purchases anywhere in the listing).
- **No `ui/open-link` usage** → the "allowed link URIs" field can be left
  empty (it's optional and only suppresses link-confirmation prompts).
- **Not an MCP App** (no UI resources) → carousel screenshots not required.

Smoke tests (run from `mcp-server/`, all passing against production):
`MCP_URL=https://mcp.favcircles.com/mcp FAVCIRCLES_TOKEN=$(node scripts/mint-token.cjs) node worker/scripts/http-smoke.cjs`
(plus `oauth-flow-test.cjs`, `phase4-security-test.cjs`).

---

## Manual steps to publish

### 1. Get portal access (the blocker above)

Team/Enterprise org + Owner role → https://claude.ai/admin-settings/directory/submissions/new

### 2. Upload the public documentation page (required by publish date)

`website/connect-claude.html` is written (matches privacy.html styling).
favcircles.com is Apache-hosted — **upload it the same way privacy.html was
uploaded** so `https://favcircles.com/connect-claude.html` resolves. This is
the "documentation URL" for the Listing step. (Docs may be shared privately
during review, but must be public by launch — simplest to upload now.)

### 3. Create a reviewer test account (required, must be fully populated)

- Fresh FavCircles account with **email + password** (no MFA/SMS), e.g.
  `claude-review@favcircles.com`.
- Seed it: 3–5 circles ("Date Night", "Coffee", "NYC Trip") with several
  places each, some trash items, and connect it to at least one other seeded
  account so `list_connections`, `get_friend_circles`,
  `get_network_recommendations`, `find_shared_favorites`, and
  `get_network_suggestions` all return real results.
- Leave one **pending incoming connection request** on the account so the
  reviewer can exercise `respond_to_connection_request`.
- ⚠️ `post_suggestion` and `send_connection_request` broadcast/notify real
  users — only test these between the seeded accounts, never from a personal
  account.

### 4. Self-test every tool (you must confirm this in the portal)

The Test & launch step requires confirming you've run **every** tool yourself,
via MCP Inspector or as a custom connector in Claude:

1. Claude.ai → Settings → Connectors → Add custom connector →
   `https://mcp.favcircles.com/mcp` → OAuth login as the test account.
2. Run each of the 26 tools once (the golden prompts below cover the read
   paths; drive the write/trash/permanent-delete paths explicitly).
3. Alternative/supplement: `npx @modelcontextprotocol/inspector` against the
   same URL.
4. Check error quality while you're there: invalid ids should return
   actionable messages, not bare "Internal Server Error" (functional-quality
   criterion).

Golden prompts:
- "What circles do I have in FavCircles?"
- "Find coffee places I've saved"
- "What restaurants do my friends recommend near [city]?"
- "Which places do [friend name] and I both like?"
- "Create a circle called Weekend Trip and add [place] to it"
- "What's new in my FavCircles network?"
- "Move the Weekend Trip circle to trash, then restore it"
- "Permanently delete [test place] from my trash"

### 5. Portal walkthrough — copy-ready answers

Progress auto-saves in the browser between steps.

**Connection**
| Field | Value |
|---|---|
| Server URL | `https://mcp.favcircles.com/mcp` |
| Transport | Streamable HTTP |
| Same URL for all users? | Yes |

**Tools** — auto-synced from the server; verify all 26 land in the
read-only/write groups and none in "missing annotations".

**Listing**
| Field | Value |
|---|---|
| Server name | FavCircles |
| Tagline (≤55 chars) | Trusted place recommendations from people you know. *(52)* |
| Description (≤2,000 chars) | See below |
| Categories (1–5) | Pick closest to Lifestyle / Social / Travel / Food & Drink in the portal's taxonomy |
| Documentation URL | https://favcircles.com/connect-claude.html |
| Privacy policy URL | https://favcircles.com/privacy.html |
| Support contact | wesley@favcircles.com |
| Icon | `Marketing/claude-connector-icon-512.png` (512×512 PNG from the app icon; `chatgpt-app-icon-64.png` as small fallback) |
| URL slug | `favcircles` ⚠️ permanent once published |

Description (copy-ready, ~1,000 chars):

> FavCircles is a private, trust-based recommendation network. You save your
> favorite places into "circles" — curated collections like Date Night,
> Coffee, or NYC Trip — connect with people you know, and discover places
> through your network instead of anonymous internet reviews.
>
> With the FavCircles connector, Claude works with your circles directly in
> conversation. Ask what you've saved, search your places by name or category,
> and organize new finds into circles. Tap your network: get recommendations
> from your connections near any location, see a friend's shared circles,
> find favorites you have in common, and catch up on suggestions and activity
> from people you trust. Discover new spots in the community place database
> and save them in one step.
>
> Privacy levels (public, my network, private) are enforced server-side
> exactly as in the app. Read actions run freely; anything that changes data —
> creating circles, deleting places, posting suggestions, connection
> requests — is annotated so Claude confirms first, and deletions go to a
> recoverable trash.
>
> Requires a free FavCircles account (iOS app or favcircles.com).

**Use cases**
- Primary use cases: (1) "What do my friends recommend near X?" — trusted,
  geo-ranked recommendations from the user's own network; (2) planning —
  build/curate circles for trips, dates, and neighborhoods in conversation;
  (3) recall — "which coffee places have I saved?" across all circles;
  (4) social — find overlap with a friend, share finds with your network.
- Required before connecting: a free FavCircles account (email/password,
  Google, or Facebook — Apple-sign-in users must set a password first).
- Reads data, writes data: **both**.

**Company**
| Field | Value |
|---|---|
| Company | FavCircles |
| Website | https://favcircles.com |
| Contact | Wesley Sgroi, wesley@favcircles.com |

**Authentication**
- OAuth with **dynamic client registration** (also supports client ID
  metadata documents / CIMD). No static client ID needed. Server does not
  operate unauthenticated; all tools require login upfront.

**Data handling**
- API ownership: **our own first-party API** (FavCircles backend on Google
  Cloud Run, fronted by our Cloudflare Worker at mcp.favcircles.com).
- Personal health data: No. Sponsored content: No.

**Test & launch**
- Paste the test-account credentials + step-by-step from step 3, including
  the connect flow (directory/custom connector → FavCircles login page →
  email+password → approve). State explicitly: no MFA, no VPN, no IP
  allowlist; account is pre-populated (circles, places, trash, connections,
  one pending incoming request).
- Confirm every tool was self-run (step 4).
- Launch readiness: server is live/GA now; tested surfaces: claude.ai web
  and Claude Desktop as a custom connector (add mobile if tested).

**Compliance** — seven acknowledgments (directory guidelines, first-party
API, financial transactions, AI media generation, prompt injection,
conversation-data collection, public docs). All apply cleanly; all seven are
required.

### 6. Submit & track

- Auto-scan → listed as a **community connector** by default; Anthropic may
  escalate popular listings to verified review (functional test of each
  tool) automatically — no action needed.
- Dashboard: https://claude.ai/admin-settings/directory/submissions (status,
  reviewer feedback; post-publish server health + usage metrics).
- Handler-logic redeploys (`cd mcp-server/worker && npx wrangler deploy`) are
  fine; **adding/renaming/re-schema-ing tools changes the scanned surface —
  expect re-review.**

### Known constraints / gotchas

- Tool descriptions must describe behavior only — no instructions telling
  Claude how to behave (prompt-injection screen). Server `instructions` field
  is the right home for conventions (already the case); if the scan flags
  anything, it'll be a description, not the instructions.
- Reviewer account must be email+password (web login page limitation —
  Apple-sign-in users can't link; same as ChatGPT).
- Ages 13+, no in-connector monetization mentions — consistent with existing
  policy.
