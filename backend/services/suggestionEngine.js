// Builds each user's ranked list of people worth following.
//
// The old discovery surfaces ranked strangers by how many places they'd saved,
// which is a suggestion any app could make. This is a recommendation network,
// so the strongest reason to follow somebody is that you save the same places —
// a signal the normalized place model makes directly computable and that
// nothing was using.
//
// Signals, strongest first:
//   sharedSaves     "Also saved Café Mogador + 5 more"
//   sameTaste       "Saves coffee & wine bars in Fort Greene"
//   followGraph     "Followed by Dani + 3 others you follow"
//
// "Follows you" is deliberately NOT precomputed — it's one set-membership check
// against data the request already loads, and it must never be stale.
//
// PRIVACY: only publicly-visible places feed this. A reason string is shown to
// a stranger, so naming a venue from someone's private or network-only circle
// would leak it. See isPlaceVisibleToViewer in firebasePlaceController.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

const SUGGESTIONS_COLLECTION = 'userSuggestions';

// How many suggestions to keep per user. The client shows a handful per
// section; the surplus is headroom for dismissals before the next rebuild.
const KEEP_PER_USER = 40;

// Relative weight of each signal. Shared saves dominates on purpose: one
// genuinely shared venue is a better reason than any amount of "is popular".
const WEIGHT = {
  sharedSave: 10,
  sameArea: 7,
  taste: 6,
  followGraph: 4
};

// Geohash prefix lengths used for "same area". 5 chars is roughly a 5km cell
// (same neighbourhood), 4 chars roughly 20km (same metro).
const AREA_NEAR = 5;
const AREA_METRO = 4;

// How strongly each kind of location match counts. Sharing a neighbourhood is
// a much better reason to follow someone than sharing a metro, and both beat
// merely sharing the first three digits of a zipcode.
const AREA_STRENGTH = {
  near: 1.0,     // same ~5km geohash cell
  metro: 0.6,    // same ~20km geohash cell
  zipExact: 0.9, // identical 5-digit zipcode
  zipPrefix: 0.4 // same 3-digit zipcode prefix
};

// Which reason to *show* when several apply. This is deliberately separate
// from WEIGHT, which decides ranking: location contributes the most to whether
// someone is worth suggesting, but "saves coffee & bars in Fort Greene" already
// contains the location, so it is the better sentence to put on the row.
const DISPLAY_RANK = {
  sharedSaves: 4,
  sameTaste: 3,
  sameArea: 2,
  followGraph: 1
};

const CATEGORY_LABELS = {
  restaurant: 'restaurants',
  cafe: 'coffee',
  bar: 'bars',
  hotel: 'hotels',
  retail: 'shops',
  service: 'services',
  attraction: 'attractions',
  entertainment: 'entertainment',
  healthcare: 'health spots',
  fitness: 'gyms',
  education: 'schools',
  outdoor: 'outdoor spots',
  transport: 'transit',
  finance: 'banks',
  other: 'places'
};

/** Cosine similarity between two {key: count} histograms. */
const cosine = (a, b) => {
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (const key of Object.keys(a)) {
    normA += a[key] * a[key];
    if (b[key]) dot += a[key] * b[key];
  }
  for (const key of Object.keys(b)) normB += b[key] * b[key];
  if (!normA || !normB) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
};

/**
 * Reads everything once and builds the indexes every signal needs.
 * Three collection reads total, regardless of how many users exist.
 */
