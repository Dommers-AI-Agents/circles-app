import { describe, expect, it } from 'vitest';
import {
  chunk, conversationPreview, conversationTitle, enterSends, filterPeople, firstName, isDeleted, listTime, mergeMessages, messageActions,
  messageablePeople, newestFirst, oldestStamp, otherPerson, previewText, readByOther, unreadCount, unreadIds
} from './chatThread';

const me = 'me';
const direct = { _id: 'c1', type: 'direct', participants: ['me', 'sam'], participantDetails: [{ _id: 'sam', displayName: 'Sam Rivera', profilePicture: 'https://x/s.jpg' }] };

describe('who a chat is with', () => {
  it('a one-on-one chat is the other person', () => {
    expect(otherPerson(direct, me)?.displayName).toBe('Sam Rivera');
    expect(conversationTitle(direct, me)).toBe('Sam Rivera');
    expect(firstName(otherPerson(direct, me))).toBe('Sam');
    expect(firstName({ displayName: 'Sam Rivera', firstName: 'Samuel' })).toBe('Samuel');
    expect(firstName(null)).toBe('');
  });
  it('falls back to the id when the person\'s card is missing', () => {
    expect(otherPerson({ type: 'direct', participants: ['me', 'gone'], participantDetails: [] }, me)).toEqual({ _id: 'gone' });
    expect(conversationTitle({ type: 'direct', participants: ['me', 'gone'] }, me)).toBe('FavCircles member');
  });
  it('a group has a name and no single person', () => {
    expect(otherPerson({ type: 'group', participants: ['me', 'a', 'b'] }, me)).toBeNull();
    expect(conversationTitle({ type: 'group', name: 'Supper club' }, me)).toBe('Supper club');
    expect(conversationTitle({ type: 'group', name: ' ' }, me)).toBe('Group chat');
    expect(conversationTitle(null, me)).toBe('Chat');
  });
});

describe('the conversations list', () => {
  it('says "You:" for mine, the sender in a group, nothing for theirs', () => {
    expect(conversationPreview({ ...direct, lastMessage: 'See you there', lastMessageSenderId: 'me' }, me)).toBe('You: See you there');
    expect(conversationPreview({ ...direct, lastMessage: 'See you\n there', lastMessageSenderId: 'sam' }, me)).toBe('See you there');
    expect(conversationPreview({ type: 'group', lastMessage: 'Friday?', lastMessageSenderId: 'kim', lastMessageSenderName: 'Kim Lee' }, me)).toBe('Kim: Friday?');
    expect(conversationPreview({ ...direct, lastMessage: null }, me)).toBe('No messages yet');
  });
  it('has words for photos, shares and deleted messages', () => {
    expect(previewText('[image]')).toBe('📷 Photo');
    expect(previewText('', 'image')).toBe('📷 Photo');
    expect(previewText('[location]')).toBe('📌 Location');
    expect(previewText('[Message deleted]')).toBe('Message deleted');
    expect(previewText('📍 Pasta & Provisions')).toBe('📍 Pasta & Provisions');
    expect(previewText('[circle_share]')).toBe('⭕️ A circle');
    expect(previewText('[place_share]')).toBe('📍 A place');
    expect(previewText('[something_new]')).toBe('Message');
    expect(conversationPreview({ ...direct, lastMessage: '[image]', lastMessageSenderId: 'me' }, me)).toBe('You: 📷 Photo');
  });
  it('reads my unread count only', () => {
    expect(unreadCount({ unreadCounts: { me: 3, sam: 9 } }, me)).toBe(3);
    expect(unreadCount({ unreadCounts: { sam: 9 } }, me)).toBe(0);
    expect(unreadCount({ unreadCounts: null }, me)).toBe(0);
    expect(unreadCount({ unreadCounts: { me: -2 } }, me)).toBe(0);
  });
  it('shows when a chat last moved', () => {
    const clock = { timeZone: 'America/New_York', locale: 'en-US', now: new Date('2026-11-23T17:00:00Z') }; // Monday noon
    expect(listTime('2026-11-23T15:05:00Z', clock).replace(/\s/g, ' ')).toBe('10:05 AM');
    expect(listTime('2026-11-22T15:05:00Z', clock)).toBe('Yesterday');
    expect(listTime('2026-11-19T15:05:00Z', clock)).toBe('Thu');
    expect(listTime('2026-11-03T15:05:00Z', clock)).toBe('Nov 3');
    expect(listTime('2025-11-03T15:05:00Z', clock)).toBe('Nov 3, 2025');
    expect(listTime(null, clock)).toBe('');
    expect(listTime('rubbish', clock)).toBe('');
  });
  it('sorts newest first and keeps ties in the server\'s order', () => {
    const list = [{ _id: 'a', lastMessageTime: '2026-11-01T00:00:00Z' }, { _id: 'b', lastMessageTime: '2026-11-03T00:00:00Z' },
      { _id: 'c', createdAt: '2026-11-02T00:00:00Z' }, { _id: 'd', lastMessageTime: '2026-11-03T00:00:00Z' }];
    expect(newestFirst(list).map((c) => c._id)).toEqual(['b', 'd', 'c', 'a']);
  });
});

