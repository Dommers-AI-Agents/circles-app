// Who can be put in a conversation and who can still write in one
// (security audit 2026-10-01).
jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
const { vetParticipants, checkMessageContent, directChatBlocked, MAX_PARTICIPANTS } = require('../conversationAccess');

const connectedIds = new Set(['britt', 'joe', 'blocky']);

test('connections only; the creator and duplicates are folded out', async () => {
  const others = await vetParticipants({
    creatorId: 'wes', creatorData: {}, participantIds: ['britt', 'joe', 'britt', 'wes'], connectedIds
  });
  expect(others).toEqual(['britt', 'joe']);
});

test('a stranger in the list refuses the whole group', async () => {
  await expect(vetParticipants({
    creatorId: 'wes', creatorData: {}, participantIds: ['britt', 'stranger'], connectedIds
  })).rejects.toMatchObject({ status: 403, code: 'not_connected', details: { notConnected: ['stranger'] } });
});

test('blocked either way refuses', async () => {
  await expect(vetParticipants({
    creatorId: 'wes', creatorData: { blockedBy: ['blocky'] }, participantIds: ['blocky'], connectedIds
  })).rejects.toMatchObject({ status: 403, code: 'blocked' });
});

test('bad shapes and oversize groups refuse with a 400', async () => {
  await expect(vetParticipants({ creatorId: 'wes', creatorData: {}, participantIds: 'britt', connectedIds }))
    .rejects.toMatchObject({ status: 400 });
  await expect(vetParticipants({ creatorId: 'wes', creatorData: {}, participantIds: ['wes'], connectedIds }))
    .rejects.toMatchObject({ status: 400 });
  const many = Array.from({ length: MAX_PARTICIPANTS }, (_, i) => `u${i}`);
  await expect(vetParticipants({ creatorId: 'wes', creatorData: {}, participantIds: many, connectedIds: new Set(many) }))
    .rejects.toMatchObject({ status: 400, code: 'too_many_participants' });
});

test('message bodies are bounded', () => {
  expect(() => checkMessageContent('hi')).not.toThrow();
  expect(() => checkMessageContent(undefined)).not.toThrow();
  expect(() => checkMessageContent('x'.repeat(4001))).toThrow(/4000/);
  expect(() => checkMessageContent({ evil: true })).toThrow();
});

test('a blocked direct chat refuses new messages; groups are unaffected', () => {
  const direct = { type: 'direct', participants: ['wes', 'sal'] };
  expect(directChatBlocked(direct, 'wes', { blockedUsers: ['sal'] })).toBe(true);
  expect(directChatBlocked(direct, 'wes', { blockedBy: ['sal'] })).toBe(true);
  expect(directChatBlocked(direct, 'wes', {})).toBe(false);
  expect(directChatBlocked({ type: 'group', participants: ['wes', 'sal'] }, 'wes', { blockedUsers: ['sal'] })).toBe(false);
});
