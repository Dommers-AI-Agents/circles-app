// backend/services/dogPark/posts.js
//
// The Dog Park: members post a photo or a short video of their dog(s); others
// Pet it (one per person, the post's like) and comment. Feeds: newest first,
// top of the week by pets, and people you follow. Reports hide a post after
// REPORT_HIDE_THRESHOLD trusted reporters until an admin decides; blocked and
// hidden accounts never show.
//
// Videos go phone → Storage through signed URLs like Events videos: start
// reserves a post (status 'uploading'), the phone uploads, finish measures
// what landed and publishes.
const s = require('./shared');
const profiles = require('./profiles');
const { ServiceError } = require('../../utils/serviceError');
const { clean } = require('../../utils/text');
const { nowIso } = require('../../utils/ids');
const { queryInChunks } = require('../../utils/firestoreChunks');
const notifyQuiet = require('../notifyQuiet');

const UPLOAD_TTL_MS = 2 * 60 * 60 * 1000;
const SIGNED_URL_TTL_MS = 30 * 60 * 1000;
const TOP_SCAN = 500;

const parseBefore = (before) => (before && Number.isFinite(Date.parse(before)) ? new Date(Date.parse(before)).toISOString() : null);

// ---------------------------------------------------------------------------
// Feeds
// ---------------------------------------------------------------------------

async function feed(uid, { tab = 'today', before = null } = {}) {
  const viewer = await s.loadMember(uid);
  const cursor = parseBefore(before);
  if (tab === 'top') {
    // The week's posts by pets (ties: newest). One page; the week is small.
    const since = new Date(Date.now() - s.TOP_DAYS * 86400000).toISOString();
    const snap = await s.postsCol().where('createdAt', '>=', since).orderBy('createdAt', 'desc').limit(TOP_SCAN).get();
    const posts = await s.present(snap.docs, uid, viewer);
    posts.sort((a, b) => b.petCount - a.petCount || b.createdAt.localeCompare(a.createdAt));
    return { posts: posts.slice(0, s.TOP_LIMIT), hasMore: false };
  }
  if (tab === 'following') {
    const following = [...new Set((viewer.following || []).map(String))].filter((id) => id !== uid);
    if (!following.length) return { posts: [], hasMore: false };
    const docs = await queryInChunks(following, (ids) => {
      let q = s.postsCol().where('authorId', 'in', ids);
      if (cursor) q = q.where('createdAt', '<', cursor);
      return q.orderBy('createdAt', 'desc').limit(s.POSTS_PAGE).get();
    });
    docs.sort((a, b) => String(b.data().createdAt).localeCompare(String(a.data().createdAt)));
    const posts = await s.present(docs, uid, viewer);
    return { posts: posts.slice(0, s.POSTS_PAGE), hasMore: posts.length > s.POSTS_PAGE || docs.length >= s.POSTS_PAGE };
  }
  if (tab !== 'today') throw new ServiceError(400, 'invalid_tab', 'Today, Top or Following');
  // Newest first. Reads a little past a page so hidden posts don't leave it short.
  const read = s.POSTS_PAGE * 2;
  let q = s.postsCol();
  if (cursor) q = q.where('createdAt', '<', cursor);
  const snap = await q.orderBy('createdAt', 'desc').limit(read).get();
  const posts = await s.present(snap.docs, uid, viewer);
  return { posts: posts.slice(0, s.POSTS_PAGE), hasMore: snap.docs.length >= read || posts.length > s.POSTS_PAGE };
}

/** One post (a shared link or a push). Any signed-in person may open it. */
async function getPost(uid, postId) {
  const viewer = await s.loadUser(uid);
  const post = await s.loadVisiblePost(postId, uid, viewer);
  const petted = await s.pettedBy([post.id], uid);
  return { post: s.toClientPost(post.id, post.data, uid, { iPetted: petted.has(post.id) }) };
}

// ---------------------------------------------------------------------------
// Posting
// ---------------------------------------------------------------------------

const authorFields = (uid, user) => ({
  authorId: uid,
  authorName: s.displayName(user),
  authorPhotoUrl: user.profilePicture || null
});

