// One photo library per place: who sees what, the owner's order and cover,
// owner removal vs. uploader delete, and race-safe likes.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const svc = require('../placePhotoService');

const P = (id, extra = {}) => ({ id, url: `https://x/${id}.jpg`, uploadedBy: 'cust', ...extra });
const OWNER = { canManage: true };
const NOBODY = { canManage: false };

const seed = async (photos, extra = {}) => {
  mockDb.rows('globalPlaces').clear();
  mockDb.rows('stickerVenues').clear();
  mockDb.rows('places').clear();
  await mockDb.collection('globalPlaces').doc('gp').set({ name: 'Cafe', photos, ...extra });
};
const stored = () => mockDb.rows('globalPlaces').get('gp');

describe('who sees what', () => {
  const photos = [P('a'), P('b', { private: true }), P('c', { removedAt: '2026-09-30' }), P('d', { uploadedBy: 'other' }), P('a2', { url: 'https://x/a.jpg' })];

  test('removed photos are gone for everyone; private ones show only to their uploader; one per URL', () => {
    expect(svc.visiblePhotos(photos, 'cust').map((p) => p.id)).toEqual(['a', 'b', 'd']);
    expect(svc.visiblePhotos(photos, 'other').map((p) => p.id)).toEqual(['a', 'd']);
    expect(svc.visiblePhotos(photos, null).map((p) => p.id)).toEqual(['a', 'd']);
  });

  test('hiddenUrls names what a save doc must not bring back', () => {
    expect([...svc.hiddenUrls(photos, 'other')].sort()).toEqual(['https://x/b.jpg', 'https://x/c.jpg']);
    expect([...svc.hiddenUrls(photos, 'cust')]).toEqual(['https://x/c.jpg']);
  });

  test('the cover is the first photo everyone can see', () => {
    expect(svc.coverUrl([P('b', { private: true }), P('c', { removedAt: 'x' }), P('d')])).toBe('https://x/d.jpg');
    expect(svc.coverUrl([])).toBeNull();
  });
});

