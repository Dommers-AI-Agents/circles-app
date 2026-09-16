// backend/services/widgetDataService.js
//
// Generic per-user, per-widget JSON document store for the Widgets tab.
// The server never knows a widget's schema: the payload is an opaque JSON
// string that is parsed exactly once (to reject non-JSON / non-object top
// levels) and stored as a string. A string, not a map, because Firestore
// maps reject '.'/'__' keys and nested arrays, index every field, and can't
// be byte-capped in one call.
//
// Doc id = `${uid}_${widgetId}` so every read is a by-id fetch (no query, no
// composite index). `version` is an optimistic lock: the client sends the
// version it last saw, the server bumps it on every write, and a mismatch
// hands back the current document so the client can merge.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

// Covers plain ids (`water`, `prefs`) and month shards (`calories_2026-09`).
const WIDGET_ID_RE = /^[a-z][a-z0-9_-]{1,47}$/;
const WIDGET_PAYLOAD_MAX_BYTES = 200 * 1024; // well under Firestore's 1 MiB doc cap
const MAX_BATCH_IDS = 30;

class ValidationError extends Error {
  constructor(status, code, message) {
    super(message || code);
    this.name = 'ValidationError';
    this.status = status;
    this.code = code;
  }
}

class VersionConflictError extends Error {
  constructor(current) {
    super('Widget document version conflict');
    this.name = 'VersionConflictError';
    this.status = 409;
    this.code = 'VERSION_CONFLICT';
    this.current = current;
  }
}

/**
 * A client running an older schema tried to overwrite a document written by a
 * newer one.
 *
 * Widget payloads are plain Codable structs, so a client decoding a document
 * it doesn't fully understand silently drops the fields it has never heard of.
 * If we then let it save, those fields are gone from the server for good — not
 * a conflict, not a merge, just deletion by a build that shipped months ago.
 *
 * This must be enforced here rather than on the device, because the clients
 * that cause the damage are already in people's hands and cannot be fixed.
 */
class SchemaTooOldError extends Error {
  constructor(current, storedSchema, incomingSchema) {
    super('Widget document was written by a newer version of the app');
    this.name = 'SchemaTooOldError';
    this.status = 409;
    this.code = 'SCHEMA_TOO_OLD';
    this.current = current;
    this.storedSchema = storedSchema;
    this.incomingSchema = incomingSchema;
  }
}

const docIdFor = (userId, widgetId) => `${userId}_${widgetId}`;

function assertWidgetId(widgetId) {
  if (typeof widgetId !== 'string' || !WIDGET_ID_RE.test(widgetId)) {
    throw new ValidationError(400, 'invalid_widget_id', 'Invalid widget id');
  }
  return widgetId;
}

function assertVersion(version) {
  if (!Number.isInteger(version) || version < 0) {
    throw new ValidationError(400, 'invalid_version', 'version must be a non-negative integer');
  }
  return version;
}

// Byte cap first (cheap), parse second, then the top-level shape. Returns
// the trimmed string plus its byte size so callers never re-measure.
function normalizePayload(payload) {
  if (typeof payload !== 'string') {
    throw new ValidationError(400, 'invalid_payload', 'payload must be a JSON string');
  }
  const bytes = Buffer.byteLength(payload, 'utf8');
  if (bytes > WIDGET_PAYLOAD_MAX_BYTES) {
    throw new ValidationError(413, 'payload_too_large',
      `payload exceeds ${WIDGET_PAYLOAD_MAX_BYTES} bytes`);
  }
  let parsed;
  try {
    parsed = JSON.parse(payload);
  } catch (_) {
    throw new ValidationError(400, 'invalid_payload', 'payload is not valid JSON');
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new ValidationError(400, 'invalid_payload', 'payload must be a JSON object');
  }
  return { payload, bytes };
}