async function createPhotoPost(uid, body = {}, { isAllowedImageUrl = require('../postcardShareService').isAllowedImageUrl } = {}) {
  const user = await s.loadMember(uid);
  const photoUrl = body.photoUrl ? String(body.photoUrl) : '';
  if (!photoUrl || !isAllowedImageUrl(photoUrl)) throw new ServiceError(400, 'invalid_image', 'Upload the photo first');
  const thumbUrl = body.thumbUrl && isAllowedImageUrl(String(body.thumbUrl)) ? String(body.thumbUrl) : null;
  const dogs = await profiles.dogsForPost(uid, body.dogIds);
  const post = {
    ...authorFields(uid, user),
    kind: 'photo', status: 'ready',
    caption: s.cleanCaption(body.caption),
    dogs, dogIds: dogs.map((d) => d.id),
    photoUrl, thumbUrl,
    petCount: 0, commentCount: 0, petMilestonesSent: [],
    createdAt: nowIso()
  };
  const ref = await s.postsCol().add(post);
  await profiles.bumpPostCounts(dogs, 1);
  return { post: s.toClientPost(ref.id, post, uid) };
}

const bucket = () => require('firebase-admin/storage').getStorage().bucket();
const bucketName = () => process.env.FIREBASE_STORAGE_BUCKET || bucket().name;

/** A file's download URL with its own unguessable token (as Events videos). */
async function tokenUrl(path) {
  const token = require('crypto').randomUUID();
  await bucket().file(path).setMetadata({ metadata: { firebaseStorageDownloadTokens: token } });
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName()}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
}

async function startVideo(uid, body = {}) {
  const user = await s.loadMember(uid);
  const seconds = Number(body.durationSec);
  if (!Number.isFinite(seconds) || seconds <= 0) throw new ServiceError(400, 'invalid_duration', 'That video has no length');
  // Half a second of slack for how phones round a clip's length
  if (seconds > s.VIDEO_MAX_SECONDS + 0.5) {
    throw new ServiceError(400, 'video_too_long', `Videos can be up to ${s.VIDEO_MAX_SECONDS} seconds`);
  }
  const ref = s.postsCol().doc();
  const base = `dogs/${uid}/${ref.id}`;
  const storagePaths = { video: `${base}.mp4`, poster: `${base}.jpg`, thumb: `${base}_thumb.jpg` };
  const now = Date.now();
  await ref.set({
    ...authorFields(uid, user),
    kind: 'video', status: 'uploading',
    caption: '', dogs: [], dogIds: [],
    durationSec: Math.round(seconds * 10) / 10,
    storagePaths,
    petCount: 0, commentCount: 0, petMilestonesSent: [],
    createdAt: new Date(now).toISOString()
  });
  const sign = (path, contentType) => bucket().file(path).getSignedUrl({
    version: 'v4', action: 'write', expires: now + SIGNED_URL_TTL_MS, contentType
  }).then(([url]) => url);
  const [video, poster, thumb] = await Promise.all([
    sign(storagePaths.video, 'video/mp4'),
    sign(storagePaths.poster, 'image/jpeg'),
    sign(storagePaths.thumb, 'image/jpeg')
  ]);
  return { videoId: ref.id, uploadUrls: { video, poster, thumb } };
}

async function finishVideo(uid, videoId, body = {}) {
  await s.loadMember(uid);
  const post = await s.loadPost(videoId);
  const row = post.data;
  if (row.kind !== 'video' || row.authorId !== uid) throw new ServiceError(404, 'not_found', 'That video is gone');
  // A retry after success answers with the post as it stands
  if (row.status !== 'uploading') return { post: s.toClientPost(post.id, row, uid) };
  if (Date.now() - (Date.parse(row.createdAt) || 0) >= UPLOAD_TTL_MS) {
    throw new ServiceError(409, 'upload_expired', 'This upload took too long. Please add the video again.');
  }
  const dogs = await profiles.dogsForPost(uid, body.dogIds);
  const { readObjectSizes, deleteObjects, maxEventVideoBytes } = require('../uploadSizeGuard');
  const paths = row.storagePaths || {};
  const sizes = await readObjectSizes(bucket(), paths);
  if (!sizes.video || !sizes.poster) throw new ServiceError(400, 'upload_missing', 'The video didn’t finish uploading. Please try again.');
  if (sizes.video > maxEventVideoBytes(s.VIDEO_MAX_SECONDS) || sizes.poster > 10 * 1024 * 1024 || (sizes.thumb || 0) > 10 * 1024 * 1024) {
    console.warn(`🚫 Oversize dog video ${videoId} by ${uid}: ${JSON.stringify(sizes)}`);
    await deleteObjects(bucket(), paths);
    await post.ref.delete();
    throw new ServiceError(413, 'video_too_large', 'That video is too large. Try a shorter clip.');
  }
  const [videoUrl, posterUrl, thumbUrl] = await Promise.all([
    tokenUrl(paths.video), tokenUrl(paths.poster), sizes.thumb ? tokenUrl(paths.thumb) : null
  ]);
  const ready = {
    status: 'ready', videoUrl, posterUrl, photoUrl: posterUrl, thumbUrl: thumbUrl || posterUrl,
    caption: s.cleanCaption(body.caption), dogs, dogIds: dogs.map((d) => d.id),
    fileSize: sizes.video,
    // Published now: it lands at the top of the newest-first feed
    createdAt: nowIso()
  };
  await post.ref.update(ready);
  await profiles.bumpPostCounts(dogs, 1);
  return { post: s.toClientPost(post.id, { ...row, ...ready }, uid) };
}

