// backend/services/careCheckin/questionBank.js
// The questions "How Are You?" can ask, and the words around them.
//
// A question has a KIND, and the kind decides the answers. "Did you get
// outside today?" is not answered with "Okay"; "How much pain are you in?"
// is a number. Each kind is also its own push type and Lock Screen
// category, because the buttons on a notification are baked into the app
// build that registered them (NotificationCategoryRegistry.swift).
//
//   mood   Doing great 👍 / Okay / Not so good      (the original care_ask)
//   done   Yes / Not yet / No                       ("did you … today?")
//   yesno  Yes / No                                 (a state, not a task)
//   scale  0–10 with a low and a high label         (pain, sleep, energy)
//   text   a few typed words                        ("anything on your mind?")
//
// A question can REQUIRE a care-profile flag (only ask about PT when the
// parent has PT), repeat every N days rather than daily, prefer a time of
// day, sit on a fixed weekday, and name the answer that should worry the
// family. The planner (questionPlanner.js) turns this table plus the
// profile into one question per slot.

const KINDS = ['mood', 'done', 'yesno', 'scale', 'text'];

/** Push type per kind. `mood` keeps the original type so older parent builds keep their buttons. */
const ASK_TYPE_BY_KIND = {
  mood: 'care_ask',
  done: 'care_ask_done',
  yesno: 'care_ask_yesno',
  scale: 'care_ask_scale',
  text: 'care_ask_text'
};

/** The choice keys and labels per choice kind. Scale and text have none. */
const CHOICES = {
  mood: { great: 'Doing great 👍', okay: 'Okay', not_great: 'Not so good' },
  done: { yes: 'Yes', not_yet: 'Not yet', no: 'No' },
  yesno: { yes: 'Yes', no: 'No' }
};

const SCALE_MIN = 0;
const SCALE_MAX = 10;
const TEXT_ANSWER_MAX = 300;

/**
 * What the owner answers about the parent once, so the rotation fits them.
 * Order is the order the questionnaire is shown in. Every flag is a plain
 * yes/no; nothing here is diagnostic, it only gates which questions apply.
 */
const PROFILE_FIELDS = [
  { key: 'livesAlone', question: 'Do they live alone?', hint: 'We ask a little more often about company and errands.' },
  { key: 'takesMeds', question: 'Do they take medication every day?', hint: 'Daily "did you take it?" and a weekly "is everything filled?"' },
  { key: 'hasPT', question: 'Are they doing physical therapy right now?', hint: 'A weekly "did you go?" and the home exercises.' },
  { key: 'chronicPain', question: 'Do they deal with ongoing pain?', hint: 'A daily 0–10 so you can see the trend.' },
  { key: 'sleepConcern', question: 'Is sleep a worry?', hint: 'Sleep is asked more often, as 0–10.' },
  { key: 'fallRisk', question: 'Do they use a cane or walker, or have they had a fall?', hint: 'Falls and close calls, dizziness, using the walker.' },
  { key: 'checksBloodSugar', question: 'Do they check their blood sugar at home?', hint: 'A daily "did you check?"' },
  { key: 'checksBloodPressure', question: 'Do they check their blood pressure at home?', hint: 'A daily "did you check?"' },
  { key: 'needsRides', question: 'Do they need rides to appointments?', hint: 'A weekly "anything coming up?" so nobody scrambles.' }
];
const PROFILE_KEYS = PROFILE_FIELDS.map((f) => f.key);

/** Time-of-day phase of a "HH:mm" slot. Used as a preference, never a rule. */
function phaseOf(hhmm) {
  const h = parseInt(String(hhmm).split(':')[0], 10);
  if (!Number.isInteger(h)) return 'any';
  if (h < 11) return 'morning';
  if (h < 17) return 'midday';
  return 'evening';
}

