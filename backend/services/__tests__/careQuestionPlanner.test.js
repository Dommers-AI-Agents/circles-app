// The question planner is pure: the bank + care profile + what was asked
// lately → one question for this slot. Every "why did Dad get asked about PT
// on a Tuesday" lives here.
const planner = require('../careCheckin/questionPlanner');
const bank = require('../careCheckin/questionBank');
const { anyDeviceAtLeast, atLeast, compareVersions } = require('../../utils/appVersion');

const base = { capable: true, slot: '08:30', weekday: 2, dateKey: '2026-09-22', recent: [] }; // a Tuesday

describe('question planner', () => {
  test('without a profile, nothing that requires a flag is ever asked', () => {
    const ids = new Set();
    let recent = [];
    for (let day = 0; day < 14; day += 1) {
      const dateKey = `2026-09-${String(10 + day).padStart(2, '0')}`;
      for (const slot of ['08:30', '13:00', '19:00']) {
        const q = planner.pick({ ...base, slot, dateKey, weekday: (day + 4) % 7, recent });
        if (!q) continue;
        ids.add(q.id);
        recent.unshift({ questionId: q.id, dateKey });
      }
    }
    for (const id of ids) expect(bank.BANK_BY_ID.get(id).requires).toBeUndefined();
    expect(ids.size).toBeGreaterThan(8); // the rotation is wide, not three questions on repeat
  });

  test('an older parent app only gets mood questions, and the right one for the time of day', () => {
    expect(planner.pick({ ...base, capable: false }).id).toBe('mood_morning');
    expect(planner.pick({ ...base, capable: false, slot: '13:00' }).id).toBe('mood_midday');
    expect(planner.pick({ ...base, capable: false, slot: '19:00' }).id).toBe('mood_evening');
    // The owner's own yes/no question waits for the app update; a legacy custom question (no kind) still goes out.
    const custom = [{ id: 'c1', text: 'Did you call Sue?', kind: 'yesno' }, { id: 'c2', text: 'How are things?' }];
    const recent = [{ questionId: 'mood_morning', dateKey: base.dateKey }];
    expect(planner.pick({ ...base, capable: false, custom, recent }).id).toBe('c2');
  });

  test('profile flags open their questions; a weekday-pinned one goes first on its day', () => {
    const profile = { hasPT: true, takesMeds: true };
    expect(planner.pick({ ...base, profile, slot: '19:00', weekday: 5, dateKey: '2026-09-25' }).id).toBe('pt_week'); // Friday
    expect(planner.pick({ ...base, profile, slot: '19:00', weekday: 4, dateKey: '2026-09-24' }).id).not.toBe('pt_week');
    expect(planner.pick({ ...base, profile, slot: '13:00', weekday: 1, dateKey: '2026-09-21' }).id).toBe('meds_filled'); // Monday
    // Asked last Friday → not again until this Friday, even on a Friday if only 6 days passed... a week is a week.
    const recent = [{ questionId: 'pt_week', dateKey: '2026-09-19' }];
    expect(planner.pick({ ...base, profile, slot: '19:00', weekday: 5, dateKey: '2026-09-25', recent }).id).not.toBe('pt_week');
    const older = [{ questionId: 'pt_week', dateKey: '2026-09-18' }];
    expect(planner.pick({ ...base, profile, slot: '19:00', weekday: 5, dateKey: '2026-09-25', recent: older }).id).toBe('pt_week');
    // With the whole day known, a pinned question waits for the last slot that suits it.
    const friday = { ...base, profile, weekday: 5, dateKey: '2026-09-25', slots: ['08:30', '13:00', '19:00'] };
    expect(planner.pick({ ...friday, slot: '08:30' }).id).not.toBe('pt_week');
    expect(planner.pick({ ...friday, slot: '13:00' }).id).not.toBe('pt_week');
    expect(planner.pick({ ...friday, slot: '19:00' }).id).toBe('pt_week');
    // A parent asked only in the morning still gets it — at the day's last slot.
    expect(planner.pick({ ...friday, slots: ['08:30'], slot: '08:30' }).id).toBe('pt_week');
    expect(planner.pinnedSlot({ phases: ['morning'] }, ['08:30', '10:00', '19:00'])).toBe('10:00');
    expect(planner.pinnedSlot({}, ['08:30', '19:00'])).toBe('19:00');
  });

  test('never the same question twice in a day, and every-N-days questions wait their turn', () => {
    const recent = [{ questionId: 'sleep', dateKey: base.dateKey }, { questionId: 'mood_morning', dateKey: base.dateKey }];
    const q = planner.pick({ ...base, recent });
    expect(['sleep', 'mood_morning']).not.toContain(q.id);
    const energyYesterday = [{ questionId: 'energy', dateKey: '2026-09-21' }];
    const picks = [];
    for (let i = 0; i < 6; i += 1) {
      const p = planner.pick({ ...base, slot: '13:00', recent: [...energyYesterday, ...picks.map((id) => ({ questionId: id, dateKey: base.dateKey }))] });
      if (p) picks.push(p.id);
    }
    expect(picks).not.toContain('energy'); // every 2 days: yesterday's ask blocks today
  });

  test('an own question that is word for word a bank question yields to the bank (the old mood defaults)', () => {
    const custom = [{ id: 'old_default', text: 'Did you get outside today?' }, { id: 'old_sleep', text: 'Did you sleep well?' }, { id: 'own', text: 'Did you water the plants?' }];
    const rot = planner.rotation({ custom });
    expect(rot.filter((q) => q.text === 'Did you get outside today?').map((q) => q.source)).toEqual(['bank']);
    expect(rot.find((q) => q.id === 'old_sleep')).toBeUndefined(); // the old wording of a bank question, too
    expect(Object.keys(bank.LEGACY_TEXTS).every((t) => bank.BANK_BY_TEXT.has(t))).toBe(true);
    expect(rot.find((q) => q.id === 'own')).toMatchObject({ source: 'custom', kind: 'mood' });
    // On an old parent app the mood-kind duplicate must not sneak back in as a mood question.
    const everythingMood = ['mood_morning', 'mood_midday', 'mood_evening', 'own'].map((id) => ({ questionId: id, dateKey: base.dateKey }));
    expect(planner.pick({ ...base, capable: false, custom, recent: everythingMood })).toBeNull();
  });

  test('muted bank questions stay out; custom questions join the rotation daily', () => {
    const profile = { chronicPain: true };
    expect(planner.pick({ ...base, profile, slot: '13:00' }).id).toBe('pain');
    expect(planner.pick({ ...base, profile, slot: '13:00', muted: ['pain'] }).id).not.toBe('pain');
    const custom = [{ id: 'c1', text: 'Did the nurse come?', kind: 'yesno', weight: 5 }];
    expect(planner.pick({ ...base, custom, slot: '13:00' }).id).toBe('c1');
    const rot = planner.rotation({ profile, custom, muted: ['pain'] });
    expect(rot.find((q) => q.id === 'pain')).toMatchObject({ source: 'bank', muted: true });
    expect(rot.find((q) => q.id === 'c1')).toMatchObject({ source: 'custom', muted: false, kind: 'yesno' });
    expect(rot.find((q) => q.id === 'falls')).toBeUndefined();
  });

  test('living alone leans on company and offers a call; everything runs out gracefully', () => {
    const profile = { livesAlone: true };
    const recent = ['mood_evening', 'meal', 'outside', 'smile', 'mind', 'water'].map((id) => ({ questionId: id, dateKey: base.dateKey }));
    const q = planner.pick({ ...base, profile, slot: '19:00', recent });
    expect(['company', 'call', 'dizzy', 'energy']).toContain(q.id);
    const everything = bank.BANK.map((b) => ({ questionId: b.id, dateKey: base.dateKey }));
    expect(planner.pick({ ...base, profile, recent: everything })).toBeNull();
  });

  test('answers resolve by kind and alerts fire on the worrying ones', () => {
    const pain = bank.BANK_BY_ID.get('pain');
    expect(bank.resolveAnswer(pain, { value: 7 })).toMatchObject({ answerScore: 7, answerText: 'Pain 7/10' });
    expect(bank.isAlertAnswer(pain, bank.resolveAnswer(pain, { value: 7 }))).toBe(true);
    expect(bank.isAlertAnswer(pain, bank.resolveAnswer(pain, { value: 6 }))).toBe(false);
    expect(bank.resolveAnswer(pain, { value: 'ten' })).toBeNull();
    const sleep = bank.BANK_BY_ID.get('sleep');
    expect(bank.isAlertAnswer(sleep, bank.resolveAnswer(sleep, { answer: '2' }))).toBe(true);
    const meds = bank.BANK_BY_ID.get('meds_today');
    expect(bank.resolveAnswer(meds, { answer: 'not_yet' })).toMatchObject({ answer: 'not_yet', answerText: 'Not yet' });
    expect(bank.isAlertAnswer(meds, bank.resolveAnswer(meds, { answer: 'not_yet' }))).toBe(false);
    expect(bank.isAlertAnswer(meds, bank.resolveAnswer(meds, { value: 'no' }))).toBe(true);
    const falls = bank.BANK_BY_ID.get('falls');
    expect(bank.isAlertAnswer(falls, bank.resolveAnswer(falls, { answer: 'yes' }))).toBe(true);
    expect(bank.resolveAnswer(falls, { answer: 'not_yet' })).toBeNull();
    const mood = { kind: 'mood' };
    expect(bank.resolveAnswer(mood, { answer: 'not_great' })).toMatchObject({ answerText: 'Not so good' });
    expect(bank.resolveAnswer({}, { answer: 'okay' })).toMatchObject({ kind: 'mood', answerText: 'Okay' }); // legacy ask without a kind
    const mind = bank.BANK_BY_ID.get('mind');
    expect(bank.resolveAnswer(mind, { value: '  the  roof  ' })).toMatchObject({ answerText: 'the roof' });
  });

  test('the bank is well-formed: unique ids and texts, known kinds, scale labels, phases', () => {
    const ids = bank.BANK.map((q) => q.id);
    expect(new Set(ids).size).toBe(ids.length);
    const texts = bank.BANK.map((q) => q.text);
    expect(new Set(texts).size).toBe(texts.length);
    for (const q of bank.BANK) {
      expect(bank.KINDS).toContain(q.kind);
      if (q.kind === 'scale') expect(q.low && q.high && q.short).toBeTruthy();
      if (q.requires) expect(bank.PROFILE_KEYS).toContain(q.requires);
      for (const p of q.phases || []) expect(['morning', 'midday', 'evening']).toContain(p);
      expect(q.text.length).toBeLessThanOrEqual(60); // fits a Lock Screen line
    }
    expect(bank.cadenceLabel({ everyDays: 3 })).toBe('Every 3 days');
    expect(bank.cadenceLabel({ everyDays: 7, weekday: 0 })).toBe('Weekly · Sundays');
    expect(bank.phaseOf('10:59')).toBe('morning');
    expect(bank.phaseOf('17:00')).toBe('evening');
  });

  test('app build gating: a newer version passes alone, the same version needs the build, older apps fail closed', () => {
    const min = { version: '1.3.3', build: 6 };
    expect(atLeast({ version: '1.3.4', build: null }, min)).toBe(true);
    expect(atLeast({ version: '1.3.3', build: 6 }, min)).toBe(true);
    expect(atLeast({ version: '1.3.3', build: 5 }, min)).toBe(false);
    expect(atLeast({ version: '1.3.3', build: null }, min)).toBe(false);
    expect(atLeast({ version: '1.10.0' }, { version: '1.9.9' })).toBe(true);
    expect(atLeast(null, min)).toBe(false);
    expect(compareVersions('1.3', '1.3.0')).toBe(0);
    expect(anyDeviceAtLeast([{ appVersion: '1.3.3', appBuild: 5 }, { appVersion: '1.3.3', appBuild: 6 }], min)).toBe(true);
    expect(anyDeviceAtLeast([{ token: 'x' }], min)).toBe(false);
    expect(anyDeviceAtLeast(undefined, min)).toBe(false);
  });
});
