// services/viewerContext.js
//
// Builds the little bundle of relationships every visibility decision needs:
// who the viewer is connected to, who they follow, and whose Inner Circle list
// they are on. Three reads, done once per request, then handed to the pure
// helpers in services/visibility.js.
//
// Read paths that already have some of this loaded (the activity feed builds
// its own connection sets, the map resolves circles first) can call
// `makeViewerContext` with what they have instead of paying for the reads
// twice.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { getConnectedUserIds, getInnerCircleGrantorLists } = require('../utils/networkAccess');
const { normalizeUserId } = require('./idService');

const db = getFirestore();

// Sets are keyed by NORMALISED id so membership tests match regardless of
// which shape an Apple account's id arrived in.
const toIdSet = (values) =>
  new Set((values ? Array.from(values) : []).filter(Boolean).map(normalizeUserId).filter(Boolean));

/**
 * Assemble a context from sets a caller has already loaded.
 *
 * Grantors are intersected with connections, and that is what makes revocation
 * work: only connections may be added to an Inner Circle, so if someone is on
 * the list but is no longer a connection — they disconnected, or one of them
 * blocked the other — the grant evaporates at the next read. No cleanup job is
 * needed for correctness; tidying the stored list is cosmetic.
 */
const makeViewerContext = ({ viewerId, connections, following, innerCircleGrantors, innerCircleLists, excluded }) => {
  // Blocked either way contributes nothing, on any surface that builds a
  // context — the feed used to be the only reader that stripped them.
  const banned = toIdSet(excluded);
  const connectionSet = new Set([...toIdSet(connections)].filter(id => !banned.has(id)));
  // A caller with the per-list map need not also pass the owners.
  const owners = innerCircleGrantors !== undefined
    ? toIdSet(innerCircleGrantors)
    : toIdSet(innerCircleLists ? [...innerCircleLists.keys()] : []);
  const grantors = new Set([...owners].filter(id => connectionSet.has(id) && !banned.has(id)));
  // The same intersection applied per list, so a grant cannot outlive the
  // connection it was qualified by on either shape of the question.
  const lists = new Map();
  for (const [ownerId, listIds] of (innerCircleLists || new Map())) {
    const owner = normalizeUserId(ownerId);
    if (owner && grantors.has(owner)) lists.set(owner, new Set(listIds));
  }
  return {
    viewerId: viewerId ? String(viewerId) : null,
    connections: connectionSet,
    following: new Set([...toIdSet(following)].filter(id => !banned.has(id))),
    innerCircleGrantors: grantors,
    excluded: banned,
    innerCircleLists: lists
  };
};

/** The full three-read build, for callers starting from nothing. */
const buildViewerContext = async (viewerId) => {
  if (!viewerId) return makeViewerContext({ viewerId: null });

  const [connections, userDoc, innerCircleLists] = await Promise.all([
    getConnectedUserIds(viewerId),
    db.collection(COLLECTIONS.USERS).doc(String(viewerId)).get(),
    getInnerCircleGrantorLists(viewerId)
  ]);

  const { excludedUserIds } = require('./moderationService');
  return makeViewerContext({
    viewerId,
    connections,
    following: userDoc.exists ? userDoc.data().following : [],
    innerCircleLists,
    excluded: userDoc.exists ? excludedUserIds(userDoc.data()) : []
  });
};

module.exports = { makeViewerContext, buildViewerContext };
