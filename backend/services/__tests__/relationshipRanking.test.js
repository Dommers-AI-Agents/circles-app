const { rankRelationships } = require('../relationshipRanking');

const row = (id, score, name) => ({ id, connectionScore: score, connectedUser: { displayName: name } });

describe('rankRelationships', () => {
  test('highest score first, ties by name (code-unit order) then id, whatever the input order', () => {
    const rows = [row('c', 10, 'eaglescout103'), row('a', 10, 'Sal'), row('b', 63, 'Zed'), row('d', 10, 'Sal'), row('e', 0, 'Amy')];
    const ranked = rankRelationships(rows).map((r) => r.id);
    expect(ranked).toEqual(['b', 'a', 'd', 'c', 'e']);
    expect(rankRelationships([...rows].reverse()).map((r) => r.id)).toEqual(ranked);
  });

  test('a missing score sorts last, a missing name before named ties, and nothing throws', () => {
    const ranked = rankRelationships([{ id: 'x' }, row('y', 1, 'B'), { id: 'z', connectionScore: 1 }]);
    expect(ranked.map((r) => r.id)).toEqual(['z', 'y', 'x']);
  });
});
