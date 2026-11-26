import { describe, expect, it } from 'vitest';
import { notificationMark, notificationPath } from './notificationRoute';

describe('notificationPath', () => {
  it.each([
    ['new_message', { conversationId: 'c1' }, '/messages/c1'],
    ['new_message', {}, '/messages'],
    ['connection_request', { fromUserId: 'u1', connectionId: 'x' }, '/people'],
    ['follow_request', { fromUserId: 'u1' }, '/people'],
    ['starter_follow', {}, '/people'],
    ['connection_accepted', { acceptedByUserId: 'u2', fromUserId: 'u1' }, '/user/u2'],
    ['connection_accepted', { fromUserId: 'u1' }, '/user/u1'],
    ['connection_accepted', {}, '/people'],
    ['new_follower', { fromUserId: 'u1' }, '/user/u1'],
    ['user_followed', { actorId: 'u3' }, '/user/u3'],
    ['follow_request_accepted', { fromUserId: 'u1' }, '/user/u1'],
    ['new_follower', {}, '/people'],
    ['store_alert', { venueId: 'v1', placeId: 'g1' }, '/rewards/v1'],
    ['store_alert', { placeId: 'g1', storeCode: '5GJRC2' }, '/place/g1'],
    ['store_nudge', { venueId: 'v1' }, '/rewards/v1'],
    ['store_nudge', {}, '/rewards'],
    ['new_suggestion', { placeId: 'p1', fromUserId: 'u1' }, '/place/p1'],
    ['new_suggestion', { fromUserId: 'u1' }, '/user/u1'],
    ['new_place', { circleId: 'c1', placeId: 'p1' }, '/circle/c1'],
    ['circle_liked', { circleId: 'c1' }, '/circle/c1'],
    ['circle_commented', {}, '/feed'],
    ['place_like', { placeId: 'p1', fromUserId: 'u1' }, '/place/p1'],
    ['place_liked', { placeId: 'p1' }, '/place/p1'],
    ['place_comment', { placeId: 'p1' }, '/place/p1'],
    ['place_commented', { activityId: 'a1' }, '/feed'],
    ['check_in', { placeId: 'p1' }, '/place/p1'],
    ['check_in_response', { placeId: 'p1' }, '/place/p1'],
    ['waitlist_ready', { placeId: 'g1' }, '/place/g1'],
    ['receipt_result', { placeId: 'g1' }, '/place/g1'],
    ['moment_tag', { videoId: 'v1', placeId: 'p1' }, '/place/p1'],
    ['moment_tag', { videoId: 'v1' }, '/feed'],
    ['activity_reaction', { activityId: 'a1', placeId: 'p1', fromUserId: 'u1' }, '/place/p1'],
    ['activity_reaction', { activityId: 'a1', circleId: 'c1' }, '/circle/c1'],
    ['activity_reaction', { activityId: 'a1', videoId: 'v1', fromUserId: 'u1' }, '/feed'],
    ['activity_comment', { activityId: 'a1', fromUserId: 'u1', commentText: 'hi' }, '/feed'],
    ['store_claim_approved', { placeId: 'g1' }, '/me'],
    ['favcoin_claim_settled', {}, '/rewards'],
    ['starter_map', {}, '/'],
    ['milestone', { milestoneType: 'places' }, '/feed'],
    ['care_answer', { askId: 'q1' }, '/feed'],
    // Types the table doesn't name: whatever the row carries, in the app's order
    ['brand_new', { activityId: 'a1', placeId: 'p1' }, '/feed'],
    ['brand_new', { circleId: 'c1', placeId: 'p1' }, '/circle/c1'],
    ['brand_new', { placeId: 'p1', fromUserId: 'u1' }, '/place/p1'],
    ['brand_new', { conversationId: 'c1' }, '/messages/c1'],
    ['brand_new', { fromUserId: 'u1' }, '/user/u1'],
    ['brand_new', {}, '/feed']
  ] as [string, Record<string, unknown>, string][])('%s %j → %s', (type, data, expected) => {
    expect(notificationPath(type, data)).toBe(expected);
  });

  it('never throws on a row with nothing in it', () => {
    expect(notificationPath(undefined, undefined)).toBe('/feed');
    expect(notificationPath(null, null)).toBe('/feed');
    expect(notificationPath('place_like', { placeId: '' })).toBe('/feed');
    expect(notificationPath('place_like', { placeId: { nested: true } })).toBe('/feed');
  });
  it('escapes ids', () => {
    expect(notificationPath('new_message', { conversationId: 'a/b' })).toBe('/messages/a%2Fb');
  });
});

describe('notificationMark', () => {
  it('has a mark for every row', () => {
    expect(notificationMark('place_like')).toBe('❤️');
    expect(notificationMark('activity_comment')).toBe('💬');
    expect(notificationMark('care_silence')).toBe('💗');
    expect(notificationMark('whatever')).toBe('🔔');
  });
});
