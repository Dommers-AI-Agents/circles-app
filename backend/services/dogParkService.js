// backend/services/dogParkService.js
//
// "Can I Pet Dat Dog" widget: one entry point over services/dogPark/*
// (see shared.js for what the widget is). Joining, the widget's opening
// state, and the public preview a shared link's landing page shows.
const s = require('./dogPark/shared');
const profiles = require('./dogPark/profiles');
const posts = require('./dogPark/posts');
const daily = require('./dogPark/daily');
const places = require('./dogPark/places');
const records = require('./dogPark/records');
const { nowIso } = require('../utils/ids');
const { atLeast } = require('../utils/appVersion');

/** What the widget opens on: membership, my dogs, Daily Dog settings and today's dog. */
async function me(uid, { client = null, now = new Date() } = {}) {
  const user = await s.loadUser(uid);
  const [dogs, today] = await Promise.all([
    profiles.listMine(uid),
    daily.todayFor(uid, user, now).catch((e) => { console.error('🐶 today failed:', e.message); return null; })
  ]);
  return {
    member: s.isMember(user),
    minVersionOk: atLeast(client, s.DOGS_MIN_CLIENT),
    dogs,
    prefs: daily.prefsOf(user),
    today
  };
}

async function join(uid) {
  const user = await s.loadUser(uid);
  if (!s.isMember(user)) {
    await s.usersCol().doc(uid).update({
      dogPark: { member: true, joinedAt: (user.dogPark && user.dogPark.joinedAt) || nowIso() },
      updatedAt: nowIso()
    });
  }
  return { member: true };
}

/** Leaving stops posting and the feeds; their posts stay up (they can delete them). */
async function leave(uid) {
  const user = await s.loadUser(uid);
  await s.usersCol().doc(uid).update({ dogPark: { ...(user.dogPark || {}), member: false }, updatedAt: nowIso() });
  return { member: false };
}

/**
 * The landing page's preview of a shared post or daily dog (signed out, so
 * only what anyone may see): { title, description, imageUrl } or null.
 */
async function publicPreview({ post = null, daily: dailyId = null } = {}) {
  try {
    let postId = post ? String(post) : null;
    if (!postId && dailyId) {
      const raw = String(dailyId);
      if (raw.startsWith('line_')) {
        const line = require('../config/dogLines').find((l) => `line_${l.id}` === raw);
        return line ? { title: 'Daily Dog 🐶', description: line.text, imageUrl: null } : null;
      }
      if (raw.startsWith('dotd_')) {
        const pick = (await s.dotdCol().doc(raw.slice(5)).get());
        postId = pick.exists ? pick.data().postId : null;
        if (!postId) return null;
      }
    }
    if (!postId) return null;
    const doc = await s.postsCol().doc(postId.slice(0, 128)).get();
    if (!doc.exists) return null;
    const data = doc.data();
    const authors = await s.authorsOf([data]);
    if (!s.canSeePost(data, null, { authors }) || data.moderationStatus) return null;
    const names = s.dogNames(data.dogs, 'A very good dog');
    return {
      title: `${names} 🐾`,
      description: data.caption || `Petted ${data.petCount || 0} ${data.petCount === 1 ? 'time' : 'times'} in the Dog Park`,
      imageUrl: data.posterUrl || data.photoUrl || null
    };
  } catch (e) {
    console.warn('🐶 public preview failed:', e.message);
    return null;
  }
}

module.exports = {
  me, join, leave, publicPreview,
  // dog cards
  listMyDogs: profiles.listMine, createDog: profiles.createDog, updateDog: profiles.updateDog,
  deleteDog: profiles.deleteDog, getDog: profiles.getDog,
  // the Dog Park
  feed: posts.feed, getPost: posts.getPost, createPhotoPost: posts.createPhotoPost,
  startVideo: posts.startVideo, finishVideo: posts.finishVideo, deletePost: posts.deletePost,
  togglePet: posts.togglePet, listComments: posts.listComments, addComment: posts.addComment,
  deleteComment: posts.deleteComment, reportPost: posts.reportPost, blockAuthor: posts.blockAuthor,
  // Daily Dog
  getSettings: daily.getSettings, updateSettings: daily.updateSettings, listDaily: daily.listDaily,
  getDaily: daily.getDaily, runDailyDue: daily.runDue,
  // favorite places, vet records
  savePlace: places.savePlace, scanRecords: records.scan
};
