import { describe, expect, it } from 'vitest';
import type { Activity } from '../api/feed';
import { activityCard, groupSummary, picturesOf, pinOf, posterOf, sentenceOf, targetOf, tintOf } from './activityCopy';

const row = (over: Partial<Activity>): Activity => ({
  _id: 'a1', type: 'place_added', actorId: 'u1', actor: { _id: 'u1', displayName: 'Brittany' },
  targetType: 'place', targetId: 'save1', targetName: 'STIR', circleId: 'c1', circleName: 'Date Night',
  metadata: {}, timestamp: '2026-11-25T16:45:00.000Z', ...over
});

describe('sentenceOf', () => {
  it.each([
    ['place_added', {}, 'saved STIR to Date Night'],
    ['place_added', { circleName: null }, 'saved STIR to a circle'],
    ['place_liked', {}, 'liked STIR'],
    ['place_commented', {}, 'commented on STIR'],
    ['circle_created', { targetName: 'Tucson' }, 'created a new circle Tucson'],
    ['comment_liked', { targetName: 'Comment on Chill House' }, 'liked a comment on Chill House'],
    ['comment_liked', { targetName: 'Chill House' }, 'liked a comment on Chill House'],
    ['check_in', {}, 'checked in at STIR'],
    ['video_uploaded', {}, 'uploaded a video at STIR'],
    ['video_uploaded', { metadata: { contentType: 'photo' } }, 'shared a photo at STIR'],
    ['photo_uploaded', {}, 'uploaded a photo at STIR'],
    ['place_discovered', {}, 'discovered STIR'],
    ['global_place_liked', {}, 'liked a photo at STIR'],
    ['video_liked', { targetName: "Moment at Antonio's" }, "liked Moment at Antonio's"],
    ['comment_added', {}, 'commented on STIR'],
    ['circle_liked', { targetName: 'Brunch' }, 'liked the circle Brunch'],
    ['circle_commented', { targetName: 'Brunch' }, 'commented on the circle Brunch'],
    ['suggestion_sent', {}, 'suggested STIR'],
    ['suggestion_accepted', {}, 'accepted a suggestion for STIR'],
    ['profile_updated', {}, 'updated their profile'],
    ['user_activity', {}, 'was active'],
    ['reaction_added', {}, 'reacted to STIR'],
    ['venue_announcement', { metadata: { message: 'Live music Friday' } }, 'posted an announcement: Live music Friday'],
    ['venue_announcement', {}, 'posted an announcement'],
    ['venue_offer', { metadata: { message: 'Free cookie' } }, 'added a new offer: Free cookie'],
    ['venue_offer', { metadata: { message: '  ' } }, 'added a new offer'],
    ['workout_shared', { targetName: 'Leg day' }, 'finished a workout: Leg day'],
    ['run_shared', { metadata: { runDetail: '3.10 mi · 26:40 · 8:36/mi' } }, 'went for a run 🏃 3.10 mi · 26:40 · 8:36/mi'],
    ['run_shared', {}, 'went for a run 🏃'],
    ['postcard_sent', { targetName: 'Mom' }, 'sent a postcard to Mom'],
    ['postcard_mailed', { targetName: 'Mom' }, 'mailed a printed postcard to Mom'],
    ['fridgemail_sent', { targetName: 'Grandpa' }, 'mailed Fridge Mail to Grandpa'],
    ['something_new_2027', {}, 'shared an update']
  ] as [string, Partial<Activity>, string][])('%s %j → %s', (type, over, expected) => {
    expect(sentenceOf(row({ type, ...over }))).toBe(expected);
  });

  it('never leaves a hole when the name is missing', () => {
    expect(sentenceOf(row({ type: 'place_liked', targetName: null }))).toBe('liked a place');
    expect(sentenceOf(row({ type: 'circle_liked', targetName: '' }))).toBe('liked the circle a circle');
    expect(sentenceOf(row({ type: 'video_liked', targetName: undefined }))).toBe('liked a moment');
    expect(sentenceOf(row({ type: 'postcard_sent', targetName: null, metadata: { recipientName: 'Sal' } }))).toBe('sent a postcard to Sal');
  });
});