// everyDays: how often at most. weekday: 0 = Sunday … 6 = Saturday, only on
// that day. phases: preferred times of day. requires: a profile flag that must
// be true. weight: how eager the planner is (1 = normal). alert: the answer
// that gets the family a "heads up" instead of a plain answer.
const BANK = [
  // Always — the daily shape of a day
  { id: 'mood_morning', text: 'How are you feeling today?', kind: 'mood', everyDays: 1, phases: ['morning'], weight: 1.4 },
  { id: 'mood_midday', text: 'How is your afternoon going?', kind: 'mood', everyDays: 1, phases: ['midday'], weight: 1.2 },
  { id: 'mood_evening', text: 'How was your day?', kind: 'mood', everyDays: 1, phases: ['evening'], weight: 1.2 },
  { id: 'sleep', text: 'How did you sleep last night?', kind: 'scale', short: 'Sleep', low: 'Terribly', high: 'Wonderfully', everyDays: 1, phases: ['morning'], weight: 1.3, boost: 'sleepConcern', alert: { max: 3 } },
  { id: 'energy', text: 'How is your energy today?', kind: 'scale', short: 'Energy', low: 'Running on empty', high: 'Full of energy', everyDays: 2, phases: ['midday'], alert: { max: 2 } },
  { id: 'meal', text: 'Have you had a proper meal today?', kind: 'done', everyDays: 1, phases: ['midday', 'evening'], weight: 1.2, alert: { value: 'no' } },
  { id: 'water', text: 'Are you drinking enough water today?', kind: 'done', everyDays: 2, phases: ['midday', 'evening'] },
  { id: 'outside', text: 'Did you get outside today?', kind: 'done', everyDays: 1, phases: ['midday', 'evening'] },
  { id: 'company', text: 'Have you talked with anyone today?', kind: 'done', everyDays: 1, phases: ['evening'], boost: 'livesAlone' },
  { id: 'dizzy', text: 'Any dizziness or feeling unsteady today?', kind: 'yesno', everyDays: 3, boost: 'fallRisk', alert: { value: 'yes' } },
  { id: 'mind', text: 'Anything on your mind?', kind: 'text', everyDays: 3 },
  { id: 'smile', text: 'What made you smile today?', kind: 'text', everyDays: 3, phases: ['evening'] },

  // Medication
  { id: 'meds_today', text: 'Did you take your medicine today?', kind: 'done', requires: 'takesMeds', everyDays: 1, phases: ['morning', 'midday'], weight: 1.5, alert: { value: 'no' } },
  { id: 'meds_filled', text: 'Are all your medications filled?', kind: 'yesno', requires: 'takesMeds', everyDays: 7, weekday: 1, alert: { value: 'no' } },

  // Physical therapy
  { id: 'pt_week', text: 'Did you go to PT this week?', kind: 'yesno', requires: 'hasPT', everyDays: 7, weekday: 5, phases: ['midday', 'evening'], alert: { value: 'no' } },
  { id: 'pt_exercises', text: 'Did you do your PT exercises today?', kind: 'done', requires: 'hasPT', everyDays: 2, phases: ['evening'] },

  // Pain
  { id: 'pain', text: 'How much pain are you in today?', kind: 'scale', short: 'Pain', low: 'No pain', high: 'Worst pain', requires: 'chronicPain', everyDays: 1, weight: 1.4, alert: { min: 7 } },

  // Falls and mobility
  { id: 'falls', text: 'Any falls or close calls this week?', kind: 'yesno', requires: 'fallRisk', everyDays: 7, weekday: 0, alert: { value: 'yes' } },
  { id: 'walker', text: 'Are you using your cane or walker when you get up?', kind: 'yesno', requires: 'fallRisk', everyDays: 4 },

  // Home vitals
  { id: 'sugar', text: 'Did you check your blood sugar today?', kind: 'done', requires: 'checksBloodSugar', everyDays: 1, phases: ['morning', 'midday'], weight: 1.3, alert: { value: 'no' } },
  { id: 'bp', text: 'Did you check your blood pressure today?', kind: 'done', requires: 'checksBloodPressure', everyDays: 1, phases: ['morning'], weight: 1.3, alert: { value: 'no' } },

  // Getting around and getting by
  { id: 'rides', text: 'Any appointments coming up that you need a ride to?', kind: 'text', requires: 'needsRides', everyDays: 7, weekday: 3 },
  { id: 'errands', text: 'Do you need anything from the store or around the house?', kind: 'text', requires: 'livesAlone', everyDays: 7, weekday: 4 },
  { id: 'call', text: 'Would you like a call today?', kind: 'yesno', requires: 'livesAlone', everyDays: 3, phases: ['midday', 'evening'], alert: { value: 'yes' } }
];
const BANK_BY_ID = new Map(BANK.map((q) => [q.id, q]));
const BANK_BY_TEXT = new Map(BANK.map((q) => [q.text, q]));
// The eight rotating defaults from before kinds, as older owner builds copied
// them onto plans as the owner's own (mood) questions. Each is a bank
// question now, with the right answers, so the copies are recognised and
// yield to the bank.
const LEGACY_TEXTS = {
  'How are you feeling today?': 'mood_morning',
  'Did you sleep well?': 'sleep',
  'Have you eaten something good today?': 'meal',
  'Did you get outside today?': 'outside',
  'How is your energy today?': 'energy',
  'Anything on your mind?': 'mind',
  'Did you take your medicine today?': 'meds_today',
  'What made you smile today?': 'smile'
};
for (const [text, id] of Object.entries(LEGACY_TEXTS)) if (!BANK_BY_TEXT.has(text)) BANK_BY_TEXT.set(text, BANK_BY_ID.get(id));

