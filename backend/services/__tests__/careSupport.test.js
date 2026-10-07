jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), getMessaging: () => ({}) }));
const support = require('../careCheckin/support');

describe('family support on an answer', () => {
  test('reactions and responses come out oldest first, unknown kinds dropped', () => {
    const out = support.presentSupport({
      reactions: { sal: { kind: 'love', name: 'Sal', at: '2026-10-07T10:02:00Z' }, wes: { kind: 'proud', name: 'Wes', at: '2026-10-07T10:01:00Z' }, x: { kind: 'nope' } },
      responses: { wes: { action: 'calling', name: 'Wes', at: '2026-10-07T10:03:00Z' }, y: { action: 'teleport' } }
    });
    expect(out.reactions.map(r => r.userId)).toEqual(['wes', 'sal']);
    expect(out.responses).toEqual([{ userId: 'wes', name: 'Wes', action: 'calling', at: '2026-10-07T10:03:00Z' }]);
    expect(support.presentSupport({})).toEqual({ reactions: [], responses: [] });
  });

  test('push wording', () => {
    expect(support.reactionPush('Wes', 'love', { answerText: 'Great', short: null }))
      .toEqual({ title: '❤️ Wes: Love you', body: 'About your answer “Great”' });
    expect(support.reactionPush('Wes', 'glad', { answerText: '3/10', short: 'Pain' }).body).toBe('About your answer “3/10” (Pain)');
    expect(support.RESPONSES.calling.parentLine('Wes')).toBe('Wes is going to call you soon');
    expect(support.RESPONSES.got_it.parentLine).toBeNull();
    expect(support.RESPONSES.on_my_way.teamLine('Wes', 'Mom')).toBe('Wes is on the way to Mom');
  });
});
