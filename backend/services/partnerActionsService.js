// backend/services/partnerActionsService.js
//
// Partner action catalog for the place detail screen — server-driven groups of
// external deep links (Delivery / Reserve / Ride) so partners can be added,
// reordered, disabled, or switched to affiliate URLs with a Firestore edit and
// no App Store release (same catalog pattern as notificationTips).
//
// The catalog lives in Firestore (`partnerActions`), one doc per action group:
//   { title, icon (SF Symbol), sheetTitle, categories: [PlaceCategory raw | '*'],
//     order, enabled, providers: [{ id, title, webUrlTemplate,
//     appUrlTemplate?, appScheme?, enabled }] }
//
// Contract with iOS (PartnerActionsService.swift):
// - webUrlTemplate is REQUIRED per provider — a provider added server-side with
//   only a web template works with zero app changes. appUrlTemplate/appScheme
//   are an optional scheme-first fast path and are release-gated by
//   LSApplicationQueriesSchemes.
// - Template variables {name} {address} {city} {lat} {lng} {googlePlaceId} are
//   substituted (URL-encoded) on the client. Seed templates with literal
//   square brackets pre-encoded (%5B/%5D) — raw brackets nil out URL(string:).
//
// Fails closed: any read error returns the last good catalog, or { groups: [] }.

const { getFirestore } = require('../config/firebase');

const db = getFirestore();

const CATALOG_COLLECTION = 'partnerActions';
const CACHE_TTL_MS = 5 * 60 * 1000;

let cached = null;          // { updatedAt, groups }
let cachedAtMs = 0;

function sanitizeProvider(p) {
  if (!p || p.enabled === false) return null;
  if (typeof p.webUrlTemplate !== 'string' || !p.webUrlTemplate.startsWith('http')) return null;
  const out = {
    id: String(p.id || ''),
    title: String(p.title || ''),
    webUrlTemplate: p.webUrlTemplate
  };
  if (!out.id || !out.title) return null;
  if (typeof p.appUrlTemplate === 'string' && p.appUrlTemplate.length > 0) out.appUrlTemplate = p.appUrlTemplate;
  if (typeof p.appScheme === 'string' && p.appScheme.length > 0) out.appScheme = p.appScheme;
  return out;
}

async function getCatalog() {
  const now = Date.now();
  if (cached && now - cachedAtMs < CACHE_TTL_MS) return cached;

  try {
    const snap = await db.collection(CATALOG_COLLECTION).get();
    const groups = [];
    let latest = null;
    snap.forEach(doc => {
      const d = doc.data();
      if (d.enabled === false) return;
      const providers = (Array.isArray(d.providers) ? d.providers : [])
        .map(sanitizeProvider)
        .filter(Boolean);
      if (providers.length === 0) return;
      groups.push({
        id: doc.id,
        title: String(d.title || doc.id),
        icon: String(d.icon || 'arrow.up.right.square'),
        sheetTitle: String(d.sheetTitle || d.title || doc.id),
        categories: Array.isArray(d.categories) && d.categories.length ? d.categories.map(String) : ['*'],
        order: typeof d.order === 'number' ? d.order : 999,
        providers
      });
      if (d.updatedAt && (!latest || d.updatedAt > latest)) latest = d.updatedAt;
    });
    groups.sort((a, b) => a.order - b.order);
    cached = { updatedAt: latest || new Date().toISOString(), groups };
    cachedAtMs = now;
    return cached;
  } catch (error) {
    console.error('partnerActionsService.getCatalog failed:', error.message);
    // Stale-on-error beats an empty row; empty catalog only when we never loaded
    return cached || { updatedAt: null, groups: [] };
  }
}

module.exports = { getCatalog };
