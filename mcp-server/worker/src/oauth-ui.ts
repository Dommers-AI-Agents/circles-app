/**
 * OAuth 2.1 authorization UI — the defaultHandler for workers-oauth-provider.
 *
 * Three sign-in paths, all bridged to existing FavCircles auth (we never
 * store credentials; the library enforces PKCE + exact redirect_uri matching):
 *   - Email/password  -> backend POST /auth/login
 *   - Google          -> Firebase Web SDK popup -> Firebase ID token
 *                        -> backend POST /auth/firebase (same account as iOS,
 *                        keyed by Firebase uid)
 *   - Facebook        -> Facebook JS SDK login -> FB access token
 *                        -> backend POST /auth/firebase (Graph API path,
 *                        same fb_<id> account as iOS)
 *
 * Note: the Google popup requires mcp.favcircles.com in the Firebase project's
 * authorized domains; the Facebook button requires the domain in the Facebook
 * app's settings (App Domains + JS SDK allowed domains).
 */

import type { AuthRequest, ClientInfo, OAuthHelpers } from "@cloudflare/workers-oauth-provider";
import { DEFAULT_API_BASE } from "./backend";

interface Env {
  OAUTH_PROVIDER: OAuthHelpers;
  FAVCIRCLES_API?: string;
  FIREBASE_WEB_API_KEY?: string; // public client key (ships in app bundles); wrangler secret to keep it out of the repo
}

const FIREBASE_AUTH_DOMAIN = "circles-app-83b67.firebaseapp.com";
const FIREBASE_PROJECT_ID = "circles-app-83b67";
const FACEBOOK_APP_ID = "971348948407685";

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);
}

