// The shape of the lists, with no database in the way.
const { listsFrom, unionOf, listIdsContaining, DEFAULT_LIST_ID } = require('../innerCircleLists');

test('an account written before lists existed has exactly one, named', () => {
  expect(listsFrom({ innerCircle: ['a', 'b'] })).toEqual([
    { id: DEFAULT_LIST_ID, name: 'Inner Circle', userIds: ['a', 'b'] }
  ]);
  expect(listsFrom({})).toEqual([]);
  expect(listsFrom({ innerCircle: [] })).toEqual([]);
});

test('stored lists win over the flat field, and junk in them is dropped', () => {
  const lists = listsFrom({
    innerCircle: ['a', 'b', 'c'],
    innerCircles: [
      { id: 'l1', name: '  Family  ', userIds: ['a', 'b', 'a'] },
      { id: 'l2', name: '', userIds: ['c', 7, null] },
      { name: 'no id, dropped', userIds: ['d'] }
    ]
  });
  expect(lists).toEqual([
    { id: 'l1', name: 'Family', userIds: ['a', 'b'] },
    { id: 'l2', name: 'Inner Circle', userIds: ['c'] }
  ]);
});

test('a name is trimmed to one line and capped, never left empty', () => {
  const [list] = listsFrom({ innerCircles: [{ id: 'l1', name: 'x'.repeat(80), userIds: [] }] });
  expect(list.name).toHaveLength(40);
});

test('the union is what the reverse lookup reads: everyone, once', () => {
  expect(unionOf([{ userIds: ['a', 'b'] }, { userIds: ['b', 'c'] }]).sort()).toEqual(['a', 'b', 'c']);
  expect(unionOf([])).toEqual([]);
});

test('a viewer learns which lists they are on, not merely that they are', () => {
  const lists = [
    { id: 'family', userIds: ['a'] },
    { id: 'gym', userIds: ['a', 'b'] },
    { id: 'work', userIds: ['c'] }
  ];
  expect([...listIdsContaining(lists, 'a')].sort()).toEqual(['family', 'gym']);
  expect([...listIdsContaining(lists, 'zed')]).toEqual([]);
  // The caller owns the comparison, because ids arrive in more than one shape.
  const loose = (x, y) => String(x).toLowerCase() === String(y).toLowerCase();
  expect([...listIdsContaining(lists, 'A', loose)].sort()).toEqual(['family', 'gym']);
});