// Client shape: no userId (the caller is the owner) and no payloadBytes.
function toClientDoc(data) {
  if (!data) return null;
  return {
    widgetId: data.widgetId,
    version: data.version,
    payload: data.payload,
    schemaVersion: data.schemaVersion ?? null,
    createdAt: data.createdAt || null,
    updatedAt: data.updatedAt || null
  };
}

class WidgetDataService {
  get db() { return getFirestore(); }

  ref(userId, widgetId) {
    return this.db.collection(COLLECTIONS.WIDGET_DATA).doc(docIdFor(userId, widgetId));
  }

  // Batch read for the tab's hot set (settings + current shards) in one
  // round-trip. Only the caller's own docs are reachable because the id is
  // composed server-side from req.user.uid.
  async getMany(userId, ids) {
    const unique = [...new Set(ids)];
    if (unique.length > MAX_BATCH_IDS) {
      throw new ValidationError(400, 'too_many_ids', `At most ${MAX_BATCH_IDS} ids per request`);
    }
    unique.forEach(assertWidgetId);
    if (unique.length === 0) return []; // getAll() throws on zero refs
    const refs = unique.map(id => this.ref(userId, id));
    const snaps = await this.db.getAll(...refs);
    return snaps.filter(s => s.exists).map(s => toClientDoc(s.data()));
  }

  async get(userId, widgetId) {
    assertWidgetId(widgetId);
    const snap = await this.ref(userId, widgetId).get();
    return snap.exists ? toClientDoc(snap.data()) : null;
  }

  // Optimistic-lock write. Throwing inside runTransaction aborts it, so a
  // stale version never touches the store. Returns the previous updatedAt
  // alongside the doc so the controller can decide "first save today"
  // without a second read.
  async save(userId, widgetId, { version, payload, schemaVersion }) {
    assertWidgetId(widgetId);
    assertVersion(version);
    const normalized = normalizePayload(payload);
    const schema = Number.isInteger(schemaVersion) ? schemaVersion : null;
    const ref = this.ref(userId, widgetId);

    return this.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const stored = snap.exists ? snap.data() : null;
      const storedVersion = stored ? (stored.version || 0) : 0;
      if (storedVersion !== version) {
        throw new VersionConflictError(toClientDoc(stored));
      }
      // Refuse a downgrade. Documents written before schemaVersion existed
      // carry null and stay permissive, and an unversioned client can still
      // write to an unversioned document — only a known-older schema writing
      // over a known-newer one is blocked.
      const storedSchema = stored ? stored.schemaVersion : null;
      if (Number.isInteger(storedSchema) && Number.isInteger(schema) && schema < storedSchema) {
        throw new SchemaTooOldError(toClientDoc(stored), storedSchema, schema);
      }
      const now = new Date().toISOString();
      const next = {
        userId,
        widgetId,
        version: storedVersion + 1,
        payload: normalized.payload,
        payloadBytes: normalized.bytes,
        schemaVersion: schema ?? (stored ? stored.schemaVersion ?? null : null),
        createdAt: stored ? stored.createdAt : now,
        updatedAt: now
      };
      tx.set(ref, next);
      return {
        document: toClientDoc(next),
        created: !stored,
        previousUpdatedAt: stored ? stored.updatedAt || null : null
      };
    });
  }

  async remove(userId, widgetId) {
    assertWidgetId(widgetId);
    await this.ref(userId, widgetId).delete();
  }
}

module.exports = new WidgetDataService();
module.exports.WidgetDataService = WidgetDataService;
module.exports.ValidationError = ValidationError;
module.exports.VersionConflictError = VersionConflictError;
module.exports.SchemaTooOldError = SchemaTooOldError;
module.exports.normalizePayload = normalizePayload;
module.exports.toClientDoc = toClientDoc;
module.exports.WIDGET_ID_RE = WIDGET_ID_RE;
module.exports.WIDGET_PAYLOAD_MAX_BYTES = WIDGET_PAYLOAD_MAX_BYTES;
module.exports.MAX_BATCH_IDS = MAX_BATCH_IDS;
