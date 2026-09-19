// backend/utils/ids.js — ids and timestamps the services stamp on rows.
const crypto = require('crypto');

/** 12 url-safe chars from 72 random bits: collision-safe, not guessable. */
const newId = () => crypto.randomBytes(9).toString('base64url');
const nowIso = () => new Date().toISOString();

module.exports = { newId, nowIso };
