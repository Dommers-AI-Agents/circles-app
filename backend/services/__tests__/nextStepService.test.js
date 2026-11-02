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
