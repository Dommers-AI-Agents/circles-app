// backend/services/clubs/posts.js
//
// Clubs: the bulletin (organizers' announcements: every member hears about a
// new one) and the board (any member posts; replies and one emoji reaction
// per member per post). A reply tells the post's author; a new board post
// tells nobody, so a chatty board never becomes a noisy phone.
const s = require('./shared');
const { ServiceError } = require('../../utils/serviceError');
const { isAllowedImageUrl } = require('../postcardShareService');
const { clean } = require('../../utils/text');
const { nowIso } = require('../../utils/ids');
const notifyQuiet = require('../notifyQuiet');

const KINDS = ['bulletin', 'board'];
const preview = (text, n = 140) => (text.length > n ? `${text.slice(0, n - 1)}…` : text);
const memberOf = (data, uid) => (data.members && data.members[uid]) || {};

async function listPosts(clubId, uid, { kind = 'board', before = null } = {}) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  if (!KINDS.includes(kind)) throw new ServiceError(400, 'invalid_kind', 'Bulletin or board');
  let query = s.postsCol().where('clubId', '==', id).where('kind', '==', kind);
  if (before && Number.isFinite(Date.parse(before))) query = query.where('createdAt', '<', new Date(Date.parse(before)).toISOString());
  const snap = await query.orderBy('createdAt', 'desc').limit(s.POSTS_PAGE + 1).get();
  const docs = snap.docs.slice(0, s.POSTS_PAGE);
  return { posts: docs.map((d) => s.toClientPost(d.id, d.data(), data, uid)), hasMore: snap.docs.length > s.POSTS_PAGE };
}

async function createPost(clubId, uid, body = {}) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  const kind = body.kind === 'bulletin' ? 'bulletin' : 'board';
  if (kind === 'bulletin' && !s.isOrganizer(data, uid)) throw new ServiceError(403, 'not_organizer', 'Only organizers post to the bulletin');
  const text = clean(body.text, s.POST_MAX) || '';
  const photoUrl = body.photoUrl ? String(body.photoUrl) : null;
  if (photoUrl && !isAllowedImageUrl(photoUrl)) throw new ServiceError(400, 'invalid_image', 'Upload the photo first');
  if (!text && !photoUrl) throw new ServiceError(400, 'empty', 'Write something first');
  const me = memberOf(data, uid);
  const post = {
    clubId: id, kind, authorId: uid, authorName: me.name || 'Member', authorAvatar: me.avatarUrl || null,
    text, photoUrl, reactions: {}, replyCount: 0, createdAt: nowIso()
  };
  const ref = await s.postsCol().add(post);
  if (kind === 'bulletin') {
    for (const to of s.pushTargets(data, { exclude: [uid] })) {
      notifyQuiet.sendInBackground(to, {
        type: 'club_bulletin',
        title: `\u{1F4E3} ${data.name}`,
        body: text ? preview(text) : `${post.authorName} posted a photo`,
        data: { clubId: id, postId: ref.id }
      }, 'club_bulletin');
    }
  }
  return { post: s.toClientPost(ref.id, post, data, uid) };
}

async function loadPost(clubId, postId) {
  const doc = await s.postsCol().doc(String(postId || '')).get();
  if (!doc.exists || doc.data().clubId !== clubId) throw new ServiceError(404, 'not_found', 'That post is gone');
  return { ref: doc.ref, data: doc.data() };
}

async function deletePost(clubId, uid, postId) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  const post = await loadPost(id, postId);
  if (post.data.authorId !== uid && !s.isOrganizer(data, uid)) throw new ServiceError(403, 'not_yours', 'You can only delete your own posts');
  const replies = await s.repliesCol().where('postId', '==', post.ref.id).get();
  for (const r of replies.docs) await r.ref.delete();
  await post.ref.delete();
  return { deleted: true };
}

/** One reaction per member per post; null (or the same emoji again) takes it back. */
async function react(clubId, uid, postId, { emoji } = {}) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  const post = await loadPost(id, postId);
  const trimmed = typeof emoji === 'string' ? emoji.trim() : '';
  if (emoji && !(trimmed && [...trimmed].length <= 4)) throw new ServiceError(400, 'invalid_emoji', 'Pick an emoji');
  const wanted = trimmed || null;
  const fresh = await s.db().runTransaction(async (tx) => {
    const cur = (await tx.get(post.ref)).data();
    const reactions = { ...(cur.reactions || {}) };
    if (!wanted || reactions[uid] === wanted) delete reactions[uid];
    else reactions[uid] = wanted;
    tx.update(post.ref, { reactions });
    return { ...cur, reactions };
  });
  return { post: s.toClientPost(post.ref.id, fresh, data, uid) };
}

async function listReplies(clubId, uid, postId) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  const post = await loadPost(id, postId);
  const snap = await s.repliesCol().where('postId', '==', post.ref.id).orderBy('createdAt', 'asc').limit(s.REPLIES_MAX).get();
  return { replies: snap.docs.map((d) => s.toClientReply(d.id, d.data(), data, uid)) };
}

async function addReply(clubId, uid, postId, { text } = {}) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  const post = await loadPost(id, postId);
  const body = clean(text, s.REPLY_MAX);
  if (!body) throw new ServiceError(400, 'empty', 'Write something first');
  const me = memberOf(data, uid);
  const reply = {
    clubId: id, postId: post.ref.id, authorId: uid, authorName: me.name || 'Member', authorAvatar: me.avatarUrl || null,
    text: body, createdAt: nowIso()
  };
  const ref = await s.repliesCol().add(reply);
  await post.ref.update({ replyCount: s.fieldValue().increment(1) });
  const fresh = { ...post.data, replyCount: (post.data.replyCount || 0) + 1 };
  // The post's author hears about it (not you replying to yourself)
  for (const to of s.pushTargets(data, { only: [post.data.authorId], exclude: [uid] })) {
    notifyQuiet.sendInBackground(to, {
      type: 'club_reply',
      title: `\u{1F4AC} ${reply.authorName} replied in ${data.name}`,
      body: preview(body),
      data: { clubId: id, postId: post.ref.id }
    }, 'club_reply');
  }
  return { reply: s.toClientReply(ref.id, reply, data, uid), post: s.toClientPost(post.ref.id, fresh, data, uid) };
}

async function deleteReply(clubId, uid, postId, replyId) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  const post = await loadPost(id, postId);
  const doc = await s.repliesCol().doc(String(replyId || '')).get();
  if (!doc.exists || doc.data().postId !== post.ref.id) throw new ServiceError(404, 'not_found', 'That reply is gone');
  if (doc.data().authorId !== uid && !s.isOrganizer(data, uid)) throw new ServiceError(403, 'not_yours', 'You can only delete your own replies');
  await doc.ref.delete();
  await post.ref.update({ replyCount: s.fieldValue().increment(-1) });
  return { deleted: true };
}

module.exports = { listPosts, createPost, deletePost, react, listReplies, addReply, deleteReply };
