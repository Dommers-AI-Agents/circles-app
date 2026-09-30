// Pure rules for folding one venue record into another (the duplicate
// venue's history must add up on the survivor, never be dropped).
// scripts/merge-venue-pair.js does the Firestore work.

/**
 * users/{uid}/checkInStats: two per-venue aggregates → one. Counts add; the
 * first is the earlier first, the last the later last, and the "last …"
 * details come from whichever side holds that last check-in.
 */
const foldCheckInStats = (survivor, retired) => {
  if (!retired) return survivor || null;
  if (!survivor) return { ...retired };
  const newer = (retired.lastCheckInAt || '') > (survivor.lastCheckInAt || '') ? retired : survivor;
  const firsts = [survivor.firstCheckInAt, retired.firstCheckInAt].filter(Boolean).sort();
  return {
    count: (survivor.count || 0) + (retired.count || 0),
    firstCheckInAt: firsts[0] || null,
    lastCheckInAt: newer.lastCheckInAt || null,
    placeName: newer.placeName || survivor.placeName || retired.placeName || null,
    lastPlaceId: newer.lastPlaceId || null,
    lastCheckInId: newer.lastCheckInId || null
  };
};

/** Union of id lists, order kept (survivor first). */
const unionIds = (...lists) => [...new Set(lists.flat().filter(Boolean))];

/** Photos the survivor lacks, by URL, in the retired venue's order. */
const photosToCarry = (survivorPhotos, retiredPhotos) => {
  const urlOf = (p) => (typeof p === 'string' ? p : p && p.url) || null;
  const have = new Set((survivorPhotos || []).map(urlOf).filter(Boolean));
  return (retiredPhotos || []).filter((p) => {
    const url = urlOf(p);
    if (!url || have.has(url)) return false;
    have.add(url);
    return true;
  });
};

module.exports = { foldCheckInStats, unionIds, photosToCarry };
