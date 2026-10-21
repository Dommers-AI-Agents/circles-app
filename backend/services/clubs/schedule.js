// backend/services/clubs/schedule.js
//
// Clubs: the weekly meetups ("Saturdays 7 AM at the park"), one-off events
// ("Turkey Trot 5K"), and going / can't-make-it on each dated occurrence.
// Organizers change the schedule; any member RSVPs.
const s = require('./shared');
const { ServiceError } = require('../../utils/serviceError');
const { newId, nowIso } = require('../../utils/ids');
const notifyQuiet = require('../notifyQuiet');
const { clubDetail } = require('./membership');

async function addMeetup(clubId, uid, body) {
  const { ref, id, data } = await s.loadAsOrganizer(clubId, uid);
  if ((data.schedule || []).length >= s.MAX_MEETUPS) throw new ServiceError(400, 'too_many', `A club can have ${s.MAX_MEETUPS} weekly meetups`);
  const meetup = { id: newId(), ...s.parseMeetup(body, data.kind) };
  const schedule = [...(data.schedule || []), meetup];
  await ref.update({ schedule, updatedAt: nowIso() });
  return { club: await clubDetail(id, { ...data, schedule }, uid) };
}

async function updateMeetup(clubId, uid, meetupId, body) {
  const { ref, id, data } = await s.loadAsOrganizer(clubId, uid);
  const schedule = [...(data.schedule || [])];
  const at = schedule.findIndex((m) => m.id === meetupId);
  if (at < 0) throw new ServiceError(404, 'not_found', 'That meetup is gone');
  schedule[at] = { id: meetupId, ...s.parseMeetup(body, data.kind) };
  await ref.update({ schedule, updatedAt: nowIso() });
  return { club: await clubDetail(id, { ...data, schedule }, uid) };
}

async function deleteMeetup(clubId, uid, meetupId) {
  const { ref, id, data } = await s.loadAsOrganizer(clubId, uid);
  const schedule = (data.schedule || []).filter((m) => m.id !== meetupId);
  await ref.update({ schedule, updatedAt: nowIso() });
  return { club: await clubDetail(id, { ...data, schedule }, uid) };
}

/** A one-off event; every member hears about it. */
async function addEvent(clubId, uid, body, now = new Date()) {
  const { ref, id, data } = await s.loadAsOrganizer(clubId, uid);
  const event = { id: newId(), ...s.parseEvent(body, now), createdBy: uid };
  // Long-past events fall off when a new one is added (the list stays short)
  const cutoff = now.getTime() - 30 * 86400000;
  const kept = (data.events || []).filter((e) => Date.parse(e.startsAt) >= cutoff);
  if (kept.length >= s.MAX_EVENTS) throw new ServiceError(400, 'too_many', `A club can have ${s.MAX_EVENTS} upcoming events`);
  const events = [...kept, event];
  await ref.update({ events, updatedAt: nowIso() });

  const where = event.spot || data.homeSpot;
  for (const to of s.pushTargets(data, { exclude: [uid] })) {
    notifyQuiet.sendInBackground(to, {
      type: 'club_event',
      title: `${data.emoji} ${data.name}: ${event.title}`,
      body: `${s.occurrenceLine(event.startsAt, data.timezone)}${where ? ` at ${where.name}` : ''}`,
      data: { clubId: id, occurrenceKey: `e_${event.id}` }
    }, 'club_event');
  }
  return { club: await clubDetail(id, { ...data, events }, uid) };
}

async function deleteEvent(clubId, uid, eventId) {
  const { ref, id, data } = await s.loadAsOrganizer(clubId, uid);
  const events = (data.events || []).filter((e) => e.id !== eventId);
  await ref.update({ events, updatedAt: nowIso() });
  return { club: await clubDetail(id, { ...data, events }, uid) };
}

/** Going / can't make it / cleared, on one upcoming occurrence. */
async function rsvp(clubId, uid, { key, status } = {}, now = new Date()) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  if (![ 'going', 'not', null, undefined ].includes(status)) throw new ServiceError(400, 'invalid_status', 'Going or not going');
  const occ = s.upcomingOccurrences(data, now, { limit: 1000 }).find((o) => o.key === key);
  if (!occ) throw new ServiceError(404, 'not_found', 'That date has passed or was taken off the schedule');
  const ref = s.rsvpsCol().doc(`${id}_${occ.key}`);
  const me = (data.members && data.members[uid]) || {};
  const fresh = await s.db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const cur = doc.exists ? doc.data() : { clubId: id, key: occ.key, going: {}, not: {} };
    const going = { ...(cur.going || {}) };
    const not = { ...(cur.not || {}) };
    delete going[uid];
    delete not[uid];
    if (status === 'going') going[uid] = { name: me.name || 'Member', avatarUrl: me.avatarUrl || null, at: nowIso() };
    if (status === 'not') not[uid] = nowIso();
    const next = { clubId: id, key: occ.key, startsAt: occ.startsAt, going, not, updatedAt: nowIso() };
    tx.set(ref, next);
    return next;
  });
  return { occurrence: s.toClientOccurrence(occ, fresh, data, uid) };
}

module.exports = { addMeetup, updateMeetup, deleteMeetup, addEvent, deleteEvent, rsvp };
