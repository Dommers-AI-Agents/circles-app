const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const {
  userSearchFields, needsSearchFields, findUsersByName, healUserSearchFields, resetHealedForTests
} = require('../userSearchService');

const seed = async (db, id, data) => db.collection('users').doc(id).set({ ...data, ...userSearchFields(data) });

describe('userSearchService', () => {
  let db;
  beforeEach(() => { db = new FakeFirestore({ namespaced: true }); resetHealedForTests(); });

  test('tokens cover display, first and last names, accents folded', () => {
    const f = userSearchFields({ displayName: 'José R', firstName: 'José', lastName: 'Ramírez' });
    expect(f.searchTokens).toEqual(expect.arrayContaining(['jose', 'ramirez', 'r']));
    expect(f.displayNameLowercase).toBe('josé r');
  });

  test('every query word must start a name word; any order', async () => {
    await seed(db, 'a', { displayName: 'Sal Smith' });
    await seed(db, 'b', { displayName: 'Sally Jones' });
    await seed(db, 'c', { displayName: 'Bob', lastName: 'Salazar' });
    expect((await findUsersByName('sal', { db })).map(u => u.id).sort()).toEqual(['a', 'b', 'c']);
    expect((await findUsersByName('smith sal', { db })).map(u => u.id)).toEqual(['a']);
    expect(await findUsersByName('  ', { db })).toEqual([]);
  });

  test('an account without tokens is stale; a rename makes it stale again', () => {
    expect(needsSearchFields({ displayName: 'Old' })).toBe(true);
    const fresh = { displayName: 'Old', ...userSearchFields({ displayName: 'Old' }) };
    expect(needsSearchFields(fresh)).toBe(false);
    expect(needsSearchFields({ ...fresh, displayName: 'New Name' })).toBe(true);
  });

  test('heal stamps the fields once per (id, name)', async () => {
    await db.collection('users').doc('u').set({ displayName: 'Ann Lee' });
    healUserSearchFields('u', { displayName: 'Ann Lee' }, { db });
    await new Promise(r => setImmediate(r));
    expect((await findUsersByName('ann', { db })).map(u => u.id)).toEqual(['u']);
    const before = (await db.collection('users').doc('u').get()).data().searchName;
    healUserSearchFields('u', { displayName: 'Ann Lee' }, { db }); // no-op, already healed
    expect((await db.collection('users').doc('u').get()).data().searchName).toBe(before);
  });
});
