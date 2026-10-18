// Disappearing moments (2026-10-18): a moment posted with "Disappears after
// 24 hours" is hidden the moment it runs out and deleted for good by the
// sweep — files, likes, comments, views and every activity row about it.
const { FakeFirestore, FakeFieldValue } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const { COLLECTIONS } = require('../../models/FirestoreModels');
const expiry = require('../momentExpiry');
const { removeMoment, storagePathsFor } = require('../momentDeletion');
const { filterActivitiesForViewer, defaultActivityPrivacy } = require('../activityPrivacy');
const { makeViewerContext } = require('../viewerContext');

const HOUR = 60 * 60 * 1000;
const NOW = Date.parse('2026-10-18T12:00:00.000Z');

const fakeBucket = () => {
  const deleted = [];
  return { deleted, file: (p) => ({ delete: async () => { deleted.push(p); } }) };
};

const rows = (name) => [...mockDb.rows(name).values()];
const seed = (name, id, data) => mockDb.collection(name).doc(id).set(data);

beforeEach(() => {
  for (const name of [COLLECTIONS.PLACE_VIDEOS, COLLECTIONS.ACTIVITIES, COLLECTIONS.ACTIVITY_REACTIONS,
    COLLECTIONS.ACTIVITY_COMMENTS, COLLECTIONS.VIDEO_LIKES, COLLECTIONS.VIDEO_VIEWS, 'video_comments',
    COLLECTIONS.USER_VIDEO_QUOTAS]) {
    mockDb.rows(name).clear();
  }
});

describe('expiry rules', () => {
  test('24 hours from when it goes live', () => {
    expect(expiry.expiresAtFor(new Date(NOW))).toBe('2026-10-19T12:00:00.000Z');
  });

  test('only an explicit yes asks for it', () => {
    expect(expiry.wantsDisappearing({ disappearing: true })).toBe(true);
    expect(expiry.wantsDisappearing({ disappearing: 'true' })).toBe(true);
    expect(expiry.wantsDisappearing({ disappearing: false })).toBe(false);
    expect(expiry.wantsDisappearing({})).toBe(false);
    expect(expiry.wantsDisappearing(undefined)).toBe(false);
  });

  test('expired only once its time has passed; ordinary moments never', () => {
    expect(expiry.isExpired({ expiresAt: new Date(NOW - 1).toISOString() }, NOW)).toBe(true);
    expect(expiry.isExpired({ expiresAt: new Date(NOW + HOUR).toISOString() }, NOW)).toBe(false);
    expect(expiry.isExpired({}, NOW)).toBe(false);
    expect(expiry.isExpired({ expiresAt: null }, NOW)).toBe(false);
  });

  test('lists drop expired moments, docs or plain objects', () => {
    const list = [
      { id: 'a', expiresAt: new Date(NOW - HOUR).toISOString() },
      { id: 'b', expiresAt: new Date(NOW + HOUR).toISOString() },
      { id: 'c' }
    ];
    expect(expiry.withoutExpired(list, NOW).map(v => v.id)).toEqual(['b', 'c']);
    const docs = list.map(v => ({ id: v.id, data: () => v }));
    expect(expiry.withoutExpired(docs, NOW).map(d => d.id)).toEqual(['b', 'c']);
  });
});

describe('feed rows', () => {
  test('an expired moment row is hidden from everyone, its owner too, cached rows included', () => {
    const past = new Date(Date.now() - HOUR).toISOString();
    const future = new Date(Date.now() + HOUR).toISOString();
    const activities = [
      { id: 'gone', type: 'video_uploaded', actorId: 'owner', metadata: { momentVisibility: 'public', momentOwnerId: 'owner', expiresAt: past } },
      { id: 'live', type: 'video_uploaded', actorId: 'owner', metadata: { momentVisibility: 'public', momentOwnerId: 'owner', expiresAt: future } },
      { id: 'plain', type: 'video_uploaded', actorId: 'owner', metadata: { momentVisibility: 'public', momentOwnerId: 'owner' } }
    ];
    // The owner shares moments with everyone, so only expiry decides
    const grid = defaultActivityPrivacy();
    grid.moments = { public: true, myNetwork: true, innerCircle: true };
    const settingsByActor = new Map([['owner', grid]]);
    for (const viewer of ['owner', 'someone']) {
      for (const skipItemGates of [false, true]) {
        const seen = filterActivitiesForViewer({
          activities, viewerId: viewer, viewerCtx: makeViewerContext({ viewerId: viewer }),
          circlesById: null, settingsByActor, skipItemGates
        }).map(a => a.id);
        expect(seen).toEqual(['live', 'plain']);
      }
    }
  });
});

