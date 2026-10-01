// Abandoned moment uploads: stale unfinished docs are marked 'abandoned'
// (never deleted), their Storage objects removed, only inside the uploader's
// own folder, and the run is capped and resumable.
jest.mock('../../config/firebase', () => ({ getFirestore: () => { throw new Error('tests inject db'); } }));
jest.mock('../../models/FirestoreModels', () => ({ COLLECTIONS: { PLACE_VIDEOS: 'placeVideos' } }));

const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const { sweepOrphanUploads } = require('../orphanUploadSweeper');

const NOW = Date.parse('2026-10-01T12:00:00Z');
const hoursAgo = (h) => new Date(NOW - h * 3600 * 1000).toISOString();

// A Storage bucket stand-in: a set of object names, delete + prefix listing.
const fakeBucket = (names = [], { failOn = [] } = {}) => {
  const objects = new Set(names);
  const file = (name) => ({
    name,
    async delete() {
      if (failOn.includes(name)) throw new Error('boom');
      objects.delete(name);
    }
  });
  return {
    objects,
    file,
    async getFiles({ prefix }) { return [[...objects].filter((n) => n.startsWith(prefix)).map(file)]; }
  };
};

const paths = (uid, id) => ({
  video: `videos/${uid}/full/${id}_1.mp4`,
  preview: `videos/${uid}/preview/${id}_1.mp4`,
  thumbnail: `videos/${uid}/thumbnails/${id}_1.jpg`
});

const setup = (docs) => {
  const db = new FakeFirestore({ namespaced: true });
  for (const [id, data] of Object.entries(docs)) db.rows('placeVideos').set(id, data);
  return db;
};
const row = (db, id) => db.rows('placeVideos').get(id);

describe('sweepOrphanUploads', () => {
  test('abandons a stale upload and deletes its stored objects; leaves fresh and finished ones', async () => {
    const db = setup({
      stale: { userId: 'u1', uploadStatus: 'uploading', createdAt: hoursAgo(3), storagePaths: paths('u1', 'stale') },
      stuck: { userId: 'u1', uploadStatus: 'processing', createdAt: hoursAgo(5), storagePaths: { ...paths('u1', 'stuck'), video: null, preview: null } },
      fresh: { userId: 'u1', uploadStatus: 'uploading', createdAt: hoursAgo(1), storagePaths: paths('u1', 'fresh') },
      done: { userId: 'u1', uploadStatus: 'ready', createdAt: hoursAgo(9), storagePaths: paths('u1', 'done') }
    });
    const bucket = fakeBucket([
      ...Object.values(paths('u1', 'stale')),
      paths('u1', 'stuck').thumbnail,
      ...Object.values(paths('u1', 'fresh')),
      ...Object.values(paths('u1', 'done'))
    ]);

    const result = await sweepOrphanUploads({ db, bucket, now: () => NOW });

    expect(result.abandoned).toBe(2);
    expect(row(db, 'stale')).toMatchObject({ uploadStatus: 'abandoned', abandonedFromStatus: 'uploading', storageCleanupPending: false });
    expect(row(db, 'stuck')).toMatchObject({ uploadStatus: 'abandoned', abandonedFromStatus: 'processing' });
    expect(row(db, 'fresh').uploadStatus).toBe('uploading');
    expect(row(db, 'done').uploadStatus).toBe('ready');
    expect([...bucket.objects].sort()).toEqual([
      ...Object.values(paths('u1', 'done')),
      ...Object.values(paths('u1', 'fresh'))
    ].sort());
  });

  test('a doc from before stored paths is cleaned by its own prefix only', async () => {
    const db = setup({ legacy: { userId: 'u2', uploadStatus: 'uploading', createdAt: hoursAgo(30) } });
    const bucket = fakeBucket([
      'videos/u2/full/legacy_99.mp4',
      'videos/u2/thumbnails/legacy_99.jpg',
      'videos/u2/full/other_1.mp4'
    ]);
    await sweepOrphanUploads({ db, bucket, now: () => NOW });
    expect([...bucket.objects]).toEqual(['videos/u2/full/other_1.mp4']);
    expect(row(db, 'legacy').uploadStatus).toBe('abandoned');
  });

  test('never deletes a stored path outside the uploader\'s folder', async () => {
    const db = setup({
      forged: { userId: 'u3', uploadStatus: 'uploading', createdAt: hoursAgo(3), storagePaths: { video: 'videos/victim/full/forged_1.mp4', preview: null, thumbnail: 'videos/u3/thumbnails/forged_1.jpg' } }
    });
    const bucket = fakeBucket(['videos/victim/full/forged_1.mp4', 'videos/u3/thumbnails/forged_1.jpg']);
    await sweepOrphanUploads({ db, bucket, now: () => NOW });
    expect([...bucket.objects]).toEqual(['videos/victim/full/forged_1.mp4']);
  });

  test('a failed delete is kept pending and retried next run', async () => {
    const p = paths('u4', 'flaky');
    const db = setup({ flaky: { userId: 'u4', uploadStatus: 'uploading', createdAt: hoursAgo(3), storagePaths: p } });
    const first = await sweepOrphanUploads({ db, bucket: fakeBucket(Object.values(p), { failOn: [p.video] }), now: () => NOW });
    expect(first.cleanupFailed).toBe(1);
    expect(row(db, 'flaky')).toMatchObject({ uploadStatus: 'abandoned', storageCleanupPending: true });

    const bucket = fakeBucket([p.video]);
    const second = await sweepOrphanUploads({ db, bucket, now: () => NOW + 3600 * 1000 });
    expect(second.retried).toBe(1);
    expect(bucket.objects.size).toBe(0);
    expect(row(db, 'flaky').storageCleanupPending).toBe(false);
  });

  test('caps the work per run and the next run picks up the rest', async () => {
    const docs = {};
    for (let i = 0; i < 7; i++) docs[`v${i}`] = { userId: 'u5', uploadStatus: 'uploading', createdAt: hoursAgo(4), storagePaths: paths('u5', `v${i}`) };
    const db = setup(docs);
    const bucket = fakeBucket([]);
    const first = await sweepOrphanUploads({ db, bucket, now: () => NOW, maxPerRun: 3 });
    expect(first.abandoned).toBe(3);
    let total = first.abandoned;
    for (let run = 1; run < 6 && total < 7; run++) {
      total += (await sweepOrphanUploads({ db, bucket, now: () => NOW + run * 3600 * 1000, maxPerRun: 3 })).abandoned;
    }
    expect(total).toBe(7);
    expect(Object.keys(docs).every((id) => row(db, id).uploadStatus === 'abandoned')).toBe(true);
  });

  test('dry run writes and deletes nothing', async () => {
    const p = paths('u6', 'dry');
    const db = setup({ dry: { userId: 'u6', uploadStatus: 'uploading', createdAt: hoursAgo(3), storagePaths: p } });
    const bucket = fakeBucket(Object.values(p));
    const result = await sweepOrphanUploads({ db, bucket, now: () => NOW, dryRun: true });
    expect(result.abandoned).toBe(1);
    expect(row(db, 'dry').uploadStatus).toBe('uploading');
    expect(bucket.objects.size).toBe(3);
    expect(db.rows('jobCursors').size).toBe(0);
  });
});
