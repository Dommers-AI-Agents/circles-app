/**
 * FavCircles remote MCP server — Cloudflare Worker (Phases 3–4 of MCP_HANDOFF.md).
 *
 * Transport: Streamable HTTP at /mcp (agents SDK createMcpHandler; the
 * deprecated HTTP+SSE transport is intentionally not served).
 *
 * Two ways to authenticate at /mcp, checked in order:
 *   1. Pre-issued FavCircles JWT (aud = MCP_AUDIENCE) — validated here with
 *      jose, forwarded to the backend which re-verifies and scopes (Phase 2/3
 *      model; used by dev tooling and the smoke tests).
 *   2. OAuth 2.1 + PKCE (Phase 4) — workers-oauth-provider acts as the
 *      authorization server (/authorize, /token, /register with DCR and exact
 *      redirect_uri validation). The /authorize UI bridges FavCircles login.
 *      Provider-issued tokens resolve to props {userId, email}; each API call
 *      then mints a short-lived backend JWT for that user.
 *
 * RFC 9728: /.well-known/oauth-protected-resource advertises this resource and
 * its authorization server; 401s carry a WWW-Authenticate pointer to it.
 * HTTPS-only: plaintext requests are 301-redirected.
 */

import OAuthProvider from "@cloudflare/workers-oauth-provider";
import { createMcpHandler } from "agents/mcp";
import { SignJWT } from "jose";
import { AuthError, AuthInfo, DEFAULT_AUDIENCE, verifyBearer } from "./auth";
import { authDefaultHandler } from "./oauth-ui";
import { buildServer } from "./tools";

interface Env {
  FAVCIRCLES_JWT_SECRET: string; // wrangler secret
  MCP_AUDIENCE?: string;
  FAVCIRCLES_API?: string;
  OAUTH_KV: KVNamespace;
}

/** Scopes advertised to clients (ChatGPT requests scopes_supported by default). */
const SCOPES_SUPPORTED = ["favcircles:read", "favcircles:write"];

function resourceMetadata(origin: string, resource: string): Response {
  return Response.json(
    {
      resource,
      authorization_servers: [origin],
      scopes_supported: SCOPES_SUPPORTED,
      bearer_methods_supported: ["header"],
      resource_name: "FavCircles MCP Server",
      resource_documentation: "https://favcircles.com",
    },
    { headers: { "Access-Control-Allow-Origin": "*", "Cache-Control": "max-age=3600" } }
  );
}

/** The OAuth-token path: props {userId, email} -> short-lived backend JWT -> tools. */
const oauthApiHandler = {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const props = (ctx as any).props as { userId?: string; email?: string } | undefined;
    if (!props?.userId) {
      return Response.json({ error: "invalid_token", error_description: "Grant has no user." }, { status: 401 });
    }
    // Mint a short-lived backend token for this user — the backend re-verifies
    // and scopes every query to it. The OAuth access token itself never
    // reaches the backend.
    const backendToken = await new SignJWT({ uid: props.userId, email: props.email })
      .setProtectedHeader({ alg: "HS256" })
      .setIssuedAt()
      .setExpirationTime("15m")
      .sign(new TextEncoder().encode(env.FAVCIRCLES_JWT_SECRET));

    const auth: AuthInfo = { userId: props.userId, email: props.email, token: backendToken };
    const handler = createMcpHandler(buildServer(auth, env.FAVCIRCLES_API), { route: "/mcp" });
    return handler(request, env, ctx);
  },
};

const oauthProvider = new OAuthProvider({
  apiRoute: "/mcp",
  apiHandler: oauthApiHandler as any,
  defaultHandler: authDefaultHandler as any,
  authorizeEndpoint: "/authorize",
  tokenEndpoint: "/token",
  clientRegistrationEndpoint: "/register",
  scopesSupported: SCOPES_SUPPORTED,
  // CIMD (client_id as an HTTPS metadata URL) — ChatGPT's preferred
  // registration method; DCR at /register remains available for Claude.
  clientIdMetadataDocumentEnabled: true,
  // Clients disagree on the RFC 8707 resource identifier — some bind to the
  // origin, others to the full /mcp URL. Compare origins so both forms work.
  resourceMatchOriginOnly: true,
});

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // HTTPS-only (Phase 4): never serve plaintext — redirect and let HSTS pin it.
    // (Skipped for localhost so `wrangler dev` stays testable over http.)
    // Note: workerd's URL.hostname can include the port — strip it before comparing.
    const host = url.hostname.split(":")[0];
    const isLocalDev = host === "localhost" || host === "127.0.0.1" || host === "::1";
    if (url.protocol === "http:" && !isLocalDev) {
      url.protocol = "https:";
      return Response.redirect(url.toString(), 301);
    }

    // RFC 9728, both discovery forms: origin-level and path-aware (clients that
    // treat the /mcp endpoint itself as the resource probe the suffixed path).
    if (url.pathname === "/.well-known/oauth-protected-resource") {
      return resourceMetadata(url.origin, url.origin);
    }
    if (url.pathname === "/.well-known/oauth-protected-resource/mcp") {
      return resourceMetadata(url.origin, `${url.origin}/mcp`);
    }

    if (url.pathname === "/" || url.pathname === "/health") {
      return Response.json({ ok: true, service: "favcircles-mcp", transport: "streamable-http", endpoint: "/mcp" });
    }

    // Fast path: pre-issued FavCircles JWT with the right audience.
    if (url.pathname === "/mcp") {
      const header = request.headers.get("authorization");
      if (header) {
        try {
          const auth = await verifyBearer(header, env.FAVCIRCLES_JWT_SECRET, env.MCP_AUDIENCE || DEFAULT_AUDIENCE);
          const handler = createMcpHandler(buildServer(auth, env.FAVCIRCLES_API), { route: "/mcp" });
          return handler(request, env, ctx);
        } catch (e) {
          // Not a FavCircles JWT (or invalid) — fall through to the OAuth
          // provider, which validates its own tokens and emits the 401.
          if (!(e instanceof AuthError)) throw e;
        }
      }
    }

    // Everything else: OAuth provider (authorize/token/register + AS metadata
    // + /mcp with provider-issued tokens). Its 401s must point clients at the
    // protected-resource metadata (RFC 9728 §5.1).
    const res = await oauthProvider.fetch(request, env as any, ctx);
    if (res.status === 401 && !res.headers.has("WWW-Authenticate")) {
      const withHeader = new Response(res.body, res);
      withHeader.headers.set(
        "WWW-Authenticate",
        `Bearer resource_metadata="${url.origin}/.well-known/oauth-protected-resource"`
      );
      return withHeader;
    }
    return res;
  },
};
