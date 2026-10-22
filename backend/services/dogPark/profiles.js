// backend/services/dogPark/profiles.js
//
// Dog cards: the public part of "My Dogs" (name, breed, birthday, gotcha day,
// personality, photo). Health records and insurance never come here.
const s = require('./shared');
const { ServiceError } = require('../../utils/serviceError');
const { nowIso } = require('../../utils/ids');

async function listMine(uid) {
  const [snap, owner] = await Promise.all([
    s.dogsCol().where('ownerId', '==', uid).get(),
    s.loadUser(uid)
  ]);
  return snap.docs
    .filter((d) => !d.data().deletedAt)
    .sort((a, b) => String(a.data().createdAt || '').localeCompare(String(b.data().createdAt || '')))
    .map((d) => s.toClientDog(d.id, d.data(), owner));
}

async function createDog(uid, body) {
  const owner = await s.loadUser(uid);
  const fields = s.parseDog(body);
  const existing = await s.dogsCol().where('ownerId', '==', uid).get();
  if (existing.docs.filter((d) => !d.data().deletedAt).length >= s.MAX_DOGS_PER_OWNER) {
    throw new ServiceError(400, 'too_many_dogs', `Up to ${s.MAX_DOGS_PER_OWNER} dogs`);
  }
  const at = nowIso();
  const dog = { ownerId: uid, ...fields, postCount: 0, createdAt: at, updatedAt: at };
  const ref = await s.dogsCol().add(dog);
  return { dog: s.toClientDog(ref.id, dog, owner) };
}

async function loadOwnDog(uid, dogId) {
  const doc = await s.dogsCol().doc(String(dogId || '')).get();
  if (!doc.exists || doc.data().deletedAt) throw new ServiceError(404, 'not_found', 'That dog is gone');
  if (doc.data().ownerId !== uid) throw new ServiceError(403, 'not_yours', 'Only the owner can change this dog');
  return { ref: doc.ref, id: doc.id, data: doc.data() };
}

async function updateDog(uid, dogId, body) {
  const dog = await loadOwnDog(uid, dogId);
  const fields = s.parseDog(body, { partial: true });
  const next = { ...dog.data, ...fields, updatedAt: nowIso() };
  await dog.ref.update({ ...fields, updatedAt: next.updatedAt });
  return { dog: s.toClientDog(dog.id, next, await s.loadUser(uid)) };
}

/** The card goes; posts keep the name they were posted with. */
async function deleteDog(uid, dogId) {
  const dog = await loadOwnDog(uid, dogId);
  await dog.ref.delete();
  return { deleted: true };
}

/** A dog's card and its posts. Owners always; others must be members. */
async function getDog(uid, dogId) {
  const viewer = await s.loadUser(uid);
  const doc = await s.dogsCol().doc(String(dogId || '')).get();
  if (!doc.exists || doc.data().deletedAt) throw new ServiceError(404, 'not_found', 'That dog is gone');
  const dog = doc.data();
  const mine = dog.ownerId === uid;
  if (!mine && !s.isMember(viewer)) throw new ServiceError(403, 'not_member', 'Join the Dog Park first');
  const owner = (await s.db().getAll(s.usersCol().doc(String(dog.ownerId))))[0];
  const ownerData = owner && owner.exists ? owner.data() : null;
  if (!mine && (s.isHiddenAuthor(ownerData) || s.blockedSet(viewer).has(dog.ownerId))) {
    throw new ServiceError(404, 'not_found', 'That dog is gone');
  }
  const snap = await s.postsCol().where('dogIds', 'array-contains', doc.id)
    .orderBy('createdAt', 'desc').limit(s.POSTS_PAGE * 2).get();
  const posts = (await s.present(snap.docs, uid, viewer)).slice(0, s.POSTS_PAGE);
  return { dog: s.toClientDog(doc.id, dog, ownerData), posts };
}

/** The viewer's own dogs picked for a post: [{id, name, breed}] (others' ids are refused). */
async function dogsForPost(uid, dogIds) {
  const ids = [...new Set((Array.isArray(dogIds) ? dogIds : []).map(String).filter(Boolean))];
  if (ids.length > s.MAX_DOGS_PER_POST) throw new ServiceError(400, 'too_many_dogs', `Tag up to ${s.MAX_DOGS_PER_POST} dogs`);
  if (!ids.length) return [];
  const docs = await s.db().getAll(...ids.map((id) => s.dogsCol().doc(id)));
  return docs.map((d) => {
    if (!d.exists || d.data().deletedAt || d.data().ownerId !== uid) throw new ServiceError(400, 'invalid_dog', 'Pick one of your dogs');
    return { id: d.id, name: d.data().name, breed: d.data().breed || null };
  });
}

/** postCount on each tagged dog (best effort; a deleted dog is skipped). */
async function bumpPostCounts(dogs, delta) {
  await Promise.all((dogs || []).map((d) => s.dogsCol().doc(d.id)
    .update({ postCount: s.fieldValue().increment(delta) }).catch(() => {})));
}

module.exports = { listMine, createDog, updateDog, deleteDog, getDog, dogsForPost, bumpPostCounts };
