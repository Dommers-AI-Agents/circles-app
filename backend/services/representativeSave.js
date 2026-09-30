const { isSameUser } = require('./idService');

// Which save of a venue the venue page credits ("Added by Sal · saved by 3").
//
// The viewer's own save if they have one; otherwise the OLDEST save the
// viewer may see (the original adder). Visibility is the caller's
// `isVisibleToViewer(save)` — the same circle + place gate a single save
// passes on GET /places/:id — so the venue page never names a saver the
// viewer couldn't open, and never hides one they could. (It used to credit
// only saves marked Public on the save itself, so every save inheriting a
// circle's privacy — most of them — showed as "Added by a connection".)
//
// Checks are capped: a popular venue can have hundreds of saves, and each
// check may load a circle. Past the cap the page simply credits nobody.
const MAX_VISIBILITY_CHECKS = 25;

const pickRepresentativeSave = async (saves, viewerId, isVisibleToViewer) => {
  const live = (saves || []).filter(save => save && !save.deletedAt);
  if (viewerId) {
    const own = live.find(save => isSameUser(save.addedBy, viewerId));
    if (own) return own;
  }
  const others = live
    .filter(save => !viewerId || !isSameUser(save.addedBy, viewerId))
    .sort((a, b) => new Date(a.createdAt || 0) - new Date(b.createdAt || 0))
    .slice(0, MAX_VISIBILITY_CHECKS);
  for (const save of others) {
    if (await isVisibleToViewer(save)) return save;
  }
  return null;
};

module.exports = { pickRepresentativeSave, MAX_VISIBILITY_CHECKS };
