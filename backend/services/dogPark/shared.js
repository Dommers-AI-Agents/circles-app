// backend/services/dogPark/shared.js
//
// "Can I Pet Dat Dog" widget (Wes, 2026-10-22: "a more playful app for dog
// lovers… add your doggie picture, health records, insurance, and favorite
// dog places. But also like send me daily funny dog things. Let other users
// join the community of dogs to see more pictures funny things").
//
// Three parts: The Dog Park (a community anyone can join: photo and 15 s
// video posts, a Pet button instead of likes, comments), Daily Dog (opt-in
// pushes: yesterday's most-petted post or a funny line) and My Dogs (public
// dog cards here; health records and insurance stay in the private widget
// document on the phone and never reach this service).
//
// Shared constants, collections and the pure helpers (tested): validation,
// who sees what, milestones, and the client shapes.
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { ServiceError } = require('../../utils/serviceError');
const { clean } = require('../../utils/text');
const { isHiddenAccount } = require('../hiddenAccounts');
const { nameOf, photoOf } = require('../userLookup');

const NAME_MAX = 40;
const BREED_MAX = 60;
const PERSONALITY_MAX = 120;
const CAPTION_MAX = 300;
const COMMENT_MAX = 500;
const MAX_DOGS_PER_OWNER = 10;
const MAX_DOGS_PER_POST = 3;
const POSTS_PAGE = 20;
const TOP_DAYS = 7;
const TOP_LIMIT = 50;
const COMMENTS_MAX = 200;
/** Videos in the Dog Park: the free Events limit, for everyone */
const VIDEO_MAX_SECONDS = 15;
/** Distinct trusted reporters that hide a post until an admin looks */
const REPORT_HIDE_THRESHOLD = 3;
/** Pet counts that tell the author (then every 1,000) */
const PET_MILESTONES = [1, 5, 10, 25, 50, 100, 250, 500, 1000];
const COMMENT_PUSH_COOLDOWN_MS = 15 * 60 * 1000;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const LINK_BASE = `${process.env.API_PUBLIC_BASE_URL || 'https://api.favcircles.com'}/app/widget/dogs`;
/** The first build with the widget (shared with Clubs: 1.4.1) */
const DOGS_MIN_CLIENT = { version: '1.4.1' };

const db = () => getFirestore();
const fieldValue = () => require('../../config/firebase').FieldValue;
const usersCol = () => db().collection(COLLECTIONS.USERS);
const dogsCol = () => db().collection(COLLECTIONS.DOG_PROFILES);
const postsCol = () => db().collection(COLLECTIONS.DOG_POSTS);
const petsCol = () => db().collection(COLLECTIONS.DOG_PETS);
const commentsCol = () => db().collection(COLLECTIONS.DOG_COMMENTS);
const dotdCol = () => db().collection(COLLECTIONS.DOG_OF_THE_DAY);
const sendsCol = () => db().collection(COLLECTIONS.DOG_DAILY_SENDS);

const petId = (postId, uid) => `${postId}_${uid}`;
const postShareUrl = (postId) => `${LINK_BASE}?post=${encodeURIComponent(postId)}`;
const dailyShareUrl = (dailyId) => `${LINK_BASE}?daily=${encodeURIComponent(dailyId)}`;

// ---------------------------------------------------------------------------
// Validation (pure)
// ---------------------------------------------------------------------------

/** "2021-04-09" that is a real date not in the future, or null. */
function cleanDate(raw, now = new Date()) {
  if (raw === null || raw === undefined || raw === '') return null;
  const s = String(raw).trim().slice(0, 10);
  if (!DATE_RE.test(s)) throw new ServiceError(400, 'invalid_date', 'Pick a date');
  const t = Date.parse(`${s}T00:00:00Z`);
  if (!Number.isFinite(t) || new Date(t).toISOString().slice(0, 10) !== s) throw new ServiceError(400, 'invalid_date', 'Pick a date');
  if (t > now.getTime() + 86400000) throw new ServiceError(400, 'invalid_date', "That date hasn't happened yet");
  if (t < Date.parse('1980-01-01T00:00:00Z')) throw new ServiceError(400, 'invalid_date', 'Pick a date');
  return s;
}

/**
 * A dog card from a request. `partial` (an edit) leaves out what wasn't sent;
 * null clears an optional field. Photo URLs must be our own uploads.
 */