describe('picturesOf', () => {
  it('is the place photo, then the pin', () => {
    expect(picturesOf(row({ metadata: { placePhoto: 'https://x/p.jpg', latitude: 35.2, longitude: -80.8 } })))
      .toEqual([{ kind: 'photo', url: 'https://x/p.jpg' }, { kind: 'map', lat: 35.2, lng: -80.8 }]);
  });
  it('is the pin alone when there is no photo', () => {
    expect(picturesOf(row({ metadata: { placePhoto: null, latitude: 35.2, longitude: -80.8 } }))).toEqual([{ kind: 'map', lat: 35.2, lng: -80.8 }]);
  });
  it('is nothing (so the poster) with neither', () => {
    expect(picturesOf(row({ metadata: { placePhoto: '', latitude: null, longitude: null } }))).toEqual([]);
    expect(picturesOf(row({ metadata: null }))).toEqual([]);
  });
  it('shows a moment by its thumbnail first, a postcard by its picture', () => {
    const meta = { placePhoto: 'https://x/place.jpg', videoThumbnail: 'https://x/thumb.jpg', imageUrl: 'https://x/card.jpg' };
    expect(picturesOf(row({ type: 'video_liked', metadata: meta }))[0]).toEqual({ kind: 'photo', url: 'https://x/thumb.jpg' });
    expect(picturesOf(row({ type: 'postcard_sent', metadata: meta }))[0]).toEqual({ kind: 'photo', url: 'https://x/card.jpg' });
    expect(picturesOf(row({ type: 'place_liked', metadata: meta })).map((p) => p.kind)).toEqual(['photo', 'photo', 'photo']);
  });
  it('drops repeats and anything that is not a web address', () => {
    expect(picturesOf(row({ metadata: { placePhoto: 'https://x/p.jpg', imageUrl: 'https://x/p.jpg', videoThumbnail: 'javascript:alert(1)' } })))
      .toEqual([{ kind: 'photo', url: 'https://x/p.jpg' }]);
  });
});

describe('pinOf', () => {
  it('needs a real coordinate', () => {
    expect(pinOf({ latitude: 0, longitude: 0 })).toBeNull();
    expect(pinOf({ latitude: 95, longitude: 10 })).toBeNull();
    expect(pinOf({ latitude: 10, longitude: 200 })).toBeNull();
    expect(pinOf({ latitude: null, longitude: -80 })).toBeNull();
    expect(pinOf({ latitude: '35' as unknown as number, longitude: -80 })).toBeNull();
    expect(pinOf(undefined)).toBeNull();
    expect(pinOf({ latitude: 0, longitude: -80 })).toEqual({ lat: 0, lng: -80 });
  });
});