describe('messages', () => {
  const m = (id: string, createdAt: string, extra: object = {}) => ({ _id: id, senderId: 'sam', createdAt, ...extra });
  it('joins pages oldest first, each message once, newer copy wins', () => {
    const have = [m('b', '2'), m('c', '3')];
    const merged = mergeMessages(have, [m('a', '1'), m('b', '2', { content: 'edited' }), m('d', '4')]);
    expect(merged.map((x) => x._id)).toEqual(['a', 'b', 'c', 'd']);
    expect((merged[1] as { content?: string }).content).toBe('edited');
    expect(mergeMessages(have, [])).toBe(have);
  });
  it('marks read only what someone else sent and I have not read', () => {
    const list = [m('a', '1', { readBy: ['sam'] }), m('b', '2', { readBy: ['sam', 'me'] }), { _id: 'c', senderId: 'me', readBy: ['me'], createdAt: '3' }, m('d', '4', { readBy: null })];
    expect(unreadIds(list, me)).toEqual(['a', 'd']);
    expect(unreadIds(list, me, new Set(['a']))).toEqual(['d']);
    expect(unreadIds(list, undefined)).toEqual([]);
  });
  it('knows when the other person has read mine', () => {
    expect(readByOther({ senderId: 'me', readBy: ['me'] })).toBe(false);
    expect(readByOther({ senderId: 'me', readBy: ['me', 'sam'] })).toBe(true);
    expect(readByOther({ senderId: 'me' })).toBe(false);
  });
  it('chunks and finds the paging cursor', () => {
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
    expect(chunk([], 2)).toEqual([]);
    expect(oldestStamp([m('a', '1'), m('b', '2')])).toBe('1');
    expect(oldestStamp([])).toBeUndefined();
  });
});

describe('the composer', () => {
  it('Enter sends on a computer and not on a phone', () => {
    expect(enterSends({ key: 'Enter' }, false)).toBe(true);
    expect(enterSends({ key: 'Enter' }, true)).toBe(false);
    expect(enterSends({ key: 'Enter', shiftKey: true }, false)).toBe(false);
    expect(enterSends({ key: 'Enter', isComposing: true }, false)).toBe(false);
    expect(enterSends({ key: 'a' }, false)).toBe(false);
  });
});

describe('picking a person', () => {
  const people = [{ _id: '1', displayName: 'Sam Rivera' }, { _id: '2', displayName: 'Kim Lee' }, { _id: '3', displayName: null }];
  it('filters by name', () => {
    expect(filterPeople(people, '')).toBe(people);
    expect(filterPeople(people, 'riv').map((p) => p._id)).toEqual(['1']);
    expect(filterPeople(people, 'KIM l').map((p) => p._id)).toEqual(['2']);
    expect(filterPeople(people, 'zzz')).toEqual([]);
  });
  it('lists connections first, then people I follow, nobody twice and never me', () => {
    const list = messageablePeople<{ _id?: string; id?: string }>([{ _id: 'a' }, { id: 'b' }], [{ id: 'b' }, { id: 'c' }, { id: 'me' }, {}], 'me');
    expect(list).toEqual([{ _id: 'a', connected: true }, { id: 'b', connected: true }, { id: 'c', connected: false }]);
  });
});

describe('message actions', () => {
  const base = { senderId: 'me', type: 'text', content: 'Hello' };
  it('lets me copy, edit and delete my own text', () => {
    expect(messageActions(base, 'me')).toEqual({ copy: true, edit: true, remove: true });
  });
  it('lets me only copy theirs', () => {
    expect(messageActions({ ...base, senderId: 'sam' }, 'me')).toEqual({ copy: true, edit: false, remove: false });
  });
  it('edits text only; a photo can be deleted', () => {
    expect(messageActions({ ...base, type: 'image', content: '' }, 'me')).toEqual({ copy: false, edit: false, remove: true });
    expect(messageActions({ ...base, type: 'place_share', content: '📍 Sal’s' }, 'me')).toEqual({ copy: true, edit: false, remove: true });
  });
  it('does nothing to a deleted message', () => {
    expect(isDeleted({ ...base, content: '[Message deleted]' })).toBe(true);
    expect(isDeleted({ ...base, deletedAt: '2026-11-26T10:00:00Z' })).toBe(true);
    expect(messageActions({ ...base, deletedAt: '2026-11-26T10:00:00Z' }, 'me')).toEqual({ copy: false, edit: false, remove: false });
    expect(messageActions({ ...base, content: '[image]' }, 'me').copy).toBe(false);
  });
});