/** Comments, pets, files and the dog counts go with the post. */
async function removePostEverywhere(post) {
  const [pets, comments] = await Promise.all([
    s.petsCol().where('postId', '==', post.id).get(),
    s.commentsCol().where('postId', '==', post.id).get()
  ]);
  for (const d of [...pets.docs, ...comments.docs]) await d.ref.delete();
  if (post.data.status === 'ready') await profiles.bumpPostCounts(post.data.dogs, -1);
  if (post.data.kind === 'video' && post.data.storagePaths) {
    try {
      await require('../uploadSizeGuard').deleteObjects(bucket(), post.data.storagePaths);
    } catch (e) { /* best effort */ }
  }
  await post.ref.delete();
}

async function deletePost(uid, postId) {
  const user = await s.loadUser(uid);
  const post = await s.loadPost(postId);
  if (post.data.authorId !== uid && user.isSuperUser !== true) throw new ServiceError(403, 'not_yours', 'You can only delete your own posts');
  await removePostEverywhere(post);
  return { deleted: true };
}

// ---------------------------------------------------------------------------
// Pets
// ---------------------------------------------------------------------------

/**
 * Pet (or un-pet) a post: one per person, counted in a transaction. The
 * author hears at milestones (1, 5, 10, 25…), each milestone once, at most
 * one pet push per post per day.
 */
async function togglePet(uid, postId) {
  const viewer = await s.loadMember(uid);
  const post = await s.loadVisiblePost(postId, uid, viewer);
  const petRef = s.petsCol().doc(s.petId(post.id, uid));
  const result = await s.db().runTransaction(async (tx) => {
    const [cur, pet] = [await tx.get(post.ref), await tx.get(petRef)];
    if (!cur.exists) throw new ServiceError(404, 'not_found', 'That post is gone');
    const data = cur.data();
    const petted = !pet.exists;
    const petCount = Math.max(0, (data.petCount || 0) + (petted ? 1 : -1));
    if (petted) tx.set(petRef, { postId: post.id, userId: uid, authorId: data.authorId, createdAt: nowIso() });
    else tx.delete(petRef);
    tx.update(post.ref, { petCount });
    return { data: { ...data, petCount }, petted };
  });
  if (result.petted) await maybePetPush(post, result.data, uid, viewer);
  return { post: s.toClientPost(post.id, result.data, uid, { iPetted: result.petted }) };
}

/** Which push a new pet earns, or null. Pure. */
function petPush(post, { petterName, today }) {
  const milestone = s.milestoneFor(post.petCount);
  if (!milestone || (post.petMilestonesSent || []).includes(milestone)) return null;
  if (post.petPushDay === today) return null;
  const dogs = s.dogNames(post.dogs, post.kind === 'video' ? 'your video' : 'your photo');
  return {
    milestone,
    title: milestone === 1 ? `🐾 ${petterName} petted ${dogs}!` : `🐾 ${dogs} got petted ${milestone.toLocaleString('en-US')} times!`,
    body: milestone === 1 ? 'Good dog. Very good dog.' : 'The Dog Park loves this one.'
  };
}

async function maybePetPush(post, data, uid, viewer) {
  if (data.authorId === uid) return;
  const today = new Date().toISOString().slice(0, 10);
  const push = petPush(data, { petterName: s.displayName(viewer), today });
  if (!push) return;
  await post.ref.update({ petPushDay: today, petMilestonesSent: s.fieldValue().arrayUnion(push.milestone) }).catch(() => {});
  notifyQuiet.sendInBackground(data.authorId, {
    type: 'dog_pet', title: push.title, body: push.body, data: { postId: post.id }
  }, 'dog_pet');
}

// ---------------------------------------------------------------------------
// Comments
// ---------------------------------------------------------------------------

async function listComments(uid, postId) {
  const viewer = await s.loadUser(uid);
  const post = await s.loadVisiblePost(postId, uid, viewer);
  const snap = await s.commentsCol().where('postId', '==', post.id).orderBy('createdAt', 'asc').limit(s.COMMENTS_MAX).get();
  const rows = snap.docs.map((d) => ({ id: d.id, data: d.data() }));
  const authors = await s.authorsOf(rows.map((r) => r.data));
  const blocked = s.blockedSet(viewer);
  return {
    comments: rows
      .filter((r) => r.data.authorId === uid || (!blocked.has(r.data.authorId) && !s.isHiddenAuthor(authors.get(r.data.authorId))))
      .map((r) => s.toClientComment(r.id, r.data, uid))
  };
}

