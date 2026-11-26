import { describe, expect, it } from 'vitest';
import { invalidationsFor } from './liveInvalidations';

const badges = { messages: ['badge', 'messages'], notifications: ['badge', 'notifications'] };
const keys = (type: string, data?: unknown, me?: string) => invalidationsFor({ type, data }, badges, me);

describe('invalidationsFor', () => {
  it('a new message refreshes the list, that chat and the badge', () => {
    expect(keys('new_message', { messageId: 'm', conversationId: 'c1', senderId: 'u2' }))
      .toEqual([['messages', 'conversations'], ['messages', 'thread', 'c1'], ['badge', 'messages']]);
    expect(keys('new_message', {})).toEqual([['messages', 'conversations'], ['badge', 'messages']]);
  });
  it('notifications refresh the badge and the list', () => {
    expect(keys('new_notification', { id: 'n' })).toEqual([['badge', 'notifications'], ['notifications']]);
    expect(keys('notification_count', { count: 2 })).toEqual([['badge', 'notifications'], ['notifications']]);
  });
  it('activity refreshes the feed', () => {
    ['new_activity', 'activity_comment', 'activity_reaction'].forEach((type) => expect(keys(type, { activityId: 'a' })).toEqual([['feed']]));
  });
  it('connections and follows refresh people, the picker and everyone named (frames as the server sends them)', () => {
    expect(keys('follower_added', { followersCount: 1, followers: ['a'], followerId: 'a' }, 'me'))
      .toEqual([['people'], ['messages', 'people'], ['user', 'a'], ['user', 'me']]);
    expect(keys('following_added', { targetUserId: 'b' }, 'me')).toEqual([['people'], ['messages', 'people'], ['user', 'b'], ['user', 'me']]);
    expect(keys('connection_request', { id: 'conn', userId: 'a', connectedUserId: 'me', status: 'pending' }, 'me'))
      .toEqual([['people'], ['messages', 'people'], ['user', 'a'], ['user', 'me']]);
    expect(keys('connection_request', { connectionId: 'conn', from: { _id: 'b', id: 'b' } })).toEqual([['people'], ['messages', 'people'], ['user', 'b']]);
    expect(keys('connection_declined')).toEqual([['people'], ['messages', 'people']]);
  });
  it('specials refresh rewards and locals', () => {
    expect(keys('specials_updated', { venueId: 'v' })).toEqual([['rewards'], ['locals']]);
  });
  it('anything else changes nothing', () => {
    expect(keys('connected')).toEqual([]);
    expect(keys('video_engagement_update', { x: 1 })).toEqual([]);
    expect(keys('check_in_created', {})).toEqual([]);
  });
});
