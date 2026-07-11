# FavCircles — MCP Server Handoff Brief

> Paste this file into the FavCircles repo root (or save as `CLAUDE.md`) and tell Claude Code:
> "Read MCP_HANDOFF.md and let's build the FavCircles MCP server. Start at Phase 1."

---

## Goal

Expose the FavCircles backend/data via a **remote MCP server** so a user can connect FavCircles to Claude (or any MCP client) and interface with **their own** data through natural language.

The iOS app is a *client* and cannot accept inbound AI connections. What we expose is a hosted MCP server that wraps the existing FavCircles backend API and acts per-user via OAuth.

## Chosen approach (fastest path for this infra)

Deploy the MCP server as a **Cloudflare Worker** using the `agents` SDK (`McpAgent`) with Cloudflare's OAuth provider.

Why: `favcircles.com` DNS is already on Cloudflare (free plan), so hosting + TLS + the `mcp.favcircles.com` route are one-step. The existing web/app backend stays on GoDaddy — the Worker is a thin layer that calls the existing API and validates the calling user's token.

### Current infrastructure (from Cloudflare DNS panel, confirmed by user)
- Registrar/DNS: **Cloudflare** (zone `favcircles.com`, free plan, DNS Setup: Full)
- Web/app hosting: **GoDaddy** webserver at `107.180.50.217`
- Existing records:
  - `favcircles.com` A → `107.180.50.217` (DNS only)
  - `mail.favcircles.com` A → `107.180.50.217` (DNS only)
  - `api.favcircles.com` CNAME → `ghs.googlehosted.com` (DNS only)  ⚠️ verify: is the real backend API here or on the GoDaddy box?
  - `app.favcircles.com` CNAME → `ghs.googlehosted.com` (DNS only)
- **Action for Claude Code:** confirm the actual backend API base URL and auth mechanism before wiring tools. The `ghs.googlehosted.com` CNAMEs suggest some subdomains are on Google hosting — clarify with the user which host serves the data API.

## Transport & spec decisions (already made)
- Transport: **Streamable HTTP** (single endpoint). Do NOT use the deprecated HTTP+SSE transport (being sunset in 2026).
- Auth: **OAuth 2.1 + PKCE**, server acts as an OAuth 2.1 Resource Server.
  - Serve `/.well-known/oauth-protected-resource` (RFC 9728).
  - Validate the bearer token on **every** tool call, including the `aud` claim (RFC 8707).
  - Scope every backend query to the authenticated user id from the token.
  - If Dynamic Client Registration is enabled, strictly validate `redirect_uri`.
- Reuse existing FavCircles auth (whatever the app uses) — the Worker should *validate* tokens, not reinvent login, if feasible.

---

## Build phases

### Phase 1 — Prove the tool loop locally (no auth, stdio)
Fastest iteration. Stand up a minimal MCP server with 3–5 tools that call the FavCircles backend, run it over stdio, and test in Claude Code.

Starter tool list (adjust to real API):
- `list_circles` — list the user's circles
- `get_circle` — fetch one circle's items ({ circleId })
- `add_to_circle` — add an item ({ circleId, item })
- `search` — search across the user's data ({ query })
- `create_circle` — ({ name })

Register locally:
```bash
claude mcp add favcircles -- node ./dist/server.js
# then /mcp inside Claude Code to confirm tools appear; try "list my circles"
```

### Phase 2 — Add token validation
Wrap backend calls so each tool reads the user id from a validated token. Use a JWT/JWKS validation lib (e.g. `jose`) against the existing FavCircles auth provider. Enforce `aud`.

### Phase 3 — Cloudflare Worker + Streamable HTTP + deploy
- Scaffold with the Cloudflare remote-MCP template (`agents` SDK `McpAgent` + `workers-oauth-provider`), or run the SDK's `StreamableHTTPServerTransport` behind the Worker fetch handler.
- Wrangler deploy.
- Add DNS/route in Cloudflare: `mcp.favcircles.com` → Worker route. (Cloudflare-managed, so proxied + TLS automatic.)
- Serve the OAuth protected-resource metadata document.

Register as remote server:
```bash
claude mcp add --transport http favcircles https://mcp.favcircles.com/mcp
```

### Phase 4 — Verify
- Confirm token for user A cannot read user B's data.
- Confirm `aud` rejection of a foreign-audience token.
- Confirm HTTPS-only and `redirect_uri` validation.
- End-to-end: connect from the Claude app, run each tool.

## Minimal server sketch (SDK, adapt to Workers)
```ts
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

const server = new McpServer({ name: "favcircles", version: "1.0.0" });

server.tool("list_circles", "List the current user's circles", {}, async (_a, { authInfo }) => {
  const circles = await backend.getCircles(authInfo.subject);
  return { content: [{ type: "text", text: JSON.stringify(circles) }] };
});

server.tool("add_to_circle", "Add an item to a circle",
  { circleId: z.string(), item: z.string() },
  async ({ circleId, item }, { authInfo }) => {
    await backend.addItem(authInfo.subject, circleId, item);
    return { content: [{ type: "text", text: "Added." }] };
  });
```

## Open questions for the user (resolve in Phase 1)
1. What is the real backend API base URL and its auth scheme (JWT? session? API key)?
2. What language/runtime is the existing backend — anything to reuse, or is the Worker calling it purely over HTTP?
3. Confirm the `api.` / `app.` Google-hosted CNAMEs vs. the GoDaddy box: where does the data API actually live?

## Reference links
- TypeScript SDK: https://github.com/modelcontextprotocol/typescript-sdk
- SDK server docs: https://github.com/modelcontextprotocol/typescript-sdk/blob/main/docs/server.md
- OAuth 2.1 + Streamable HTTP tutorial: https://nerdleveltech.com/mcp-server-typescript-oauth-streamable-http-production-tutorial
- Build Remote MCP with Authorization: https://loginov-rocks.medium.com/build-remote-mcp-with-authorization-a2f394c669a8
- Hosting MCP servers guide: https://render.com/articles/building-and-hosting-mcp-servers-a-complete-guide