/** "Daily", "Every 3 days", "Weekly · Fridays". */
function cadenceLabel(q) {
  const days = q.everyDays || 1;
  const weekday = Number.isInteger(q.weekday) ? ['Sundays', 'Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays'][q.weekday] : null;
  if (days <= 1) return 'Daily';
  if (days >= 7) return weekday ? `Weekly · ${weekday}` : 'Weekly';
  return `Every ${days} days`;
}

/** The kind's answer meta a client needs to render the question. */
function kindMeta(q) {
  const out = { kind: q.kind };
  if (q.kind === 'scale') {
    out.short = q.short || null;
    out.low = q.low || `${SCALE_MIN}`;
    out.high = q.high || `${SCALE_MAX}`;
  }
  return out;
}

/**
 * Validate an answer for a question kind. Returns `{ answer, answerValue,
 * answerScore, answerText }` or null when it does not fit. `answer` is the
 * choice key (older clients read it), `answerValue` the raw value as a string,
 * `answerScore` the number for scales.
 */
function resolveAnswer(question, { answer, value } = {}) {
  const kind = KINDS.includes(question.kind) ? question.kind : 'mood';
  if (CHOICES[kind]) {
    const key = answer !== undefined && answer !== null ? String(answer) : (value !== undefined && value !== null ? String(value) : '');
    const label = CHOICES[kind][key];
    if (!label) return null;
    return { kind, answer: key, answerValue: key, answerScore: null, answerText: label };
  }
  if (kind === 'scale') {
    const raw = value !== undefined && value !== null ? value : answer;
    const n = typeof raw === 'number' ? raw : parseInt(String(raw).trim(), 10);
    if (!Number.isInteger(n) || n < SCALE_MIN || n > SCALE_MAX) return null;
    const short = question.short ? `${question.short} ` : '';
    return { kind, answer: null, answerValue: String(n), answerScore: n, answerText: `${short}${n}/10` };
  }
  // text
  const raw = value !== undefined && value !== null ? value : answer;
  const text = String(raw || '').replace(/\s+/g, ' ').trim().slice(0, TEXT_ANSWER_MAX);
  if (!text) return null;
  return { kind, answer: null, answerValue: text, answerScore: null, answerText: text };
}

/** Whether an answer is the one the family should hear about right away. */
function isAlertAnswer(question, resolved) {
  const rule = question && question.alert;
  if (!rule || !resolved) return false;
  if (rule.value !== undefined) return resolved.answerValue === rule.value;
  if (resolved.answerScore === null || resolved.answerScore === undefined) return false;
  if (rule.min !== undefined && resolved.answerScore >= rule.min) return true;
  if (rule.max !== undefined && resolved.answerScore <= rule.max) return true;
  return false;
}

/** Bank questions that apply to a profile, in bank order. */
function applicable(profile = {}) {
  return BANK.filter((q) => !q.requires || profile[q.requires] === true);
}

module.exports = {
  ASK_TYPE_BY_KIND, BANK, BANK_BY_ID, BANK_BY_TEXT, CHOICES, KINDS, LEGACY_TEXTS, PROFILE_FIELDS, PROFILE_KEYS,
  SCALE_MAX, SCALE_MIN, TEXT_ANSWER_MAX,
  applicable, cadenceLabel, isAlertAnswer, kindMeta, phaseOf, resolveAnswer
};
