const { describeActivity, reactionBody } = require('../activity/describe');

describe('describeActivity', () => {
  test('check-in names the place and opens it (Wes, 2026-11-10)', () => {
    const a = { type: 'check_in', targetId: 'ci1', targetName: 'YMCA of Greater Charlotte',
      metadata: { placeId: 'p1', globalPlaceId: 'g1' } };
    expect(describeActivity(a)).toEqual({ phrase: 'your check-in at YMCA of Greater Charlotte', target: { placeId: 'p1' } });
    expect(reactionBody('Salvatore A Sgroi', '👍', a))
      .toBe('Salvatore A Sgroi reacted 👍 to your check-in at YMCA of Greater Charlotte');
  });

  test('each kind lands on its subject', () => {
    expect(describeActivity({ type: 'place_added', targetId: 's1', targetName: "Ed's Tavern", metadata: { placeId: 's1' } }))
      .toEqual({ phrase: "your save of Ed's Tavern", target: { placeId: 's1' } });
    expect(describeActivity({ type: 'video_uploaded', targetId: 'v1', targetName: "Rustler's Rooste", metadata: {} }))
      .toEqual({ phrase: "your moment at Rustler's Rooste", target: { videoId: 'v1' } });
    expect(describeActivity({ type: 'video_liked', targetId: 'v2', targetName: 'Moment at Barcelona Wine Bar' }).phrase)
      .toBe('your like of a moment at Barcelona Wine Bar');
    expect(describeActivity({ type: 'circle_created', targetId: 'c1', targetName: 'Date night' }))
      .toEqual({ phrase: 'your new circle "Date night"', target: { circleId: 'c1' } });
    expect(describeActivity({ type: 'comment_liked', targetName: "Comment on McLoone's Pier House", metadata: { placeId: 'p9' } }))
      .toEqual({ phrase: "your comment on McLoone's Pier House", target: { placeId: 'p9' } });
    expect(describeActivity({ type: 'workout_shared', targetName: 'Chest and Back' }))
      .toEqual({ phrase: 'your workout "Chest and Back"', target: {} });
  });

  test('unknown or missing activity stays generic', () => {
    expect(describeActivity(null)).toEqual({ phrase: 'your activity', target: {} });
    expect(describeActivity({ type: 'mystery' }).phrase).toBe('your activity');
  });

  test('a group names the first activity', () => {
    const a = { type: 'check_in', targetName: "Ed's Tavern", metadata: { placeId: 'p' } };
    expect(reactionBody('Sam', '🎉', a, 5)).toBe("Sam reacted 🎉 to your check-in at Ed's Tavern and 4 more");
    expect(reactionBody('Sam', '🎉', null, 4)).toBe('Sam reacted 🎉 to 4 of your activities');
  });
});