const buildIndexes = async () => {
  const [usersSnap, circlesSnap, placesSnap, connectionsSnap] = await Promise.all([
    db.collection(COLLECTIONS.USERS).get(),
    db.collection(COLLECTIONS.CIRCLES).get(),
    db.collection(COLLECTIONS.PLACES).get(),
    db.collection(COLLECTIONS.CONNECTIONS).get()
  ]);

  // --- users
  const users = new Map();
  usersSnap.docs.forEach((doc) => {
    const u = doc.data();
    users.set(doc.id, {
      id: doc.id,
      displayName: u.displayName || 'Someone',
      profilePicture: u.profilePicture || null,
      isVerified: u.isVerified || false,
      following: new Set(u.following || []),
      followersCount: (u.followers || []).length,
      dismissed: new Set(u.dismissedSuggestions || []),
      geohash: u.geohash || null,
      zipcode: String(u.zipcode || '').trim().slice(0, 5),
      // Free-text "Charlotte, NC" style profile field, used to name an area
      // in the reason when we have nothing more precise.
      locationLabel: (u.location || '').trim() || null
    });
  });

  // --- circles: owner counts, and which circles are publicly visible
  const publicCircles = new Set();
  const counts = new Map(); // ownerId -> { placesCount, circlesCount }
  circlesSnap.docs.forEach((doc) => {
    const c = doc.data();
    if (c.privacy === 'public') publicCircles.add(doc.id);
    if (!c.owner) return;
    const cur = counts.get(c.owner) || { placesCount: 0, circlesCount: 0 };
    cur.placesCount += (c.placesCount || 0);
    cur.circlesCount += 1;
    counts.set(c.owner, cur);
  });

  // --- connections: anyone already connected or mid-request isn't a suggestion
  const connected = new Map(); // userId -> Set(otherId)
  const link = (a, b) => {
    if (!connected.has(a)) connected.set(a, new Set());
    connected.get(a).add(b);
  };
  connectionsSnap.docs.forEach((doc) => {
    const c = doc.data();
    if (!['accepted', 'pending'].includes(c.status)) return;
    if (!c.userId || !c.connectedUserId) return;
    link(c.userId, c.connectedUserId);
    link(c.connectedUserId, c.userId);
  });

  // --- places: the taste signals
  const savers = new Map();       // globalPlaceId -> Set(userId)
  const userPlaces = new Map();   // userId -> Set(globalPlaceId)
  const placeNames = new Map();   // globalPlaceId -> display name
  const categories = new Map();   // userId -> { category: count }
  const areas = new Map();        // userId -> { geohashPrefix: count }
  const areaNames = new Map();    // geohashPrefix -> most common neighborhood

  placesSnap.docs.forEach((doc) => {
    const p = doc.data();
    if (p.deletedAt) return;
    if (!p.addedBy || !p.globalPlaceId) return;

    // Only publicly-visible saves. A place is owner-only when its own privacy
    // is 'private'; otherwise it inherits its circle's visibility.
    if (p.privacy === 'private') return;
    if (!p.circleId || !publicCircles.has(p.circleId)) return;

    if (!savers.has(p.globalPlaceId)) savers.set(p.globalPlaceId, new Set());
    savers.get(p.globalPlaceId).add(p.addedBy);

    if (!userPlaces.has(p.addedBy)) userPlaces.set(p.addedBy, new Set());
    userPlaces.get(p.addedBy).add(p.globalPlaceId);

    if (p.name && !placeNames.has(p.globalPlaceId)) placeNames.set(p.globalPlaceId, p.name);

    const category = p.category || 'other';
    const catHist = categories.get(p.addedBy) || {};
    catHist[category] = (catHist[category] || 0) + 1;
    categories.set(p.addedBy, catHist);

    if (p.geohash) {
      // Store at the finer precision; the coarser metro key is derived from it.
      const area = p.geohash.slice(0, AREA_NEAR);
      const areaHist = areas.get(p.addedBy) || {};
      areaHist[area] = (areaHist[area] || 0) + 1;
      areas.set(p.addedBy, areaHist);

      if (p.neighborhood && !areaNames.has(area)) areaNames.set(area, p.neighborhood);
    }
  });

  // How many people follow each user, measured on the graph itself. Needed to
  // discount hubs: accounts that most of the network follows (new users
  // auto-follow the founders) connect almost everyone to almost everyone at
  // the second hop, so "followed by <hub>" carries nearly no information.
  const followerCount = new Map();
  for (const user of users.values()) {
    for (const followedId of user.following) {
      followerCount.set(followedId, (followerCount.get(followedId) || 0) + 1);
    }
  }

  // Where each user actually is.
  //
  // Profile location is sparse — most accounts have never set a zipcode and
  // never granted location — but the places someone saves are themselves a
  // strong location signal, and those always carry a geohash. So this cascades
  // across all three sources and keeps every key that matches, letting a
  // zipcode-only user and a places-only user still find each other when their
  // zip and their saves agree.
  const userAreas = new Map(); // userId -> { near:Set, metro:Set, zip:string, zipPrefix:string, label }
  for (const [userId, user] of users) {
    const near = new Set();
    const metro = new Set();

    // a) the geohash cells their saved places fall in
    const placeAreas = areas.get(userId);
    if (placeAreas) {
      for (const cell of Object.keys(placeAreas)) {
        metro.add(cell.slice(0, AREA_METRO));
        if (cell.length >= AREA_NEAR) near.add(cell.slice(0, AREA_NEAR));
      }
    }

    // b) their last known device location
    if (user.geohash) {
      near.add(user.geohash.slice(0, AREA_NEAR));
      metro.add(user.geohash.slice(0, AREA_METRO));
    }

    const zip = /^\d{5}$/.test(user.zipcode) ? user.zipcode : null;

    if (near.size || metro.size || zip) {
      userAreas.set(userId, {
        near,
        metro,
        zip,
        zipPrefix: zip ? zip.slice(0, 3) : null,
        label: user.locationLabel
      });
    }
  }

  return {
    users, counts, connected, savers, userPlaces, placeNames,
    categories, areas, areaNames, followerCount, userAreas
  };
};

