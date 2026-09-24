// backend/services/careCheckin/shared.js
// Constants, config and pure helpers shared by careCheckinService.js and its ./ mixins.
//
// "How Are You?": an adult child sets up a few times a day when their parent
// gets a short question as a push, answered with one tap from the Lock
// Screen. The child sees every answer and, more importantly, the silence.
//
// Two collections, both keyed so a retried run can't double-ask:
//   carePlans/{ownerId_parentId}   the arrangement (status, questions, times, tz)
//                                  plus `watchers[]` — the other siblings. One
//                                  child sets it up, the rest join it, and the
//                                  parent is asked once rather than once each.
//   careAsks/{planId_YYYY-MM-DD_HHMM}  one question sent at one slot
//
// Every query is equality-only and sorted in memory: no composite indexes.
const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { buildConnectionMap } = require('../connectionMap');
const { normalizeUserId } = require('../idService');
const notificationService = require('../notificationService');
const { localClock, localDateKey } = require('../../utils/localClock');

class CareError extends ServiceError {}

const bank = require('./questionBank');

/** The bank questions that apply with no care profile at all — what an older owner build lists as "rotating defaults". */
const DEFAULT_QUESTIONS = bank.applicable({}).map((q) => q.text);
const DEFAULT_TIMES = ['08:30', '13:00', '19:00'];
/** The mood answers (the original three). Older clients read this map for labels. */
const ANSWERS = bank.CHOICES.mood;
/**
 * The first app build whose Lock Screen has buttons for the non-mood kinds
 * (CARE_DONE / CARE_YESNO / CARE_SCALE / CARE_TEXT). Older parent builds
 * only get mood questions — a question with no buttons is worse than none.
 */
const RICH_ASKS_MIN_CLIENT = { version: '1.3.3', build: 6 };
const MAX_QUESTIONS = 40;
const MAX_TIMES = 5;
const QUESTION_MAX = 120;
const NOTE_MAX = 200;
/** Unanswered this long after the push → the child hears about it. */
const DUE_AFTER_MS = 3 * 60 * 60 * 1000;
/** The scheduler runs every 15 minutes; a slot is "now" inside its window. */
const RUN_WINDOW_MINUTES = 15;
/** Read the plan's queue of questions across runs. */
const TYPES = {
  invite: 'care_invite',
  ask: 'care_ask',
  askByKind: bank.ASK_TYPE_BY_KIND,
  answer: 'care_answer',
  accepted: 'care_accepted',
  watcherRequest: 'care_watcher_request',
  watcherAccepted: 'care_watcher_accepted',
  watcherDeclined: 'care_watcher_declined',
  silence: 'care_silence'
};

const { newId, nowIso } = require('../../utils/ids');
const { clean } = require('../../utils/text');
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

/** "08:30" → "8:30 AM" */
function friendlyTime(hhmm) {
  const [h, m] = String(hhmm).split(':').map((n) => parseInt(n, 10));
  if (!Number.isInteger(h) || !Number.isInteger(m)) return hhmm;
  const suffix = h >= 12 ? 'PM' : 'AM';
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12}:${String(m).padStart(2, '0')} ${suffix}`;
}

function normalizeTimes(times) {
  if (!Array.isArray(times)) return null;
  const valid = [...new Set(times.map((t) => clean(t, 5)).filter((t) => TIME_RE.test(t)))].sort();
  if (valid.length === 0 || valid.length > MAX_TIMES) return null;
  return valid;
}

/**
 * The owner's own questions. Each carries a kind (default: a plain yes/no
 * for a newly typed one; a question already on the plan keeps its kind).
 * A string that is one of the bank's questions is dropped: the bank already
 * asks it, and an older owner build sends the whole default list back when
 * it adds one question of its own.
 */
function normalizeQuestions(questions, existing = []) {
  if (!Array.isArray(questions)) return null;
  const out = [];
  const seen = new Set();
  for (const q of questions.slice(0, MAX_QUESTIONS)) {
    const text = clean(typeof q === 'string' ? q : q && q.text, QUESTION_MAX);
    if (!text || seen.has(text) || bank.BANK_BY_TEXT.has(text)) continue;
    seen.add(text);
    const prior = existing.find((e) => e.text === text) || (q && q.id ? existing.find((e) => e.id === q.id) : null);
    const askedKind = q && typeof q === 'object' && bank.KINDS.includes(q.kind) ? q.kind : null;
    const kind = askedKind || (prior && prior.kind) || (prior ? 'mood' : 'yesno');
    const row = { id: prior ? prior.id : newId(), text, kind, createdAt: prior ? prior.createdAt : nowIso() };
    if (kind === 'scale') {
      const src = q && typeof q === 'object' ? q : {};
      row.short = clean(src.short, 20) || (prior && prior.short) || null;
      row.low = clean(src.low, 30) || (prior && prior.low) || null;
      row.high = clean(src.high, 30) || (prior && prior.high) || null;
    }
    out.push(row);
  }
  return out;
}

/** Only the known flags, only as booleans; unknown keys are dropped. */
function normalizeProfile(profile) {
  if (!profile || typeof profile !== 'object' || Array.isArray(profile)) return null;
  const out = {};
  for (const key of bank.PROFILE_KEYS) out[key] = profile[key] === true;
  return out;
}

/** Bank ids the owner switched off; anything that is not a bank id is ignored. */
function normalizeMuted(ids) {
  if (!Array.isArray(ids)) return null;
  return [...new Set(ids.map((id) => clean(id, 40)).filter((id) => bank.BANK_BY_ID.has(id)))];
}

module.exports = { ANSWERS, RICH_ASKS_MIN_CLIENT, bank, normalizeMuted, normalizeProfile, COLLECTIONS, CareError, DEFAULT_QUESTIONS, DEFAULT_TIMES, DUE_AFTER_MS, MAX_QUESTIONS, MAX_TIMES, NOTE_MAX, QUESTION_MAX, RUN_WINDOW_MINUTES, TIME_RE, TYPES, buildConnectionMap, clean, friendlyTime, getFirestore, localClock, localDateKey, newId, normalizeQuestions, normalizeTimes, normalizeUserId, notificationService, nowIso };
