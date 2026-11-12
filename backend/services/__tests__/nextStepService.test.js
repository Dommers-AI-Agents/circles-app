// Phase 4: the server ranks next steps from what each person does (2026-11-02)
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const { rank } = require('../nextStepService');

test('a reward ready to use comes first and is offered anywhere', () => {
  const r = rank({ rewardReady: true, followingCount: 50, placesCount: 100, hasMoment: true });
  expect(r.order[0]).toBe('my_rewards');
  expect(r.boost).toEqual(['my_rewards']);
});

test('a new person is steered to people and places', () => {
  const r = rank({ followingCount: 1, placesCount: 2 });
  expect(r.order.slice(0, 2)).toEqual(['find_people', 'add_place']);
  expect(r.boost).toEqual(expect.arrayContaining(['find_people', 'add_place']));
});

test('a step they keep skipping sinks and is never boosted', () => {
  const r = rank({ followingCount: 1, stats: { find_people: { shown: 6, tapped: 0 } } });
  expect(r.avoid).toContain('find_people');
  expect(r.order[r.order.length - 1]).toBe('find_people');
  expect(r.boost).not.toContain('find_people');
});

test('a step they tap stays up even after many showings', () => {
  const r = rank({ followingCount: 1, stats: { find_people: { shown: 9, tapped: 1 } } });
  expect(r.avoid).not.toContain('find_people');
  expect(r.order[0]).toBe('find_people');
});

describe('eventUpdate (tour bubbles + next-step chips)', () => {
  const { eventUpdate } = require('../nextStepService');

  test('tour events land under tour.* with the last one remembered', () => {
    const { update, count } = eventUpdate([
      { step: 'tour_add_places', kind: 'shown' },
      { step: 'tour_add_places', kind: 'next' },
      { step: 'tour_follow_users', kind: 'shown' },
      { step: 'tour_follow_users', kind: 'skip' }
    ], { now: '2026-11-12T10:00:00.000Z' });
    expect(count).toBe(4);
    expect(update['tour.tour_add_places.shown']).toBe(1);
    expect(update['tour.tour_follow_users.skip']).toBe(1);
    expect(update.tourLast).toEqual({ step: 'tour_follow_users', action: 'skip', at: '2026-11-12T10:00:00.000Z' });
    expect(Object.keys(update).some((k) => k.startsWith('steps.'))).toBe(false);
  });

  test('next-step chips keep their shown/tapped shape and set no tourLast', () => {
    const { update, count } = eventUpdate([{ step: 'add_place', kind: 'tapped' }, { step: 'add_place', kind: 'whatever' }]);
    expect(count).toBe(2);
    expect(update['steps.add_place.tapped']).toBe(1);
    expect(update['steps.add_place.shown']).toBe(1);
    expect(update.tourLast).toBeUndefined();
  });

  test('unknown steps and unknown tour actions are dropped', () => {
    const { update, count } = eventUpdate([{ step: 'tour_nope', kind: 'shown' }, { step: 'tour_moments', kind: 'tapped' }, { step: 'bogus', kind: 'shown' }]);
    expect(count).toBe(0);
    expect(update).toEqual({});
  });
});