function loginPage(oauthReqB64: string, client: ClientInfo | null, env: Env, error?: string): Response {
  const clientName = esc(client?.clientName || "an MCP client");
  const firebaseKey = env.FIREBASE_WEB_API_KEY || "";
  const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Connect to FavCircles</title>
<style>
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f5f6f8;margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center}
  .card{background:#fff;border-radius:16px;box-shadow:0 4px 24px rgba(0,0,0,.08);padding:40px;max-width:380px;width:100%;margin:16px}
  h1{font-size:22px;margin:0 0 4px;color:#1a1a2e}
  p.sub{color:#666;font-size:14px;margin:0 0 20px}
  label{display:block;font-size:13px;font-weight:600;color:#333;margin:14px 0 6px}
  input{width:100%;box-sizing:border-box;padding:11px 12px;border:1px solid #d5d9e0;border-radius:8px;font-size:15px}
  button{width:100%;margin-top:22px;padding:12px;border:0;border-radius:8px;background:#4A90D9;color:#fff;font-size:16px;font-weight:600;cursor:pointer}
  .social{margin-top:0;display:flex;flex-direction:column;gap:10px}
  .social button{margin-top:0;display:flex;align-items:center;justify-content:center;gap:10px;font-size:15px}
  .g{background:#fff;color:#3c4043;border:1px solid #d5d9e0}
  .f{background:#1877F2}
  .divider{display:flex;align-items:center;gap:12px;color:#9aa0a8;font-size:12px;margin:20px 0 4px}
  .divider::before,.divider::after{content:"";flex:1;height:1px;background:#e4e7ec}
  .err{background:#fdecea;color:#b3261e;border-radius:8px;padding:10px 12px;font-size:13px;margin-bottom:6px}
  .note{color:#8a8f98;font-size:12px;margin-top:18px;text-align:center}
</style></head><body>
<div class="card">
  <h1>Connect to FavCircles</h1>
  <p class="sub"><strong>${clientName}</strong> is requesting access to your circles and places.</p>
  ${error ? `<div class="err">${esc(error)}</div>` : ""}
  <div class="social">
    <button type="button" class="g" onclick="googleSignIn()">
      <svg width="18" height="18" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.5 0 6.6 1.2 9 3.5l6.7-6.7C35.6 2.4 30.2 0 24 0 14.6 0 6.5 5.4 2.6 13.2l7.8 6.1C12.3 13.4 17.7 9.5 24 9.5z"/><path fill="#4285F4" d="M46.5 24.5c0-1.6-.1-3.1-.4-4.5H24v9h12.7c-.6 3-2.3 5.5-4.8 7.2l7.5 5.8c4.4-4.1 7.1-10.1 7.1-17.5z"/><path fill="#FBBC05" d="M10.4 28.7A14.5 14.5 0 0 1 9.5 24c0-1.6.3-3.2.8-4.7l-7.8-6.1A24 24 0 0 0 0 24c0 3.9.9 7.5 2.6 10.8l7.8-6.1z"/><path fill="#34A853" d="M24 48c6.2 0 11.4-2 15.2-5.5l-7.5-5.8c-2 1.4-4.7 2.3-7.7 2.3-6.3 0-11.7-3.9-13.6-9.3l-7.8 6.1C6.5 42.6 14.6 48 24 48z"/></svg>
      Continue with Google
    </button>
    <button type="button" class="f" onclick="facebookSignIn()">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="#fff"><path d="M24 12.07C24 5.4 18.63 0 12 0S0 5.4 0 12.07C0 18.1 4.39 23.1 10.13 24v-8.44H7.08v-3.49h3.05V9.41c0-3.02 1.79-4.7 4.53-4.7 1.31 0 2.68.24 2.68.24v2.97h-1.51c-1.49 0-1.95.93-1.95 1.89v2.26h3.32l-.53 3.49h-2.79V24C19.61 23.1 24 18.1 24 12.07z"/></svg>
      Continue with Facebook
    </button>
  </div>
  <div class="divider">or use email</div>
  <form id="authForm" method="POST" action="/authorize">
    <input type="hidden" name="oauthReq" value="${esc(oauthReqB64)}">
    <input type="hidden" name="idToken" id="idToken" value="">
    <label for="email">Email</label>
    <input id="email" name="email" type="email" autocomplete="username">
    <label for="password">Password</label>
    <input id="password" name="password" type="password" autocomplete="current-password">
    <button type="submit">Sign in &amp; allow</button>
  </form>
  <p class="note">Only your FavCircles data is shared. Revoke anytime by changing your password.</p>
</div>
<script src="https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js"></script>
<script src="https://www.gstatic.com/firebasejs/10.14.1/firebase-auth-compat.js"></script>
<script>
  firebase.initializeApp({
    apiKey: ${JSON.stringify(firebaseKey)},
    authDomain: ${JSON.stringify(FIREBASE_AUTH_DOMAIN)},
    projectId: ${JSON.stringify(FIREBASE_PROJECT_ID)}
  });
  function submitWithToken(token) {
    document.getElementById('idToken').value = token;
    document.getElementById('email').removeAttribute('required');
    document.getElementById('password').removeAttribute('required');
    document.getElementById('authForm').submit();
  }
  function showErr(message) { alert(message); }
  function googleSignIn() {
    var provider = new firebase.auth.GoogleAuthProvider();
    firebase.auth().signInWithPopup(provider)
      .then(function (result) { return result.user.getIdToken(); })
      .then(submitWithToken)
      .catch(function (e) { showErr('Google sign-in failed: ' + (e && e.message ? e.message : e)); });
  }
  // Facebook uses its own JS SDK (NOT the Firebase provider) so the account
  // maps to the same fb_<id> user the iOS app creates.
  window.fbAsyncInit = function () {
    FB.init({ appId: ${JSON.stringify(FACEBOOK_APP_ID)}, cookie: false, xfbml: false, version: 'v21.0' });
  };
  function facebookSignIn() {
    if (typeof FB === 'undefined') { showErr('Facebook SDK failed to load.'); return; }
    FB.login(function (response) {
      if (response.authResponse && response.authResponse.accessToken) {
        submitWithToken(response.authResponse.accessToken);
      } else {
        showErr('Facebook sign-in was cancelled.');
      }
    }, { scope: 'email,public_profile' });
  }
</script>
<script async defer src="https://connect.facebook.net/en_US/sdk.js"></script>
</body></html>`;
  return new Response(html, { status: error ? 401 : 200, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

async function handleAuthorizeGet(request: Request, env: Env): Promise<Response> {
  let oauthReq: AuthRequest;
  try {
    oauthReq = await env.OAUTH_PROVIDER.parseAuthRequest(request);
  } catch (e) {
    return new Response(`Invalid authorization request: ${e instanceof Error ? e.message : e}`, { status: 400 });
  }
  const client = await env.OAUTH_PROVIDER.lookupClient(oauthReq.clientId);
  if (!client) return new Response("Unknown client_id.", { status: 400 });
  // The library enforces exact redirect_uri matching at completeAuthorization,
  // but reject obviously-invalid requests before showing a login form.
  if (!client.redirectUris.includes(oauthReq.redirectUri)) {
    return new Response("redirect_uri is not registered for this client.", { status: 400 });
  }
  const b64 = btoa(JSON.stringify(oauthReq));
  return loginPage(b64, client, env);
}

async function handleAuthorizePost(request: Request, env: Env): Promise<Response> {
  const form = await request.formData();
  const oauthReqB64 = String(form.get("oauthReq") || "");
  const idToken = String(form.get("idToken") || "");
  const email = String(form.get("email") || "").trim().toLowerCase();
  const password = String(form.get("password") || "");

  let oauthReq: AuthRequest;
  try {
    oauthReq = JSON.parse(atob(oauthReqB64));
  } catch {
    return new Response("Invalid or missing authorization state — restart the connect flow.", { status: 400 });
  }
  const client = await env.OAUTH_PROVIDER.lookupClient(oauthReq.clientId);
  if (!client || !client.redirectUris.includes(oauthReq.redirectUri)) {
    return new Response("Client/redirect_uri validation failed — restart the connect flow.", { status: 400 });
  }

  // Bridge to existing FavCircles auth. Social sign-ins arrive as an idToken
  // (Firebase ID token from the Google popup, or a Facebook access token) and
  // go to /auth/firebase — the same endpoint the iOS app uses, so accounts
  // match exactly. Email/password goes to /auth/login. Never stored.
  const apiBase = env.FAVCIRCLES_API || DEFAULT_API_BASE;
  let loginRes: Response;
  if (idToken) {
    loginRes = await fetch(`${apiBase}/auth/firebase`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken }),
    });
  } else if (email && password) {
    loginRes = await fetch(`${apiBase}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
  } else {
    return loginPage(oauthReqB64, client, env, "Enter your email and password, or use Google/Facebook.");
  }

  const login: any = await loginRes.json().catch(() => ({}));
  if (!loginRes.ok || !login?.success || !login?.user?._id) {
    const message = idToken
      ? login?.message || "Social sign-in could not be verified — please try again."
      : loginRes.status === 401
        ? "Invalid email or password. (If you signed up with Google or Facebook, use those buttons instead.)"
        : login?.message || "Sign-in failed — please try again.";
    return loginPage(oauthReqB64, client, env, message);
  }

  const userEmail = login.user.email || email || undefined;
  const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({
    request: oauthReq,
    userId: login.user._id,
    metadata: { email: userEmail },
    scope: oauthReq.scope,
    props: { userId: login.user._id, email: userEmail },
  });
  return Response.redirect(redirectTo, 302);
}

export const authDefaultHandler = {
  async fetch(request: Request, env: Env, _ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/authorize" && request.method === "GET") return handleAuthorizeGet(request, env);
    if (url.pathname === "/authorize" && request.method === "POST") return handleAuthorizePost(request, env);
    return Response.json({ error: "not_found" }, { status: 404 });
  },
};
