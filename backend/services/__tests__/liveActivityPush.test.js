// The aps dictionary for a Live Activity push: start carries the attributes,
// update/end don't; stale and dismissal dates only when given.
const { buildAps } = require('../liveActivityPush');

test('start carries attributes-type, attributes and the alert', () => {
  expect(buildAps({ event: 'start', state: { a: 1 }, attributesType: 'CareQuestionAttributes', attributes: { askId: 'x' },
    alert: { title: 'Wes asks', body: 'How are you?' }, staleDate: 200, now: 100 })).toEqual({
    timestamp: 100, event: 'start', 'content-state': { a: 1 },
    'attributes-type': 'CareQuestionAttributes', attributes: { askId: 'x' },
    alert: { title: 'Wes asks', body: 'How are you?' }, 'stale-date': 200
  });
});

test('update and end carry only the state and their dates', () => {
  expect(buildAps({ event: 'update', state: { a: 2 }, attributesType: 'X', attributes: { y: 1 }, now: 5 }))
    .toEqual({ timestamp: 5, event: 'update', 'content-state': { a: 2 } });
  expect(buildAps({ event: 'end', state: {}, dismissalDate: 9, now: 5 }))
    .toEqual({ timestamp: 5, event: 'end', 'content-state': {}, 'dismissal-date': 9 });
});
