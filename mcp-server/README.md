# FavCircles MCP Server

MCP server exposing FavCircles circles and places, per `../MCP_HANDOFF.md`.

**Status: Phase 4 complete** — deployed as a Cloudflare Worker at **`https://mcp.favcircles.com/mcp`** (Streamable HTTP). Two auth paths:

1. **Pre-issued FavCircles JWT** (dev tooling): HS256 + expiry + RFC 8707 `aud` validation per request, token forwarded to the backend which re-verifies and scopes.
2. **OAuth 2.1 + PKCE** (Claude apps): `workers-oauth-provider` acts as the authorization server — Dynamic Client Registration at `/register` (exact `redirect_uri` matching), `/authorize` renders a FavCircles login page (bridged to the backend's `/auth/login` — passwords are never stored), `/token` issues provider tokens backed by `OAUTH_KV`. Each API call mints a 15-minute backend JWT for the granted user; OAuth access tokens never reach the backend.

Verified by test suites (all green): cross-user isolation (synthetic user cannot see/read/write another user's private circle), foreign-`aud` rejection, HTTPS-only, DCR + `redirect_uri` validation, PKCE metadata, bad-credential rejection, fake-token 401s with RFC 9728 `WWW-Authenticate` pointers.

**Sign-in options on the OAuth page:** email/password (backend `/auth/login`), **Google** (Firebase Web SDK popup → Firebase ID token → backend `/auth/firebase`, same Firebase uid as the iOS app), and **Facebook** (Facebook JS SDK → FB access token → backend `/auth/firebase` Graph path, same `fb_<id>` account as iOS — deliberately *not* the Firebase Facebook provider, which would create a different account). Apple sign-in is not supported on the web page yet (needs an Apple Services ID).

External configuration the social buttons depend on:
- **Google**: `mcp.favcircles.com` must be in the Firebase project's Auth **authorized domains** (Identity Toolkit `admin/v2 config.authorizedDomains`, or Firebase Console → Authentication → Settings).
- **Facebook**: `mcp.favcircles.com` must be added to the Facebook app (id `971348948407685`) — App Domains + a Website platform entry (developers.facebook.com → App settings → Basic).
- `FIREBASE_WEB_API_KEY` wrangler secret (the public Firebase client key; secret only to keep it out of the repo).

**Connect from Claude apps:** add a custom connector with URL `https://mcp.favcircles.com/mcp` — the client discovers the authorization server via RFC 9728 metadata, registers itself, and shows the FavCircles sign-in page. The stdio server remains for local development.

## Layout

- `src/` + `scripts/` — local stdio server (Phases 1–2), still useful for offline dev
- `worker/` — the deployed remote server (Phase 3): Cloudflare Worker using the `agents` SDK's stateless `createMcpHandler`; tools are built per request and close over the validated user

## Remote server (production)

```bash
cd worker
npm install --ignore-scripts        # --ignore-scripts: skips a native build in an unused optional dep
npm run typecheck
npx wrangler dev                    # local: secrets from .dev.vars (gitignored)
MCP_URL=http://localhost:8787/mcp FAVCIRCLES_TOKEN=$(node ../scripts/mint-token.cjs) npm run smoke
npx wrangler deploy                 # deploys + owns the mcp.favcircles.com custom domain
```

- Secret: `npx wrangler secret put FAVCIRCLES_JWT_SECRET` (the backend's `JWT_SECRET`)
- The Worker calls Cloud Run directly (`FAVCIRCLES_API` var) — fetching `api.favcircles.com` from inside its own zone loops on Google's https redirect
- `/.well-known/oauth-protected-resource` serves RFC 9728 metadata; 401s carry `WWW-Authenticate` pointing at it
- Register in Claude Code: `claude mcp add --scope user --transport http favcircles https://mcp.favcircles.com/mcp --header "Authorization: Bearer $(node scripts/mint-token.cjs)"`

## Tools

| Tool | What it does |
|---|---|
| `list_circles` | List the user's circles (name, id, category, privacy, place count) |
| `get_circle` | One circle's details + all its places (`circleId`) |
| `create_circle` | Create a circle (`name`, optional description/category/privacy) |
| `update_circle` | Edit a circle's name/description/category/privacy (owner or editor only) |
| `delete_circle` | Move the circle and its places to the user's **trash** (requires `confirm: true`). Owner only. |
| `add_place` | Add a place to a circle (`circleId`, `name`, `address`, `category`, `latitude`, `longitude`, optional `notes`) |
| `update_place` | Edit a place's name/address/category/notes |
| `delete_place` | Move a place to the user's trash |
| `search_places` | Case-insensitive search across all places in the user's circles (`query`) |
| `list_trash` | Show deleted circles and individually deleted places |
| `restore_circle` | Bring a deleted circle back, including the places deleted with it |
| `restore_place` | Bring an individually deleted place back into its circle |
| `permanently_delete_circle` | Irreversibly erase a trashed circle + its places (requires `confirm: true`) |
| `permanently_delete_place` | Irreversibly erase a trashed place (requires `confirm: true`) |

**Trash model** (backend `/api/trash`, `controllers/trashController.js`): deleting a circle moves its doc to the `deletedCircles` collection and marks its places `deletedAt` + `deletedViaCircleDelete` — because the doc leaves the `circles` collection, every existing backend/iOS query stops seeing it with zero filter changes. Deleting a place sets `deletedAt` (pre-existing behavior) and pulls it from the circle's `places` array; restore reverses both. Data is retained per-user until permanently deleted. Restoring a place whose circle is itself in the trash returns 409 with a pointer to `restore_circle`.

All mutations are authorized by the backend against the token's user — the isolation suites verify another user cannot read, edit, delete, restore, or permanently delete your data even with `confirm: true`.

## Auth (Phase 2)

FavCircles auth is the backend's own HS256 JWT (signed with `JWT_SECRET`, payload `{uid, email}` — not a Firebase ID token, and symmetric — so `jose` validates against the shared secret rather than a JWKS endpoint).

Every tool call runs `verifyToken()` (`src/auth.ts`) **before** touching the backend:

- **signature** — HS256 against the same `JWT_SECRET` the backend uses (from `FAVCIRCLES_JWT_SECRET`, falling back to parsing `../backend/.env` locally)
- **expiry**
- **audience** — tokens must carry `aud: "favcircles-mcp"` (`MCP_AUDIENCE` to override). Legacy app tokens without the claim are refused (RFC 8707).

The user id comes from the *validated* token, and the token is then forwarded to the backend, whose `protect` middleware re-verifies and scopes every query to that user (defense in depth). On stdio the token arrives via `FAVCIRCLES_TOKEN`; the Phase 3 Worker will feed each request's `Authorization` header into the same `verifyToken()` seam.

Mint a dev token (requires `../backend/.env` and the Firebase service account):

```bash
node scripts/mint-token.cjs        # bare token on stdout; MINT_EMAIL / MINT_TTL / MINT_AUD to override
```

The backend's `jwt.verify` ignores extra claims, so `aud`-bearing tokens work against the API unchanged.

## Build, test, register

```bash
npm install && npm run build
npm run test:auth                                               # verifyToken unit tests (aud/expiry/signature)
FAVCIRCLES_TOKEN=$(node scripts/mint-token.cjs) npm run smoke   # stdio JSON-RPC smoke test vs live backend

claude mcp add --scope user favcircles \
  --env FAVCIRCLES_TOKEN=$(node scripts/mint-token.cjs) \
  -- node "$(pwd)/dist/server.js"
```

Then `/mcp` inside Claude Code should show `favcircles` with 5 tools ("list my circles", etc.).

## Implementation notes

- SDK: `@modelcontextprotocol/sdk` 1.x (stable), `registerTool` + zod raw shapes, `StdioServerTransport`. stdout is the JSON-RPC channel — diagnostics use `console.error` only.
- `get_circle`/`search_places` use `POST /api/places/batch` (the legacy `GET /circles/:id/places` route is not mounted on the deployed backend). The batch endpoint caps at 50 circleIds per request, so `backend.ts` chunks.
- Place creation requires `location.coordinates` `[lng, lat]` — hence the required lat/lng tool params.
- Category/privacy enums mirror `backend/models/FirestoreModels.js` validators.

## Test suites

```bash
npm run test:auth                                   # local: verifyToken unit tests
FAVCIRCLES_TOKEN=$(node scripts/mint-token.cjs) npm run smoke          # stdio server
cd worker
MCP_URL=https://mcp.favcircles.com/mcp FAVCIRCLES_TOKEN=... npm run smoke   # remote transport + 401s
node scripts/phase4-security-test.cjs               # isolation / foreign-aud / HTTPS (creates+removes synthetic user)
BASE=https://mcp.favcircles.com node scripts/oauth-flow-test.cjs            # AS metadata / DCR / redirect_uri / PKCE
node scripts/social-oauth-e2e.cjs                   # FULL OAuth flow with a real Firebase ID token (no browser/password)
```

## Future work

- App-side connect flow so social-sign-in users (Google/Facebook/Apple) can authorize MCP clients.
- Token/grant management UI (revocation currently means rotating the JWT secret or deleting grants in KV).
