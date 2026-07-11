# FavCircles → ChatGPT App Directory Submission Guide

Status as of July 10, 2026: the MCP server at `https://mcp.favcircles.com/mcp` is
**technically ready** for ChatGPT Apps (see "What the server provides" below,
all verified in production). What remains is account setup, assets, and the
submission itself — the manual steps in this doc.

References: developers.openai.com/apps-sdk (build/mcp-server, build/auth,
deploy/submission, app-submission-guidelines, deploy/connect-chatgpt).

---

## What the server provides (done, deployed, tested)

- **Transport**: Streamable HTTP at `https://mcp.favcircles.com/mcp` (the only
  transport ChatGPT supports). Public HTTPS, stable origin.
- **26 tools**, every one with `title`, `inputSchema`, `outputSchema`,
  `structuredContent` results, annotations (`readOnlyHint` / `destructiveHint` /
  `idempotentHint` / `openWorldHint` — reviewed at submission), and
  `openai/toolInvocation/invoking|invoked` status strings:
  - Core: `list_circles`, `get_circle`, `create_circle`, `update_circle`,
    `add_place`, `update_place`, `search_places` (query + category + circle filters)
  - Trash: `delete_circle`, `delete_place`, `list_trash`, `restore_circle`,
    `restore_place`, `permanently_delete_circle`, `permanently_delete_place`
  - Identity & social graph: `get_current_user`, `list_connections` (with
    connectionId + direction for the request flow), `get_friend_circles`,
    `search_users`, `send_connection_request`, `respond_to_connection_request`
  - Recommendations & discovery: `get_network_recommendations` (network-wide
    or geo-ranked), `find_shared_favorites` (overlap with a friend),
    `discover_places` (community-wide global place database — also used to get
    exact coordinates before `add_place`)
  - Feed: `get_network_suggestions`, `post_suggestion` (broadcasts to all
    connections, notifies them), `get_network_activity`
- **Backend search upgrade** (2026-07-10): `discover_places` matches any word
  in a place's name, case-insensitive, multi-word ("pizza", "trader jo") — via
  a `searchTokens` word-prefix array on globalPlaces docs, backfilled across
  the collection, with matching composite indexes recorded in both
  `firestore.indexes.json` files.
- **Server instructions** in the initialize response (trust-first
  recommendation behavior, id conventions, delete-confirmation policy).
- **OAuth 2.1** per the MCP auth spec: authorization-code + PKCE (S256),
  Dynamic Client Registration at `/register`, **CIMD enabled** (ChatGPT's
  preferred registration: URL-formatted client_ids), AS metadata at
  `/.well-known/oauth-authorization-server`, protected-resource metadata at
  `/.well-known/oauth-protected-resource` **and** the path-aware
  `/.well-known/oauth-protected-resource/mcp`, both advertising
  `scopes_supported: ["favcircles:read", "favcircles:write"]`. 401s carry the
  RFC 9728 `WWW-Authenticate` challenge. RFC 8707 `resource` binding accepted
  in both origin and `/mcp` forms.
- **Login page** at `/authorize` supports email/password, Google, and Facebook
  sign-in. (Apple sign-in not available on web yet — reviewer credentials must
  be an email/password account.)
- **Widgets**: none (optional per OpenAI docs; text + structured content only).
  Can be added later — note that adding UI resources requires a new version
  through review.

Test suites (all passing against production):
`worker/scripts/http-smoke.cjs`, `oauth-flow-test.cjs`, `phase4-security-test.cjs`.
Run with `MCP_URL=https://mcp.favcircles.com/mcp FAVCIRCLES_TOKEN=$(node scripts/mint-token.cjs) node worker/scripts/http-smoke.cjs` from `mcp-server/`.

---

## Manual steps to publish

### 1. Upload the Terms of Service page (required)

`website/terms.html` was created (matches privacy.html styling) but the
favcircles.com site is on Apache hosting — **upload it the same way
privacy.html was uploaded**, so `https://favcircles.com/terms.html` resolves.
Privacy policy already live at `https://favcircles.com/privacy.html`.

