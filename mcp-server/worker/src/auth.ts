/**
 * Bearer-token validation for the Worker (Phase 3).
 *
 * Same rules as the local server's auth.ts: HS256 signature against the
 * backend's JWT_SECRET, expiry, and RFC 8707 audience enforcement. On Workers
 * the secret comes exclusively from the FAVCIRCLES_JWT_SECRET secret binding —
 * there is no .env fallback.
 */

import { jwtVerify, errors as joseErrors } from "jose";

export const DEFAULT_AUDIENCE = "favcircles-mcp";

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

/**
 * Validate the Authorization header value and return the authenticated user.
 * Throws AuthError with a client-safe message on any failure.
 */
export async function verifyBearer(
  authorizationHeader: string | null,
  secret: string | undefined,
  audience: string
): Promise<AuthInfo> {
  if (!secret) {
    throw new AuthError("Server misconfigured: FAVCIRCLES_JWT_SECRET is not set.");
  }
  const match = authorizationHeader?.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new AuthError("Missing bearer token. Send Authorization: Bearer <token>.");
  }
  const token = match[1].trim();

  try {
    const { payload } = await jwtVerify(token, new TextEncoder().encode(secret), {
      algorithms: ["HS256"],
      audience,
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
      throw new AuthError("Token expired.");
    }
    if (e instanceof joseErrors.JWTClaimValidationFailed && e.claim === "aud") {
      throw new AuthError(`Token audience mismatch — tokens must be minted for aud "${audience}" (RFC 8707).`);
    }
    if (e instanceof joseErrors.JWSSignatureVerificationFailed) {
      throw new AuthError("Token signature is invalid.");
    }
    throw new AuthError(`Token validation failed: ${e instanceof Error ? e.message : String(e)}`);
  }
}