describe('posterOf', () => {
  it('wears the place category mark when the row has one', () => {
    expect(posterOf(row({ type: 'place_added', metadata: { placeCategory: 'cafe', placeAddress: '1 Main St' } })))
      .toEqual({ mark: '☕', title: 'STIR', detail: '1 Main St', tint: 'brand' });
  });
  it('wears the mark of what happened otherwise', () => {
    expect(posterOf(row({ type: 'circle_created', targetName: 'Tucson', metadata: { placeCategory: 'bar' } }))).toEqual({ mark: '⭕', title: 'Tucson', detail: null, tint: 'circle' });
    expect(posterOf(row({ type: 'run_shared', metadata: { runDetail: '3 mi' } }))).toEqual({ mark: '🏃', title: 'Went for a run', detail: '3 mi', tint: 'run' });
    expect(posterOf(row({ type: 'venue_offer', targetName: "Sal's Bakery", metadata: { message: 'Free cookie' } })))
      .toEqual({ mark: '🎁', title: 'Free cookie', detail: "Sal's Bakery", tint: 'store' });
    expect(posterOf(row({ type: 'workout_shared', targetName: 'Leg day', metadata: { workoutDetail: '5 exercises · 54 min', workoutPlaceName: 'Dowd YMCA' } })))
      .toEqual({ mark: '🏋️', title: 'Leg day', detail: '5 exercises · 54 min · Dowd YMCA', tint: 'workout' });
    expect(posterOf(row({ type: 'postcard_sent', targetName: 'Mom' })).title).toBe('To Mom');
  });
  it('always has a title, even for a type nobody has seen', () => {
    expect(posterOf(row({ type: 'brand_new', targetName: null, metadata: null }))).toEqual({ mark: '✨', title: 'Shared an update', detail: null, tint: 'brand' });
    expect(posterOf(row({ type: 'brand_new', targetName: 'Something' })).title).toBe('Something');
    expect(posterOf(row({ type: 'profile_updated' })).title).toBe('Updated their profile');
  });
});

describe('targetOf', () => {
  it.each([
    ['place_added', { targetId: 'save1' }, '/place/save1'],
    ['place_liked', { targetId: 'save1' }, '/place/save1'],
    ['place_commented', { targetId: 'save1' }, '/place/save1'],
    ['place_added', { targetId: null, metadata: { globalPlaceId: 'g1' } }, '/place/g1'],
    // targetId is the check-in, the comment, the photo or the moment: never opened as a place
    ['check_in', { targetId: 'checkin9', metadata: { placeId: 'p1', globalPlaceId: 'g1' } }, '/place/p1'],
    ['check_in', { targetId: 'checkin9', metadata: { globalPlaceId: 'g1' } }, '/place/g1'],
    ['check_in', { targetId: 'checkin9', metadata: {} }, '/user/u1'],
    ['comment_liked', { targetId: 'comment9', metadata: { placeId: 'p1' } }, '/place/p1'],
    ['comment_liked', { targetId: 'comment9', metadata: {} }, '/user/u1'],
    ['global_place_liked', { targetId: 'photo9', metadata: { globalPlaceId: 'g1' } }, '/place/g1'],
    ['global_place_liked', { targetId: 'photo9', metadata: {} }, '/user/u1'],
    ['video_liked', { targetId: 'video9', metadata: { placeId: 'p1' } }, '/place/p1'],
    ['video_uploaded', { targetId: 'video9', metadata: {} }, '/user/u1'],
    ['photo_uploaded', { targetId: 'g2', metadata: { globalPlaceId: 'g1' } }, '/place/g1'],
    ['photo_uploaded', { targetId: 'g2', metadata: {} }, '/place/g2'],
    ['venue_announcement', { targetId: 'g1' }, '/place/g1'],
    ['venue_offer', { targetId: 'g1' }, '/place/g1'],
    ['circle_created', { targetId: 'c9' }, '/circle/c9'],
    ['circle_liked', { targetId: 'c9' }, '/circle/c9'],
    ['circle_commented', { targetId: 'c9' }, '/circle/c9'],
    ['comment_added', { targetType: 'circle', targetId: 'c9' }, '/circle/c9'],
    ['comment_added', { targetType: 'place', targetId: 'p9' }, '/place/p9'],
    ['comment_added', { targetType: 'video', targetId: 'v9' }, '/user/u1'],
    ['run_shared', { targetId: 'run9', metadata: {} }, '/user/u1'],
    ['workout_shared', { targetId: 'post9', metadata: { globalPlaceId: 'gym1' } }, '/place/gym1'],
    ['postcard_sent', { targetId: 'x' }, '/user/u1'],
    ['profile_updated', { targetId: 'x' }, '/user/u1'],
    ['suggestion_sent', { targetId: 'x' }, '/user/u1'],
    ['brand_new', { targetType: 'place', targetId: 'p9' }, '/place/p9'],
    ['brand_new', { targetType: 'circle', targetId: 'c9' }, '/circle/c9'],
    ['brand_new', { targetType: 'user', targetId: 'u9' }, '/user/u9'],
    ['brand_new', { targetType: 'widget', targetId: 'w9', metadata: null }, '/user/u1']
  ] as [string, Partial<Activity>, string][])('%s %j → %s', (type, over, expected) => {
    expect(targetOf(row({ type, ...over }))).toBe(expected);
  });

  it('escapes ids', () => {
    expect(targetOf(row({ type: 'circle_created', targetId: 'a/b' }))).toBe('/circle/a%2Fb');
  });
});