function parseDog(body, { partial = false, now = new Date(), isAllowedImageUrl = require('../postcardShareService').isAllowedImageUrl } = {}) {
  const b = body || {};
  const out = {};
  if (!partial || b.name !== undefined) {
    const name = clean(b.name, NAME_MAX);
    if (!name) throw new ServiceError(400, 'invalid_name', "What's your dog's name?");
    out.name = name;
  }
  if (!partial || b.breed !== undefined) out.breed = clean(b.breed, BREED_MAX) || null;
  if (!partial || b.personality !== undefined) out.personality = clean(b.personality, PERSONALITY_MAX) || null;
  if (!partial || b.birthday !== undefined) out.birthday = cleanDate(b.birthday, now);
  if (!partial || b.gotchaDay !== undefined) out.gotchaDay = cleanDate(b.gotchaDay, now);
  if (!partial || b.photoUrl !== undefined) {
    const url = b.photoUrl ? String(b.photoUrl) : null;
    if (url && !isAllowedImageUrl(url)) throw new ServiceError(400, 'invalid_image', 'Upload the photo first');
    out.photoUrl = url;
  }
  return out;
}

const cleanCaption = (raw) => clean(raw, CAPTION_MAX) || '';

/** The milestone a pet count just reached, or null. Pure. */
function milestoneFor(count) {
  if (!Number.isInteger(count) || count <= 0) return null;
  if (PET_MILESTONES.includes(count)) return count;
  return count > 1000 && count % 1000 === 0 ? count : null;
}

/** "Biscuit", "Biscuit and Mochi", "Biscuit, Mochi and Pip", or the fallback. Pure. */
function dogNames(dogs, fallback = 'your dog') {
  const names = (dogs || []).map((d) => d && d.name).filter(Boolean);
  if (!names.length) return fallback;
  if (names.length === 1) return names[0];
  return `${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}`;
}

// ---------------------------------------------------------------------------
// Who sees what (pure)
// ---------------------------------------------------------------------------

const isMember = (user) => !!(user && user.dogPark && user.dogPark.member === true);

/** Blocked in either direction, from the viewer's own doc. */
function blockedSet(viewer) {
  return new Set([...((viewer && viewer.blockedUsers) || []), ...((viewer && viewer.blockedBy) || [])]);
}

/** An author nobody should see: test/fake/merged/deactivated or banned. */
const isHiddenAuthor = (author) => !author || isHiddenAccount(author) || author.banned === true;

/**
 * Whether `viewerId` may see a post. `authors` maps authorId → user data
 * (missing = deleted account). Finished uploads only; a post under review is
 * still shown to its author, a removed one to nobody.
 */
function canSeePost(post, viewerId, { blocked = new Set(), authors = null } = {}) {
  if (!post || post.status !== 'ready') return false;
  if (post.moderationStatus === 'removed') return false;
  const mine = post.authorId === viewerId;
  if (post.moderationStatus === 'under_review' && !mine) return false;
  if (mine) return true;
  if (blocked.has(post.authorId)) return false;
  if (authors && isHiddenAuthor(authors.get(post.authorId))) return false;
  return true;
}

// ---------------------------------------------------------------------------
// Client shapes (pure)
// ---------------------------------------------------------------------------

const displayName = (user) => ((user && user.displayName) || '').trim() || 'Someone';

function toClientDog(id, dog, owner = null) {
  return {
    id,
    ownerId: dog.ownerId,
    ownerName: owner ? displayName(owner) : (dog.ownerName || 'Someone'),
    ownerPhotoUrl: owner ? (owner.profilePicture || null) : (dog.ownerPhotoUrl || null),
    name: dog.name,
    breed: dog.breed || null,
    birthday: dog.birthday || null,
    gotchaDay: dog.gotchaDay || null,
    personality: dog.personality || null,
    photoUrl: dog.photoUrl || null,
    postCount: dog.postCount || 0
  };
}

// `author` = the author's user record (authorsOf), when the caller read it:
// the post then shows who they are NOW; without it, the name/photo stored on
// the post (Wes, 2026-10-31: one source for people).
function toClientPost(id, post, viewerId, { iPetted = false, author = null } = {}) {
  const video = post.kind === 'video';
  return {
    id,
    authorId: post.authorId,
    authorName: nameOf(author) || post.authorName || 'Someone',
    authorPhotoUrl: photoOf(author) || post.authorPhotoUrl || null,
    caption: post.caption || '',
    dogs: (post.dogs || []).map((d) => ({ id: d.id, name: d.name, breed: d.breed || null })),
    kind: video ? 'video' : 'photo',
    photoUrl: post.photoUrl || null,
    thumbUrl: post.thumbUrl || post.photoUrl || null,
    videoUrl: video ? (post.videoUrl || null) : null,
    posterUrl: video ? (post.posterUrl || post.photoUrl || null) : null,
    durationSec: video ? (post.durationSec || null) : null,
    petCount: Math.max(0, post.petCount || 0),
    iPetted: !!iPetted,
    commentCount: Math.max(0, post.commentCount || 0),
    createdAt: post.createdAt,
    mine: post.authorId === viewerId,
    shareUrl: postShareUrl(id)
  };
}