/**
 * How strongly two users share a location, and what to call it.
 * Returns null when there is no overlap at all.
 */
const areaMatch = (a, b, idx) => {
  if (!a || !b) return null;

  const shared = (setA, setB) => {
    for (const key of setA) if (setB.has(key)) return key;
    return null;
  };

  // Most precise match wins.
  const nearKey = shared(a.near, b.near);
  if (nearKey) {
    return { strength: AREA_STRENGTH.near, label: b.label || idx.areaNames.get(nearKey) || null };
  }
  if (a.zip && b.zip && a.zip === b.zip) {
    return { strength: AREA_STRENGTH.zipExact, label: b.label || b.zip };
  }
  const metroKey = shared(a.metro, b.metro);
  if (metroKey) {
    return { strength: AREA_STRENGTH.metro, label: b.label || idx.areaNames.get(metroKey) || null };
  }
  if (a.zipPrefix && b.zipPrefix && a.zipPrefix === b.zipPrefix) {
    return { strength: AREA_STRENGTH.zipPrefix, label: b.label || null };
  }
  return null;
};

/**
 * How much a path through `viaId` is worth. Someone followed by three people
 * is a real signal; someone followed by the entire network is furniture.
 * Falls off logarithmically rather than cliff-edging at a threshold.
 */
const viaWeight = (viaId, idx) => {
  const followers = idx.followerCount.get(viaId) || 0;
  return 1 / Math.log2(2 + followers);
};

/** The single strongest thing we can say about `candidate` to `userId`. */
const describe = (signal, detail) => {
  switch (signal) {
    case 'sharedSaves': {
      const { placeName, extra } = detail;
      if (!placeName) return `Saved ${extra + 1} of the same places`;
      return extra > 0 ? `Also saved ${placeName} + ${extra} more` : `Also saved ${placeName}`;
    }
    case 'sameTaste': {
      const { topCategories, areaName } = detail;
      const labels = topCategories.map((c) => CATEGORY_LABELS[c] || c);
      const what = labels.length > 1 ? `${labels[0]} & ${labels[1]}` : labels[0];
      return areaName ? `Saves ${what} in ${areaName}` : `Saves ${what} too`;
    }
    case 'sameArea': {
      const { label } = detail;
      return label ? `Saves places in ${label}` : 'Saves places near you';
    }
    case 'followGraph': {
      const { viaName, extra } = detail;
      return extra > 0 ? `Followed by ${viaName} + ${extra} others` : `Followed by ${viaName}`;
    }
    default:
      return 'Suggested for you';
  }
};

