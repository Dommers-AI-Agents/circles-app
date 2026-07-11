#!/usr/bin/env node

/**
 * Dev-only helper: mints a FavCircles app JWT for local MCP testing.
 *
 * The backend's `protect` middleware verifies its own JWTs (signed with
 * JWT_SECRET), so we sign one directly — same pattern as
 * backend/scripts/test-viewport-endpoint.js. Prints the bare token to stdout
 * (nothing else), so it can be captured:
 *
 *   FAVCIRCLES_TOKEN=$(node scripts/mint-token.cjs)
 *
 * Env overrides: MINT_EMAIL (default sgroiwes@gmail.com), MINT_TTL (default 30d),
 * MINT_AUD (default favcircles-mcp — must match the server's MCP_AUDIENCE).
 * Requires backend/.env (JWT_SECRET) and backend/config/firebase-service-account.json.
 */

const path = require('path');
const { createRequire } = require('module');

// Resolve dependencies from the backend's node_modules (dotenv, firebase-admin, jsonwebtoken)
const backendDir = path.join(__dirname, '../../backend');
const backendRequire = createRequire(path.join(backendDir, 'scripts/_resolver.js'));

backendRequire('dotenv').config({ path: path.join(backendDir, '.env') });
const { initializeApp, cert } = backendRequire('firebase-admin/app');
const { getFirestore } = backendRequire('firebase-admin/firestore');
const jwt = backendRequire('jsonwebtoken');

const EMAIL = (process.env.MINT_EMAIL || 'sgroiwes@gmail.com').toLowerCase();
const TTL = process.env.MINT_TTL || '30d';
const AUD = process.env.MINT_AUD || 'favcircles-mcp';

async function main() {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET missing from backend/.env');

  const serviceAccount = require(path.join(backendDir, 'config/firebase-service-account.json'));
  initializeApp({
    credential: cert(serviceAccount),
    projectId: process.env.FIREBASE_PROJECT_ID || 'circles-app-83b67'
  });
  const db = getFirestore();

  const users = await db.collection('users').where('email', '==', EMAIL).limit(1).get();
  if (users.empty) throw new Error(`No user doc found with email ${EMAIL}`);
  const uid = users.docs[0].id;

  // Bare token on stdout so shell substitution works; status goes to stderr.
  // aud is the MCP resource identifier (RFC 8707); the backend's jwt.verify
  // ignores extra claims, so aud-bearing tokens still work against the API.
  console.error(`Minted ${TTL} token for ${EMAIL} (aud: ${AUD})`);
  console.log(jwt.sign({ uid, email: EMAIL, aud: AUD }, secret, { expiresIn: TTL }));
  process.exit(0);
}

main().catch((err) => {
  console.error('mint-token failed:', err.message);
  process.exit(1);
});