describe('activityCard', () => {
  it('sends a store actor to its place page', () => {
    const card = activityCard(row({ type: 'venue_offer', actorId: 'place_g1', actor: { _id: 'place_g1', displayName: "Sal's Bakery", isPlace: true }, targetId: 'g1', metadata: { message: 'Free cookie' } }));
    expect(card.actorPath).toBe('/place/g1');
    expect(card.target).toBe('/place/g1');
    expect(card.actorName).toBe("Sal's Bakery");
    expect(card.chip).toBe('🎁 New offer');
  });
  it('quotes a comment or a check-in note', () => {
    expect(activityCard(row({ type: 'place_commented', metadata: { comment: 'Cool little ice cream place!' } })).quote).toBe('Cool little ice cream place!');
    expect(activityCard(row({ type: 'check_in', metadata: { message: 'Trivia night', comment: 'not this' } })).quote).toBe('Trivia night');
    expect(activityCard(row({ type: 'place_added', metadata: { comment: 'x', message: 'y' } })).quote).toBeNull();
  });
  it('says what happened on the picture', () => {
    expect(activityCard(row({})).chip).toBe('Saved to Date Night');
    expect(activityCard(row({ circleName: null })).chip).toBe('Saved');
    expect(activityCard(row({ type: 'check_in' })).chip).toBe('Checked in');
  });
  it('draws a whole card for a row with no actor, no name and an unknown type', () => {
    const card = activityCard({ _id: 'x', type: 'who_knows', actorId: '' } as Activity);
    expect(card.actorName).toBe('Someone');
    expect(card.sentence).toBe('shared an update');
    expect(card.pictures).toEqual([]);
    expect(card.poster.title).toBe('Shared an update');
    expect(card.target).toBe('/people');
    expect(card.actorPath).toBe('/people');
  });
  it('gives every kind its colour', () => {
    expect(tintOf('place_liked')).toBe('like');
    expect(tintOf('place_commented')).toBe('comment');
    expect(tintOf('venue_offer')).toBe('store');
    expect(tintOf('check_in')).toBe('brand');
    expect(tintOf('nope')).toBe('brand');
  });
});

describe('groupSummary', () => {
  it('counts repeated kinds and keeps single ones in full', () => {
    const burst = [
      row({ _id: '1' }), row({ _id: '2', targetName: 'Koi' }),
      row({ _id: '3', type: 'place_liked' }), row({ _id: '4', type: 'global_place_liked' }),
      row({ _id: '5', type: 'circle_created', targetName: 'Tucson' })
    ];
    expect(groupSummary(burst)).toBe('saved 2 places, liked 2 places, and created a new circle Tucson');
  });
  it('joins two with "and", one alone as itself', () => {
    expect(groupSummary([row({ _id: '1' }), row({ _id: '2', type: 'place_commented' })])).toBe('saved STIR to Date Night and commented on STIR');
    expect(groupSummary([row({ _id: '1' })])).toBe('saved STIR to Date Night');
    expect(groupSummary([])).toBe('shared an update');
  });
  it('has words for a burst of kinds it does not know', () => {
    expect(groupSummary([row({ _id: '1', type: 'zzz' }), row({ _id: '2', type: 'zzz' })])).toBe('shared 2 updates');
  });
});