/** Ranked suggestions for one user, given the prebuilt indexes. */
const suggestFor = (userId, idx) => {
  const me = idx.users.get(userId);
  if (!me) return [];

  const alreadyConnected = idx.connected.get(userId) || new Set();
  const eligible = (id) =>
    id !== userId
    && !me.following.has(id)
    && !me.dismissed.has(id)
    && !alreadyConnected.has(id)
    && idx.users.has(id);

  // candidateId -> { score, signal, detail }
  const scores = new Map();
  const bump = (id, points, signal, detail) => {
    if (!eligible(id)) return;
    const existing = scores.get(id);
    if (!existing) {
      scores.set(id, { score: points, best: points, signal, detail });
      return;
    }
    // Signals accumulate into the ranking score, but the row shows a single
    // reason: the most specific one available, falling back to the strongest
    // when two are equally specific.
    existing.score += points;
    const rank = DISPLAY_RANK[signal] || 0;
    const currentRank = DISPLAY_RANK[existing.signal] || 0;
    if (rank > currentRank || (rank === currentRank && points > existing.best)) {
      existing.best = points;
      existing.signal = signal;
      existing.detail = detail;
    }
  };

  // --- 1. shared saves
  const mine = idx.userPlaces.get(userId);
  if (mine && mine.size > 0) {
    const overlap = new Map(); // candidateId -> [globalPlaceId]
    for (const globalPlaceId of mine) {
      const others = idx.savers.get(globalPlaceId);
      if (!others) continue;
      for (const otherId of others) {
        if (otherId === userId) continue;
        if (!overlap.has(otherId)) overlap.set(otherId, []);
        overlap.get(otherId).push(globalPlaceId);
      }
    }
    for (const [candidateId, placeIds] of overlap) {
      const placeName = idx.placeNames.get(placeIds[0]) || null;
      bump(
        candidateId,
        WEIGHT.sharedSave * Math.min(placeIds.length, 5),
        'sharedSaves',
        { placeName, extra: placeIds.length - 1 }
      );
    }
  }

  // --- 2. location. In a place-recommendation network, someone saving good
  // spots in your city is useful even when your tastes differ; someone with
  // identical taste three time zones away is not. This used to be only a gate
  // on the taste signal, so proximity was required but never rewarded.
  const myArea = idx.userAreas.get(userId);
  if (myArea) {
    for (const [candidateId, theirArea] of idx.userAreas) {
      if (!eligible(candidateId)) continue;
      const match = areaMatch(myArea, theirArea, idx);
      if (!match) continue;
      bump(
        candidateId,
        WEIGHT.sameArea * match.strength,
        'sameArea',
        { label: match.label }
      );
    }
  }

  // --- 3. same taste. Still gated on sharing an area — but now on the full
  // cascade, so a user whose only location signal is a zipcode can match too,
  // rather than being invisible for never having saved a public place.
  const myCats = idx.categories.get(userId);
  if (myCats && myArea) {
    for (const [candidateId, theirCats] of idx.categories) {
      if (!eligible(candidateId)) continue;

      const theirArea = idx.userAreas.get(candidateId);
      const match = areaMatch(myArea, theirArea, idx);
      if (!match) continue;

      const similarity = cosine(myCats, theirCats);
      if (similarity < 0.6) continue;

      const topCategories = Object.entries(theirCats)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 2)
        .map(([c]) => c);

      bump(
        candidateId,
        WEIGHT.taste * similarity,
        'sameTaste',
        { topCategories, areaName: match.label }
      );
    }
  }

  // --- 4. follow graph. The old friendsOfFriends walked accepted connections
  // only, which is exactly the sparse graph once Follow is the primary action.
  const viaCounts = new Map(); // candidateId -> [{ name, weight }]
  for (const followedId of me.following) {
    const followed = idx.users.get(followedId);
    if (!followed) continue;
    const weight = viaWeight(followedId, idx);
    for (const secondHop of followed.following) {
      if (!eligible(secondHop)) continue;
      if (!viaCounts.has(secondHop)) viaCounts.set(secondHop, []);
      viaCounts.get(secondHop).push({ name: followed.displayName, weight });
    }
  }
  for (const [candidateId, vias] of viaCounts) {
    // Name the most *informative* connector, not an arbitrary one. Being
    // followed by someone with a handful of follows says something; being
    // followed by the account everybody auto-follows says nothing.
    vias.sort((a, b) => b.weight - a.weight);
    const total = vias.slice(0, 5).reduce((sum, v) => sum + v.weight, 0);
    bump(
      candidateId,
      WEIGHT.followGraph * total,
      'followGraph',
      { viaName: vias[0].name, extra: vias.length - 1 }
    );
  }

  // --- rank and denormalize, so rendering a row needs no follow-up reads
  return [...scores.entries()]
    .sort((a, b) => b[1].score - a[1].score)
    .slice(0, KEEP_PER_USER)
    .map(([candidateId, entry]) => {
      const candidate = idx.users.get(candidateId);
      const counts = idx.counts.get(candidateId) || { placesCount: 0, circlesCount: 0 };
      return {
        userId: candidateId,
        signal: entry.signal,
        reason: describe(entry.signal, entry.detail),
        score: Math.round(entry.score * 100) / 100,
        displayName: candidate.displayName,
        profilePicture: candidate.profilePicture,
        isVerified: candidate.isVerified,
        placesCount: counts.placesCount,
        circlesCount: counts.circlesCount
      };
    });
};