describe('deleting a moment', () => {
  const video = {
    userId: 'owner',
    activityId: 'act-upload',
    fileSize: 1000,
    storagePaths: { video: 'videos/owner/full/m1.mp4', preview: null, thumbnail: 'videos/owner/thumbnails/m1.jpg' },
    thumbnailUrl: 'https://firebasestorage.googleapis.com/v0/b/circles-app-83b67.firebasestorage.app/o/videos%2Fowner%2Fthumbnails%2Fm1.jpg?alt=media'
  };

  test('only the owner\'s own files, recorded paths and URLs merged', () => {
    expect(storagePathsFor(video).sort()).toEqual(['videos/owner/full/m1.mp4', 'videos/owner/thumbnails/m1.jpg']);
    expect(storagePathsFor({ ...video, storagePaths: { video: 'videos/someone-else/full/x.mp4' }, thumbnailUrl: null })).toEqual([]);
  });

  test('removes the moment with its files, likes, comments, views and activity rows', async () => {
    await seed(COLLECTIONS.PLACE_VIDEOS, 'm1', video);
    await seed(COLLECTIONS.PLACE_VIDEOS, 'm2', { userId: 'owner' });
    await seed(COLLECTIONS.ACTIVITIES, 'act-upload', { type: 'video_uploaded', targetType: 'place_video', targetId: 'm1' });
    await seed(COLLECTIONS.ACTIVITIES, 'act-like', { type: 'video_liked', targetType: 'video', targetId: 'm1' });
    await seed(COLLECTIONS.ACTIVITIES, 'act-other', { type: 'video_liked', targetType: 'video', targetId: 'm2' });
    await seed(COLLECTIONS.ACTIVITY_REACTIONS, 'r1', { activityId: 'act-upload' });
    await seed(COLLECTIONS.ACTIVITY_COMMENTS, 'c1', { activityId: 'act-upload' });
    await seed(COLLECTIONS.VIDEO_LIKES, 'u_m1', { videoId: 'm1' });
    await seed(COLLECTIONS.VIDEO_LIKES, 'u_m2', { videoId: 'm2' });
    await seed('video_comments', 'vc1', { videoId: 'm1' });
    await seed(COLLECTIONS.VIDEO_VIEWS, 'v1', { videoId: 'm1' });
    const bucket = fakeBucket();

    const counts = await removeMoment('m1', video, { db: mockDb, bucket });

    expect(bucket.deleted.sort()).toEqual(['videos/owner/full/m1.mp4', 'videos/owner/thumbnails/m1.jpg']);
    expect(mockDb.rows(COLLECTIONS.PLACE_VIDEOS).has('m1')).toBe(false);
    expect(mockDb.rows(COLLECTIONS.PLACE_VIDEOS).has('m2')).toBe(true);
    expect([...mockDb.rows(COLLECTIONS.ACTIVITIES).keys()]).toEqual(['act-other']);
    expect(rows(COLLECTIONS.ACTIVITY_REACTIONS)).toHaveLength(0);
    expect(rows(COLLECTIONS.ACTIVITY_COMMENTS)).toHaveLength(0);
    expect([...mockDb.rows(COLLECTIONS.VIDEO_LIKES).keys()]).toEqual(['u_m2']);
    expect(rows('video_comments')).toHaveLength(0);
    expect(rows(COLLECTIONS.VIDEO_VIEWS)).toHaveLength(0);
    expect(counts).toMatchObject({ files: 2, likes: 1, comments: 1, views: 1, activities: 2 });
    // The quota gives the slot back, even with no quota doc yet
    expect(mockDb.rows(COLLECTIONS.USER_VIDEO_QUOTAS).get('owner')).toMatchObject({ videosUploaded: -1, totalSize: -1000 });
  });
});

describe('the sweep', () => {
  test('deletes only moments whose time is up', async () => {
    const now = new Date(NOW);
    await seed(COLLECTIONS.PLACE_VIDEOS, 'gone', { userId: 'owner', expiresAt: new Date(NOW - HOUR).toISOString() });
    await seed(COLLECTIONS.PLACE_VIDEOS, 'live', { userId: 'owner', expiresAt: new Date(NOW + HOUR).toISOString() });
    await seed(COLLECTIONS.PLACE_VIDEOS, 'plain', { userId: 'owner' });
    await seed(COLLECTIONS.VIDEO_LIKES, 'x_gone', { videoId: 'gone' });

    const result = await expiry.sweep({ db: mockDb, bucket: fakeBucket(), now });

    expect(result).toMatchObject({ deleted: 1, failed: 0, more: false });
    expect([...mockDb.rows(COLLECTIONS.PLACE_VIDEOS).keys()].sort()).toEqual(['live', 'plain']);
    expect(rows(COLLECTIONS.VIDEO_LIKES)).toHaveLength(0);
  });
});
