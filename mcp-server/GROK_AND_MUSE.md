# FavCircles in Grok, Meta Muse, and Sign in with Apple on the connect page

Written 2026-11-22. The connector is the same everywhere:

- Full server (OAuth sign-in): `https://mcp.favcircles.com/mcp`
- No-login information only: `https://mcp.favcircles.com/public/mcp`
  (`about_favcircles`, `getting_started`, `widgets_overview`, `for_store_owners`)

## Grok

**Verified from xAI's docs** ([docs.x.ai/grok/connectors](https://docs.x.ai/grok/connectors),
[x.ai/news/grok-connectors](https://x.ai/news/grok-connectors)): since May 2026 Grok can add any
public MCP server as a custom connector. Grok supports Streamable HTTP over HTTPS, which is what
we serve.

Steps (needs a paid Grok plan; sources disagree on whether it's SuperGrok only or any paid plan):

1. Open grok.com/connectors → **New Connector** → **Custom**.
2. Paste `https://mcp.favcircles.com/mcp`.
3. Grok opens the FavCircles connect page: sign in, or tap **Create an account**.
4. Try: "What is FavCircles?", "save Driftwood Coffee House to a circle called Coffee",
   "what do my friends recommend near me?".

Grok Business/Enterprise: a team admin adds it under the team's connectors page (Other → URL);
an admin policy or MCP allowlist can block it.

**Unverified:** whether Grok's custom connectors complete our OAuth flow (DCR at `/register`,
or CIMD) without changes. Test it once Wes has a paid Grok plan; if it fails, capture the error on
the connect page and the Worker logs (`npx wrangler tail` in `mcp-server/worker`).

## Meta Muse

What the reports say (secondary sources, September 2026: TechCrunch, Social Media Today, Unite.AI):

- The consumer Muse app has **no "add a custom MCP URL" setting**. It uses Meta's connector
  catalog.
- Meta opened the catalog to outside developers in September 2026: developers submit a connector
  through Meta's developer portal and it's listed after Meta's review.
- Muse Code (the developer tool) accepts MCP servers declared in a settings file.
- A Zapier connector exists in Muse, so a Zapier MCP route is possible but indirect.

**Unverified:** the portal's exact name and URL, what it requires (MCP vs Meta's own connector
API, OAuth requirements, review time), and whether it needs a Meta business account. Next step for
Wes: in Meta's developer site (developers.facebook.com), look for Muse / connectors, or ask Muse
"how do I submit a connector?". Once the requirements are known, we fill in the submission:
connector URL above, OAuth (DCR + CIMD already served), privacy policy
https://favcircles.com/privacy.html, terms https://favcircles.com/terms.html, icon
`Marketing/claude-connector-icon-512.png`, and a reviewer test account.

## Sign in with Apple on the connect page (built, switched off)

The connect page already has Google, Facebook, email sign-in and **Create an account**. The Apple
button is in the code but hidden until these exist (Apple ties the web flow to a Services ID):

1. Apple Developer → Certificates, Identifiers & Profiles → Identifiers → **+** → **Services IDs**.
   Description "FavCircles web sign-in", identifier e.g. `com.favcircles.circles.web`.
2. Enable **Sign in with Apple** on it → Configure: primary App ID `com.favcircles.circles`,
   domain `mcp.favcircles.com`, return URL `https://mcp.favcircles.com/authorize`. Save.
3. Backend: add the identifier to `APPLE_AUDIENCES` on Cloud Run (the token's `aud` will be the
   Services ID; `services/socialIdentity.js` reads extra audiences from that env var).
4. Worker: `cd mcp-server/worker && npx wrangler secret put APPLE_SERVICES_ID` (the identifier).
   The button appears on the next page load. Same Apple team → same Apple user id as the app, so
   people land in their existing account.