Guideline note: OpenAI requires the privacy policy to enumerate data
categories, purposes, and retention. The current privacy.html covers these at
a high level; consider adding an explicit "Connected AI assistants" paragraph
(mirroring terms.html §7) before submission.

### 2. OpenAI Platform org verification (required)

- platform.openai.com → your organization → complete **individual or business
  verification**. Submission requires a verified org and Owner role (or
  `api.apps.write`).

### 3. Create a reviewer demo account (required)

OpenAI reviewers need credentials that work **without MFA/SMS/VPN**:

- Create a fresh FavCircles account with **email + password** (social logins
  won't work for reviewers), e.g. `chatgpt-review@favcircles.com`.
- Seed it with sample data: 3–5 circles (e.g. "Date Night", "Coffee", "NYC
  Trip") with a handful of places each, and connect it to at least one other
  seeded account so `list_connections` / `get_network_recommendations` /
  `find_shared_favorites` return real results.

### 4. Test in ChatGPT developer mode (before submitting)

1. ChatGPT → Settings → **Security and login** → enable Developer mode.
2. Settings → Plugins (chatgpt.com/plugins) → create a dev app with server URL
   `https://mcp.favcircles.com/mcp` and OAuth (it discovers everything from
   the well-known endpoints; no client pre-registration needed — DCR/CIMD).
3. Link the account through the FavCircles login page, then run the golden
   prompts below on desktop **and** mobile. Use "Refresh" after any redeploy.

Golden test prompts (also submit these as your test prompts):
- "What circles do I have in FavCircles?"
- "Find coffee places I've saved"
- "What restaurants do my friends recommend near [city]?"
- "Which places do [friend name] and I both like?"
- "Create a circle called Weekend Trip and add [place] to it"
- "What's new in my FavCircles network?"
- "Tell my network about [place] — post a suggestion"
- "Find [person name] on FavCircles and send them a connection request"

### 5. App metadata (copy-ready)

| Field | Value |
|---|---|
| App name | FavCircles |
| Category | Lifestyle |
| Short description | Trusted place recommendations from people you know. |
| Long description | FavCircles helps you discover places and experiences through people you trust. Save your favorites, organize them into circles, and use AI to find recommendations from your personal network — your friends' favorite restaurants, coffee shops, and hidden gems, not anonymous internet reviews. |
| Website | https://favcircles.com |
| Privacy policy | https://favcircles.com/privacy.html |
| Terms of service | https://favcircles.com/terms.html |
| Support email | wesley@favcircles.com |
| MCP server URL | https://mcp.favcircles.com/mcp |
| Auth | OAuth 2.1 (discovered via well-known endpoints; DCR + CIMD supported) |

Assets:
- **App icon 64×64 px, under 5 KB**: ready at `Marketing/chatgpt-app-icon-64.png`
  (2.6 KB PNG8, derived from `Circles-App-Icon.png`).
- Screenshots of the app in ChatGPT (take during developer-mode testing).

### 6. Submit

- platform.openai.com/plugins → new submission: server URL, OAuth details,
  metadata, assets, reviewer credentials (from step 3), test prompts with
  expected responses, country availability.
- Tool names/schemas/annotations are auto-scanned and snapshotted at
  submission. Fixing handler logic server-side later is fine; **adding,
  renaming, or re-schema-ing tools requires a new version through review.**
- After approval, apps are discoverable via search/direct link; featured
  directory placement is selective and can't be requested.

### Known constraints / gotchas

- No digital-goods monetization in-app (FavCircles premium must stay in the
  iOS app; don't mention in-ChatGPT purchase).
- Ages 13+: consistent with the app's existing policy.
- The OAuth login page only supports password + Google + Facebook accounts;
  Apple-sign-in users can't link yet (app-side connect flow is future work).
- Server-only deploys (`cd mcp-server/worker && npx wrangler deploy`) don't
  require re-review as long as the tool surface is unchanged.
