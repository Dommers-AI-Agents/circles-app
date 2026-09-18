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
const { getConnectedUserIds, getInnerCircleGrantorIds } = require('../utils/networkAccess');
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
const makeViewerContext = ({ viewerId, connections, following, innerCircleGrantors }) => {
  const connectionSet = toIdSet(connections);
  const grantors = new Set(
    [...toIdSet(innerCircleGrantors)].filter(id => connectionSet.has(id))
  );
  return {
    viewerId: viewerId ? String(viewerId) : null,
    connections: connectionSet,
    following: toIdSet(following),
    innerCircleGrantors: grantors
  };
};

/** The full three-read build, for callers starting from nothing. */
const buildViewerContext = async (viewerId) => {
  if (!viewerId) return makeViewerContext({ viewerId: null });

  const [connections, userDoc, innerCircleGrantors] = await Promise.all([
    getConnectedUserIds(viewerId),
    db.collection(COLLECTIONS.USERS).doc(String(viewerId)).get(),
    getInnerCircleGrantorIds(viewerId)
  ]);

  return makeViewerContext({
    viewerId,
    connections,
    following: userDoc.exists ? userDoc.data().following : [],
    innerCircleGrantors
  });
};

module.exports = { makeViewerContext, buildViewerContext };
