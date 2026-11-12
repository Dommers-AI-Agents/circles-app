// backend/services/sseActivityActors.js
//
// Whose activity a live (SSE) viewer listens for: themselves, their accepted
// connections and the people they follow — the same people the one-shot home
// feed draws from (utils/networkAccess). Pure, so the shape of the inputs is
// pinned by a test: getConnectedUserIds returns a Set, and calling .map on it
// silently killed every user's live feed for weeks (found 2026-11-12).

function liveActivityActorIds(userId, connectionIds, followingIds) {
  const ids = new Set();
  const add = (value) => { if (value) ids.add(String(value)); };
  add(userId);
  for (const id of Array.from(connectionIds || [])) add(id);
  for (const id of Array.from(followingIds || [])) add(id);
  return Array.from(ids);
}

module.exports = { liveActivityActorIds };
