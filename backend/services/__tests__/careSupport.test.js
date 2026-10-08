jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}), getMessaging: () => ({}) }));
jest.mock('firebase-admin/firestore', () => ({
  FieldPath: function FieldPath(...p) { this.p = p; },
  FieldValue: { arrayUnion: (...items) => ({ __union: items }), delete: () => ({ __delete: true }) }
}));
const support = require('../careCheckin/support');

describe('family support on an answer', () => {
  test('reactions and responses come out oldest first, unknown kinds dropped', () => {
    const out = support.presentSupport({
      reactions: { sal: { kind: 'love', name: 'Sal', at: '2026-10-07T10:02:00Z' }, wes: { kind: 'proud', name: 'Wes', at: '2026-10-07T10:01:00Z' }, x: { kind: 'nope' } },
      responses: { wes: { action: 'calling', name: 'Wes', at: '2026-10-07T10:03:00Z' }, y: { action: 'teleport' } }
    });
    expect(out.reactions.map(r => r.userId)).toEqual(['wes', 'sal']);
    expect(out.responses).toEqual([{ userId: 'wes', name: 'Wes', action: 'calling', at: '2026-10-07T10:03:00Z' }]);
    expect(support.presentSupport({})).toEqual({ reactions: [], responses: [], comments: [] });
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

// A small stand-in for CareCheckinService: the mixin only needs these.
function fakeService({ asks, plan }) {
  const roles = (p, u) => (u === p.ownerId ? 'owner' : u === p.parentId ? 'parent'
    : (p.watchers || []).some(w => w.userId === u && w.status === 'active') ? 'watcher' : 'none');
  class Svc {
    static roleOf(p, u) { return roles(p, u); }
    static careTeam(p) { return [p.ownerId, ...(p.watchers || []).filter(w => w.status === 'active').map(w => w.userId)]; }
    static canRead(p, u) { return ['owner', 'parent', 'watcher'].includes(roles(p, u)); }
  }
  const svc = new Svc();
  svc.pushes = [];
  svc.asks = { doc: (id) => ({
    get: async () => ({ exists: !!asks[id], id, data: () => asks[id] }),
    update: async (patch) => {
      if (patch.comments && patch.comments.__union) asks[id].comments = [...(asks[id].comments || []), ...patch.comments.__union];
    }
  }) };
  svc.requirePlan = async () => plan;
  svc.recentAsks = async () => Object.entries(asks).map(([id, a]) => ({ id, ...a })).sort((a, b) => b.askedAt.localeCompare(a.askedAt));
  svc.presentAsk = (a) => ({ askId: a.id, status: a.status, answerText: a.answerText, ...support.presentSupport(a) });
  svc.notify = (to, payload) => svc.pushes.push({ to, ...payload });
  Object.assign(svc, support.mixin);
  return svc;
}

describe('comments and a question\'s history', () => {
  const plan = { id: 'p1', ownerId: 'wes', parentId: 'sal', parentName: 'Sal Sgroi', ownerName: 'Wes',
    watchers: [{ userId: 'brit', name: 'Brittany', status: 'active' }] };
  const asks = () => ({
    a3: { planId: 'p1', questionId: 'sleep', questionText: 'How did you sleep?', short: 'Sleep', status: 'answered', answerText: '6/10', askedAt: '2026-10-08T12:30:00Z' },
    a2: { planId: 'p1', questionId: 'water', questionText: 'Water?', status: 'answered', answerText: 'Yes', askedAt: '2026-10-07T17:00:00Z' },
    a1: { planId: 'p1', questionId: 'sleep', questionText: 'How did you sleep?', status: 'answered', answerText: '8/10', askedAt: '2026-10-07T12:30:00Z' },
    a0: { planId: 'p1', questionId: 'sleep', questionText: 'How did you sleep?', status: 'missed', askedAt: '2026-10-06T12:30:00Z' }
  });

  test('askDetail: the answer plus the same question before it, newest first', async () => {
    const svc = fakeService({ asks: asks(), plan });
    const out = await svc.askDetail({ userId: 'wes', askId: 'a3' });
    expect(out.ask.askId).toBe('a3');
    expect(out.history.map(a => a.askId)).toEqual(['a1', 'a0']);
    expect(out.parentName).toBe('Sal Sgroi');
    await expect(svc.askDetail({ userId: 'stranger', askId: 'a3' })).rejects.toMatchObject({ status: 403 });
  });

  test('a family comment pings the parent; the parent\'s reply pings the family', async () => {
    const svc = fakeService({ asks: asks(), plan });
    const one = await svc.commentOnAsk({ userId: 'wes', askId: 'a3', text: '  Get some   rest! ' });
    expect(one.comments.map(c => [c.name, c.text])).toEqual([['Wes', 'Get some rest!']]);
    expect(svc.pushes).toEqual([expect.objectContaining({ to: 'sal', type: 'care_comment',
      title: '💬 Wes: Get some rest!', body: 'About your answer “6/10” (Sleep)', data: { planId: 'p1', askId: 'a3' } })]);
    svc.pushes = [];
    await svc.commentOnAsk({ userId: 'sal', askId: 'a3', text: 'I will' });
    expect(svc.pushes.map(p => p.to).sort()).toEqual(['brit', 'wes']);
    expect(svc.pushes[0].title).toBe('💬 Sal replied: I will');
  });

  test('refuses empty text, strangers and unanswered questions', async () => {
    const svc = fakeService({ asks: { ...asks(), open: { planId: 'p1', status: 'open', askedAt: '2026-10-08T13:00:00Z' } }, plan });
    await expect(svc.commentOnAsk({ userId: 'wes', askId: 'a3', text: '   ' })).rejects.toMatchObject({ status: 400 });
    await expect(svc.commentOnAsk({ userId: 'stranger', askId: 'a3', text: 'hi' })).rejects.toMatchObject({ status: 403 });
    await expect(svc.commentOnAsk({ userId: 'wes', askId: 'open', text: 'hi' })).rejects.toMatchObject({ status: 400 });
  });
});