async function addComment(uid, postId, { text } = {}) {
  const viewer = await s.loadMember(uid);
  const post = await s.loadVisiblePost(postId, uid, viewer);
  const body = clean(text, s.COMMENT_MAX);
  if (!body) throw new ServiceError(400, 'empty', 'Write something first');
  const comment = { postId: post.id, postAuthorId: post.data.authorId, ...authorFields(uid, viewer), text: body, createdAt: nowIso() };
  const ref = await s.commentsCol().add(comment);
  await post.ref.update({ commentCount: s.fieldValue().increment(1) });
  const fresh = { ...post.data, commentCount: (post.data.commentCount || 0) + 1 };
  // The author hears about it, at most once per COMMENT_PUSH_COOLDOWN per post
  const now = Date.now();
  if (post.data.authorId !== uid && now - (post.data.commentPushAt || 0) > s.COMMENT_PUSH_COOLDOWN_MS) {
    await post.ref.update({ commentPushAt: now }).catch(() => {});
    notifyQuiet.sendInBackground(post.data.authorId, {
      type: 'dog_comment',
      title: `💬 ${comment.authorName} commented on ${s.dogNames(post.data.dogs, 'your post')}`,
      body: body.length > 140 ? `${body.slice(0, 139)}…` : body,
      data: { postId: post.id }
    }, 'dog_comment');
  }
  const petted = await s.pettedBy([post.id], uid);
  return {
    comment: s.toClientComment(ref.id, comment, uid),
    post: s.toClientPost(post.id, fresh, uid, { iPetted: petted.has(post.id) })
  };
}

async function deleteComment(uid, postId, commentId) {
  const user = await s.loadUser(uid);
  const post = await s.loadPost(postId);
  const doc = await s.commentsCol().doc(String(commentId || '')).get();
  if (!doc.exists || doc.data().postId !== post.id) throw new ServiceError(404, 'not_found', 'That comment is gone');
  // The commenter, the post's author (it's their post) or an admin
  if (doc.data().authorId !== uid && post.data.authorId !== uid && user.isSuperUser !== true) {
    throw new ServiceError(403, 'not_yours', 'You can only delete your own comments');
  }
  await doc.ref.delete();
  await post.ref.update({ commentCount: s.fieldValue().increment(-1) });
  return { deleted: true };
}

// ---------------------------------------------------------------------------
// Reports and blocks
// ---------------------------------------------------------------------------

async function reportPost(uid, postId, { reason, details } = {}) {
  const viewer = await s.loadUser(uid);
  const post = await s.loadVisiblePost(postId, uid, viewer);
  if (post.data.authorId === uid) throw new ServiceError(400, 'own_post', "You can't report your own post");
  const { COLLECTIONS } = require('../../models/FirestoreModels');
  const report = {
    type: 'content',
    reporterId: uid,
    reportedItemId: post.id,
    reportedItemType: 'dog_post',
    reportedUserId: post.data.authorId,
    reason: clean(reason, 60) || 'inappropriate',
    details: clean(details, 500) || '',
    status: 'pending',
    createdAt: nowIso(),
    updatedAt: nowIso()
  };
  const id = `dog_post_${post.id}_${uid}`.replace(/[/.]/g, '_');
  try {
    await s.db().collection(COLLECTIONS.REPORTS).doc(id).create(report);
  } catch (e) {
    return { ok: true, alreadyReported: true }; // one report per person per post
  }
  const moderation = require('../moderationService');
  let hide = { hidden: false };
  try {
    hide = await moderation.applyAutoHideIfNeeded('dog_post', post.id, { threshold: s.REPORT_HIDE_THRESHOLD });
  } catch (e) {
    console.error('🛡️ dog post auto-hide failed:', e.message);
  }
  moderation.notifyAdmin({ id, ...report }, { autoHidden: hide.hidden, reporterCount: hide.count, trustedCount: hide.trustedCount });
  return { ok: true };
}

async function blockAuthor(uid, otherId) {
  await require('../blockService').block(uid, String(otherId || ''));
  return { ok: true };
}

module.exports = {
  feed, getPost, createPhotoPost, startVideo, finishVideo, deletePost, removePostEverywhere,
  togglePet, listComments, addComment, deleteComment, reportPost, blockAuthor,
  // pure (tested)
  petPush, UPLOAD_TTL_MS
};