const toClientComment = (id, comment, viewerId, author = null) => ({
  id,
  authorId: comment.authorId,
  authorName: nameOf(author) || comment.authorName || 'Someone',
  authorPhotoUrl: photoOf(author) || comment.authorPhotoUrl || null,
  text: comment.text || '',
  createdAt: comment.createdAt,
  mine: comment.authorId === viewerId
});

// ---------------------------------------------------------------------------
// Loads
// ---------------------------------------------------------------------------

async function loadUser(uid) {
  const doc = await usersCol().doc(String(uid || '')).get();
  if (!doc.exists) throw new ServiceError(404, 'user_not_found', 'Account not found');
  return doc.data();
}

async function loadMember(uid) {
  const user = await loadUser(uid);
  if (!isMember(user)) throw new ServiceError(403, 'not_member', 'Join the Dog Park first');
  return user;
}

/** Authors of these posts by id (missing = account gone). */
async function authorsOf(posts) {
  const ids = [...new Set(posts.map((p) => p.authorId).filter(Boolean))];
  if (!ids.length) return new Map();
  const docs = await db().getAll(...ids.map((id) => usersCol().doc(String(id))));
  return new Map(docs.filter((d) => d.exists).map((d) => [d.id, d.data()]));
}

/** Which of these post ids the viewer has petted. */
async function pettedBy(postIds, uid) {
  if (!postIds.length) return new Set();
  const docs = await db().getAll(...postIds.map((id) => petsCol().doc(petId(id, uid))));
  return new Set(docs.filter((d) => d.exists).map((d) => d.data().postId));
}

/** Visible posts as the viewer sees them (pets marked), in the given order. */
async function present(docs, viewerId, viewer) {
  const rows = docs.map((d) => ({ id: d.id, data: d.data() }));
  const authors = await authorsOf(rows.map((r) => r.data));
  const blocked = blockedSet(viewer);
  const visible = rows.filter((r) => canSeePost(r.data, viewerId, { blocked, authors }));
  const petted = await pettedBy(visible.map((r) => r.id), viewerId);
  // The authors read for the visibility check name them as they are now
  return visible.map((r) => toClientPost(r.id, r.data, viewerId, { iPetted: petted.has(r.id), author: authors.get(r.data.authorId) }));
}

async function loadPost(postId) {
  const doc = await postsCol().doc(String(postId || '')).get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'That post is gone');
  return { ref: doc.ref, id: doc.id, data: doc.data() };
}

/** A post the viewer can see, or 404 (blocked/hidden/removed look the same as gone). */
async function loadVisiblePost(postId, uid, viewer) {
  const post = await loadPost(postId);
  const authors = await authorsOf([post.data]);
  if (!canSeePost(post.data, uid, { blocked: blockedSet(viewer), authors })) {
    throw new ServiceError(404, 'not_found', 'That post is gone');
  }
  return post;
}

module.exports = {
  NAME_MAX, BREED_MAX, PERSONALITY_MAX, CAPTION_MAX, COMMENT_MAX, MAX_DOGS_PER_OWNER, MAX_DOGS_PER_POST,
  POSTS_PAGE, TOP_DAYS, TOP_LIMIT, COMMENTS_MAX, VIDEO_MAX_SECONDS, REPORT_HIDE_THRESHOLD, PET_MILESTONES,
  COMMENT_PUSH_COOLDOWN_MS, LINK_BASE, DOGS_MIN_CLIENT,
  db, fieldValue, usersCol, dogsCol, postsCol, petsCol, commentsCol, dotdCol, sendsCol,
  petId, postShareUrl, dailyShareUrl,
  cleanDate, parseDog, cleanCaption, milestoneFor, dogNames,
  isMember, blockedSet, isHiddenAuthor, canSeePost, displayName,
  toClientDog, toClientPost, toClientComment,
  loadUser, loadMember, authorsOf, pettedBy, present, loadPost, loadVisiblePost
};
