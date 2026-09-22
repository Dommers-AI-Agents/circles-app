// The order of the people row: highest connection score first, then a stable
// tie-break so paging never depends on Firestore document order. Names compare
// by UTF-16 code unit (uppercase before lowercase), the same comparison the
// iOS row uses within a page, so client and server agree on ties.
const nameOf = (row) => (row.connectedUser && row.connectedUser.displayName) || '';

const compareRelationships = (a, b) => {
  const scoreA = a.connectionScore || 0;
  const scoreB = b.connectionScore || 0;
  if (scoreA !== scoreB) return scoreB - scoreA;
  const nameA = nameOf(a); const nameB = nameOf(b);
  if (nameA !== nameB) return nameA < nameB ? -1 : 1;
  return String(a.id || '') < String(b.id || '') ? -1 : 1;
};

const rankRelationships = (rows) => [...rows].sort(compareRelationships);

module.exports = { compareRelationships, rankRelationships };
