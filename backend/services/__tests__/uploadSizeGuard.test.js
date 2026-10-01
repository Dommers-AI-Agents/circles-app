// security audit 2026-10-01: signed upload URLs carry no size cap, so the
// completion step measures real object sizes, refuses oversize uploads, and
// only touches paths minted for this video.

const {
  MAX_VIDEO_BYTES, MAX_IMAGE_BYTES, checkUploadSizes, resolveStoragePaths, readObjectSizes, deleteObjects
} = require('../uploadSizeGuard');

describe('checkUploadSizes', () => {
  test('normal moment passes and totals real bytes', () => {
    expect(checkUploadSizes({ video: 4_000_000, preview: 800_000, thumbnail: 90_000 }))
      .toEqual({ ok: true, offenders: [], totalBytes: 4_890_000 });
  });

  test('photo moment (thumbnail only) passes', () => {
    expect(checkUploadSizes({ video: null, preview: null, thumbnail: 400_000 }).ok).toBe(true);
  });

  test('oversize video or image is refused', () => {
    expect(checkUploadSizes({ video: MAX_VIDEO_BYTES + 1, thumbnail: 1 }).offenders).toEqual(['video']);
    expect(checkUploadSizes({ thumbnail: MAX_IMAGE_BYTES + 1 }).offenders).toEqual(['thumbnail']);
    expect(checkUploadSizes({ preview: 5 * 1024 * 1024 * 1024 }).ok).toBe(false);
  });

  test('unmeasurable slots are ignored', () => {
    expect(checkUploadSizes({})).toEqual({ ok: true, offenders: [], totalBytes: 0 });
  });
});

describe('resolveStoragePaths', () => {
  const stored = { video: 'videos/u1/full/v1_1.mp4', preview: 'videos/u1/preview/v1_1.mp4', thumbnail: 'videos/u1/thumbnails/v1_1.jpg' };

  test('stored paths win over whatever the client sends', () => {
    expect(resolveStoragePaths(stored, { thumbnail: 'videos/u2/thumbnails/x.jpg' }, 'u1', 'v1')).toEqual(stored);
  });

  test('legacy docs accept client paths only inside the caller folder for this video', () => {
    expect(resolveStoragePaths(undefined, stored, 'u1', 'v1')).toEqual(stored);
    expect(resolveStoragePaths(undefined, { ...stored, thumbnail: 'videos/u2/thumbnails/v1_1.jpg' }, 'u1', 'v1')).toBeNull();
    expect(resolveStoragePaths(undefined, { ...stored, video: 'videos/u1/full/other.mp4' }, 'u1', 'v1')).toBeNull();
    expect(resolveStoragePaths(undefined, { thumbnail: 'videos/u1/../u2/v1.jpg' }, 'u1', 'v1')).toBeNull();
    expect(resolveStoragePaths(undefined, null, 'u1', 'v1')).toBeNull();
  });
});

describe('readObjectSizes / deleteObjects', () => {
  const fakeBucket = (sizes, deleted = []) => ({
    file: (path) => ({
      getMetadata: async () => {
        if (!(path in sizes)) throw new Error('404');
        return [{ size: String(sizes[path]) }];
      },
      delete: async () => { deleted.push(path); }
    })
  });

  test('parses GCS string sizes; missing objects read as null', async () => {
    const bucket = fakeBucket({ a: 123, t: 45 });
    expect(await readObjectSizes(bucket, { video: 'a', preview: 'missing', thumbnail: 't' }))
      .toEqual({ video: 123, preview: null, thumbnail: 45 });
  });

  test('deletes every uploaded object', async () => {
    const deleted = [];
    await deleteObjects(fakeBucket({}, deleted), { video: 'a', preview: null, thumbnail: 't' });
    expect(deleted.sort()).toEqual(['a', 't']);
  });
});
