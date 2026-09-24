// backend/utils/appVersion.js
// Which build of the app a request or a device token came from, and whether
// it is new enough for something. The app sends `X-App-Version` (the
// marketing version, 1.3.3) on every request, and newer builds also
// `X-App-Build` (the build number). A device token registered by the app
// carries both, so the scheduler can ask "can this phone's app render this?"
// before sending a push whose buttons only exist in newer builds.

/** "1.3.10" vs "1.3.9" → 1; missing parts count as 0. */
function compareVersions(a, b) {
  const pa = String(a || '').split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b || '').split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return 0;
}

/** The client build from request headers: `{ version, build }`, either may be null. */
function clientFromRequest(req) {
  const get = (name) => (req && typeof req.get === 'function' ? req.get(name) : null) || null;
  const version = (get('X-App-Version') || '').trim().slice(0, 20) || null;
  const build = parseInt(get('X-App-Build'), 10);
  return { version, build: Number.isInteger(build) ? build : null };
}

/**
 * True when `{ version, build }` is at least `min` (`{ version, build }`).
 * A newer marketing version passes on its own; the same version needs the
 * build number, which older apps never sent — so they fail closed.
 */
function atLeast(client, min) {
  if (!client || !client.version) return false;
  const c = compareVersions(client.version, min.version);
  if (c !== 0) return c > 0;
  if (!Number.isInteger(min.build)) return true;
  return Number.isInteger(client.build) && client.build >= min.build;
}

/** Whether any of a user's registered device tokens came from a build at least `min`. */
function anyDeviceAtLeast(deviceTokens, min) {
  return (Array.isArray(deviceTokens) ? deviceTokens : []).some((t) => t && atLeast({ version: t.appVersion, build: t.appBuild }, min));
}

module.exports = { anyDeviceAtLeast, atLeast, clientFromRequest, compareVersions };