/**
 * Rebuilds suggestions for every user and, in the same pass, repairs the
 * denormalized counters on user docs.
 *
 * The reconcile half is not optional: denormalized counters in this codebase
 * have drifted before (a follower-count repair across 33 users), and the whole
 * point of storing them is that read paths trust them.
 */
const buildAllSuggestions = async ({ dryRun = false } = {}) => {
  const startedAt = new Date().toISOString();
  const idx = await buildIndexes();

  let written = 0;
  let countersFixed = 0;
  let batch = db.batch();
  let pending = 0;

  const commitIfNeeded = async (force = false) => {
    // Firestore caps a batch at 500 writes.
    if (pending >= 400 || (force && pending > 0)) {
      if (!dryRun) await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  };

  for (const [userId, user] of idx.users) {
    const suggestions = suggestFor(userId, idx);

    batch.set(db.collection(SUGGESTIONS_COLLECTION).doc(userId), {
      userId,
      suggestions,
      builtAt: startedAt
    });
    pending += 1;
    written += 1;

    // Counter reconcile. Array length is the truth — the stored counts are the
    // thing that drifts, which is why followersCount needed repairing across
    // 33 accounts once already.
    const truth = idx.counts.get(userId) || { placesCount: 0, circlesCount: 0 };
    batch.set(
      db.collection(COLLECTIONS.USERS).doc(userId),
      {
        placesCount: truth.placesCount,
        circlesCount: truth.circlesCount,
        followingCount: user.following.size,
        followersCount: user.followersCount
      },
      { merge: true }
    );
    pending += 1;
    countersFixed += 1;

    await commitIfNeeded();
  }

  await commitIfNeeded(true);

  return {
    users: idx.users.size,
    suggestionsWritten: written,
    countersReconciled: countersFixed,
    dryRun,
    builtAt: startedAt
  };
};

/** One user's precomputed suggestions, or null before the first build. */
const getSuggestionsFor = async (userId) => {
  const doc = await db.collection(SUGGESTIONS_COLLECTION).doc(userId).get();
  return doc.exists ? (doc.data().suggestions || []) : null;
};

module.exports = { buildAllSuggestions, getSuggestionsFor, suggestFor, buildIndexes };