describe('order', () => {
  test('listed ids go first in that order; nothing else moves or is lost', () => {
    const photos = [P('a'), P('b', { private: true }), P('c'), P('d')];
    expect(svc.reordered(photos, ['d', 'nope', 'c', 'd']).map((p) => p.id)).toEqual(['d', 'c', 'a', 'b']);
    expect(svc.movedToFront(photos, 'c').map((p) => p.id)).toEqual(['c', 'a', 'b', 'd']);
  });

  test('reorder and setCover are for the owner/admin only and keep coverPhotoUrl in step', async () => {
    await seed([P('a'), P('b'), P('c')]);
    await expect(svc.reorder('gp', ['c', 'a'], NOBODY)).rejects.toMatchObject({ code: 'forbidden' });
    const out = await svc.reorder('gp', ['c', 'a'], OWNER);
    expect(stored().photos.map((p) => p.id)).toEqual(['c', 'a', 'b']);
    expect(out.coverPhotoUrl).toBe('https://x/c.jpg');
    expect(stored().coverPhotoUrl).toBe('https://x/c.jpg');
    await svc.setCover('gp', 'b', OWNER);
    expect(stored().photos[0].id).toBe('b');
    await expect(svc.setCover('gp', 'b', NOBODY)).rejects.toMatchObject({ code: 'forbidden' });
  });

  test('a private photo can never be the cover', async () => {
    await seed([P('a'), P('b', { private: true })]);
    await expect(svc.setCover('gp', 'b', OWNER)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('removal', () => {
  test('the owner removes a customer photo softly, so it stays gone', async () => {
    await seed([P('a'), P('b')]);
    const out = await svc.remove('gp', 'a', 'owner', OWNER);
    expect(out.mode).toBe('removed');
    expect(stored().photos).toHaveLength(2);
    expect(stored().photos[0]).toMatchObject({ removedBy: 'owner' });
    expect(stored().coverPhotoUrl).toBe('https://x/b.jpg');
    // Re-adding the same URL doesn't bring it back
    const again = await svc.append('gp', P('a-again', { url: 'https://x/a.jpg' }));
    expect(again.added).toBe(false);
    expect(svc.visiblePhotos(stored().photos, 'cust').map((p) => p.id)).toEqual(['b']);
  });

  test('an uploader deletes their own photo for real; not anyone else\'s', async () => {
    await seed([P('a'), P('d', { uploadedBy: 'other' })]);
    await expect(svc.remove('gp', 'd', 'cust', NOBODY)).rejects.toMatchObject({ code: 'forbidden' });
    const out = await svc.remove('gp', 'a', 'cust', NOBODY);
    expect(out.mode).toBe('deleted');
    expect(stored().photos.map((p) => p.id)).toEqual(['d']);
    await expect(svc.remove('gp', 'a', 'cust', NOBODY)).rejects.toMatchObject({ code: 'not_found' });
  });

  test('an owner deleting their own upload deletes it outright', async () => {
    await seed([P('o', { uploadedBy: 'owner' })]);
    expect((await svc.remove('gp', 'o', 'owner', OWNER)).mode).toBe('deleted');
    expect(stored().photos).toHaveLength(0);
  });
});

describe('append and likes', () => {
  test('new photos go after the owner\'s arrangement', async () => {
    await seed([P('a'), P('b')]);
    const out = await svc.append('gp', P('new'));
    expect(out.added).toBe(true);
    expect(stored().photos.map((p) => p.id)).toEqual(['a', 'b', 'new']);
  });

  test('like / unlike is idempotent and only on photos you can see', async () => {
    await seed([P('a'), P('b', { private: true, uploadedBy: 'someone' })]);
    expect((await svc.setLiked('gp', 'a', 'v', true)).likesCount).toBe(1);
    expect((await svc.setLiked('gp', 'a', 'v', true)).changed).toBe(false);
    expect((await svc.setLiked('gp', 'a', 'v', false)).likesCount).toBe(0);
    await expect(svc.setLiked('gp', 'b', 'v', true)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('rights and privacy', () => {
  test('venue owner, managers and super-users manage; others don\'t', async () => {
    await seed([], { googlePlaceId: 'g1' });
    await mockDb.collection('stickerVenues').doc('v1').set({ globalPlaceId: 'gp', ownerUserId: 'owner', managerUserIds: ['mgr'] });
    expect((await svc.rightsFor({ uid: 'owner' }, 'gp', stored())).canManage).toBe(true);
    expect((await svc.rightsFor({ uid: 'mgr' }, 'gp', stored())).canManage).toBe(true);
    expect((await svc.rightsFor({ uid: 'cust' }, 'gp', stored())).canManage).toBe(false);
    expect((await svc.rightsFor({ uid: 'wes', isSuperUser: true }, 'gp', stored())).canManage).toBe(true);
  });

  test('a photo is private when every one of the uploader\'s saves is private', async () => {
    await seed([]);
    await mockDb.collection('places').doc('s1').set({ globalPlaceId: 'gp', addedBy: 'cust', privacy: 'private' });
    expect(await svc.uploaderSaveIsPrivate('gp', 'cust')).toBe(true);
    await mockDb.collection('places').doc('s2').set({ globalPlaceId: 'gp', addedBy: 'cust', privacy: 'public' });
    expect(await svc.uploaderSaveIsPrivate('gp', 'cust')).toBe(false);
    expect(await svc.uploaderSaveIsPrivate('gp', 'nobody')).toBe(false);
  });
});

describe('photos that arrive on a save join the one library', () => {
  const user = { uid: 'cust', displayName: 'Cust' };

  test('own uploads are attributed and appended; stock photos only fill an empty library', async () => {
    await seed([P('owner1', { uploadedBy: 'owner' })]);
    const out = await svc.adoptSavePhotos({ globalPlaceId: 'gp', user, photos: ['https://x/mine.jpg', 'https://x/stock.jpg'], ownUrls: ['https://x/mine.jpg'] });
    expect(out.added).toBe(1);
    expect(stored().photos.map((p) => p.url)).toEqual(['https://x/owner1.jpg', 'https://x/mine.jpg']);
    expect(stored().photos[1]).toMatchObject({ uploadedBy: 'cust', uploadedByName: 'Cust', source: 'user_upload' });

    await seed([]);
    await svc.adoptSavePhotos({ globalPlaceId: 'gp', user, photos: ['https://x/stock.jpg'] });
    expect(stored().photos[0]).toMatchObject({ url: 'https://x/stock.jpg', uploadedBy: null, source: 'auto' });
  });

  test('a private save\'s own photo is private, and never fills a library for others', async () => {
    await seed([]);
    await svc.adoptSavePhotos({ globalPlaceId: 'gp', user, photos: ['https://x/a.jpg', 'https://x/s.jpg'], ownUrls: ['https://x/a.jpg'], isPrivate: true });
    expect(stored().photos).toHaveLength(1);
    expect(stored().photos[0].private).toBe(true);
    expect(stored().coverPhotoUrl).toBeNull();
  });

  test('an own photo an older merge stored unattributed is credited to its uploader', async () => {
    await seed([P('old', { uploadedBy: null, source: 'legacy_import' })]);
    await svc.adoptSavePhotos({ globalPlaceId: 'gp', user, ownUrls: ['https://x/old.jpg'] });
    expect(stored().photos).toHaveLength(1);
    expect(stored().photos[0]).toMatchObject({ uploadedBy: 'cust', source: 'user_upload' });
  });

  test('Edit Place removals delete your own library photo, and leave other people\'s', async () => {
    await seed([P('mine'), P('theirs', { uploadedBy: 'other' })]);
    const out = await svc.adoptSavePhotos({ globalPlaceId: 'gp', user, removedUrls: ['https://x/mine.jpg', 'https://x/theirs.jpg'] });
    expect(out.removed).toBe(1);
    expect(stored().photos.map((p) => p.id)).toEqual(['theirs']);
  });

  test('a save without its own tier follows its circle', async () => {
    expect(svc.effectivelyPrivate('private', 'public')).toBe(true);
    expect(svc.effectivelyPrivate(null, 'private')).toBe(true);
    expect(svc.effectivelyPrivate('public', 'private')).toBe(false);
    expect(svc.effectivelyPrivate(null, null)).toBe(false);
    await mockDb.collection('circles').doc('c1').set({ privacy: 'private' });
    expect(await svc.saveIsPrivate({ circleId: 'c1' })).toBe(true);
    expect(await svc.saveIsPrivate({ circleId: 'c1', privacy: 'public' })).toBe(false);
  });
});

