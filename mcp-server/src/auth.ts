/**
 * Token validation (Phase 2 of MCP_HANDOFF.md).
 *
 * FavCircles auth is the backend's own HS256 JWTs (signed with JWT_SECRET,
 * payload {uid, email}) — a shared symmetric secret, not a JWKS provider.
 * This module validates tokens with `jose` before any backend call:
 *   - signature (HS256, same JWT_SECRET the backend uses)
 *   - expiry
 *   - audience (RFC 8707): tokens for this MCP server must carry
 *     aud = MCP_AUDIENCE (default "favcircles-mcp")
 *
 * The validated token is then forwarded to the backend, which re-verifies and
 * scopes every query to the token's uid — defense in depth. This module is
 * transport-agnostic on purpose: in Phase 3 the Cloudflare Worker calls the
 * same verifyToken() with the per-request Authorization header.
 */

import { jwtVerify, errors as joseErrors } from "jose";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

export const MCP_AUDIENCE = process.env.MCP_AUDIENCE || "favcircles-mcp";

export interface AuthInfo {
  /** The FavCircles user id (Firestore users doc id) the token is bound to. */
  userId: string;
  email?: string;
  /** The raw bearer token, forwarded to the backend on every call. */
  token: string;
}

export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuthError";
  }
}

let cachedSecret: Uint8Array | null = null;

/**
 * Resolve the shared JWT secret. Prefers FAVCIRCLES_JWT_SECRET; falls back to
 * parsing backend/.env locally so the secret never has to live in MCP client
 * config. Never logged.
 */
function getSecret(): Uint8Array {
  if (cachedSecret) return cachedSecret;

  let secret = process.env.FAVCIRCLES_JWT_SECRET;
  if (!secret) {
    try {
      const here = path.dirname(fileURLToPath(import.meta.url)); // dist/
      const envFile = readFileSync(path.join(here, "../../backend/.env"), "utf8");
      const match = envFile.match(/^JWT_SECRET=(.+)$/m);
      if (match) secret = match[1].trim().replace(/^["']|["']$/g, "");
    } catch {
      /* backend/.env not available (e.g. deployed Worker) — env var required */
    }
  }
  if (!secret) {
    throw new AuthError("No JWT secret available: set FAVCIRCLES_JWT_SECRET (or run next to backend/.env).");
  }
  cachedSecret = new TextEncoder().encode(secret);
  return cachedSecret;
}

/**
 * Validate a bearer token and return the authenticated user.
 * Throws AuthError with a client-safe message on any failure.
 */
export async function verifyToken(token: string | undefined): Promise<AuthInfo> {
  if (!token) {
    throw new AuthError("No bearer token provided. Mint one with scripts/mint-token.cjs and re-register.");
  }

  try {
    const { payload } = await jwtVerify(token, getSecret(), {
      algorithms: ["HS256"],
      audience: MCP_AUDIENCE,
    });

    const userId = typeof payload.uid === "string" ? payload.uid : undefined;
    if (!userId) {
      throw new AuthError("Token is valid but has no uid claim — not a FavCircles user token.");
    }
    return {
      userId,
      email: typeof payload.email === "string" ? payload.email : undefined,
      token,
    };
  } catch (e) {
    if (e instanceof AuthError) throw e;
    if (e instanceof joseErrors.JWTExpired) {
      throw new AuthError("Token expired — mint a fresh one with scripts/mint-token.cjs and re-register.");
    }
    if (e instanceof joseErrors.JWTClaimValidationFailed && e.claim === "aud") {
      throw new AuthError(
        `Token audience mismatch — this server only accepts tokens minted for aud "${MCP_AUDIENCE}" (RFC 8707).`
      );
    }
    if (e instanceof joseErrors.JWSSignatureVerificationFailed) {
      throw new AuthError("Token signature is invalid — not signed by the FavCircles auth secret.");
    }
    throw new AuthError(`Token validation failed: ${e instanceof Error ? e.message : String(e)}`);
  }
}
