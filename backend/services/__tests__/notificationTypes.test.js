// The one table reproduces the three it replaced, plus the rows added since
// (daily_quote: mutable via notificationPreferences.dailyQuote).
const { TYPES, categoryFor, prefKeyFor, shouldBadge } = require('../notificationTypes');

const OLD_CATEGORIES = {
  new_message: 'NEW_MESSAGE', connection_request: 'CONNECTION_REQUEST', new_suggestion: 'PLACE_SUGGESTION',
  new_place: 'ACTIVITY_UPDATE', place_like: 'ACTIVITY_UPDATE', place_comment: 'ACTIVITY_UPDATE',
  daily_summary: 'DAILY_SUMMARY', discovery_prompt: 'DISCOVERY_PROMPT', weekend_recommendations: 'WEEKEND_RECOMMENDATIONS',
  social_activity: 'SOCIAL_ACTIVITY', milestone: 'MILESTONE', check_in: 'CHECK_IN', engagement_reminder: 'ENGAGEMENT_REMINDER',
  weekly_summary: 'WEEKLY_SUMMARY', monthly_summary: 'MONTHLY_SUMMARY', special_event: 'SPECIAL_EVENT',
  network_growth: 'NETWORK_GROWTH', care_ask: 'CARE_ASK'
};
const OLD_TYPE_MAP = {
  new_message: 'newMessages', new_suggestion: 'newSuggestions', new_place: 'newPlaces',
  connection_request: 'connectionRequests', connection_accepted: 'connectionRequests', circle_invite: 'circleInvites',
  check_in: 'checkIns', daily_summary: 'dailySummary', discovery_prompt: 'discoveryPrompts',
  weekend_recommendations: 'weekendRecommendations', social_activity: 'socialActivity', social_notification: 'socialActivity',
  place_like: 'socialActivity', place_comment: 'socialActivity', new_follower: 'newFollowers',
  engagement_reminder: 'reengagement', milestone: 'milestones', did_you_know: 'tips',
  nextbar_round: 'socialActivity', nextbar_result: 'socialActivity', postcard_order: 'socialActivity', fridgemail: 'socialActivity',
  care_invite: 'careCheckins', care_ask: 'careCheckins', care_answer: 'careCheckins', care_accepted: 'careCheckins', care_silence: 'careCheckins',
  daily_quote: 'dailyQuote'
};
const OLD_BADGE_WORTHY = ['new_message', 'connection_request', 'connection_accepted', 'place_like', 'place_comment', 'new_follower',
  'activity_reaction', 'activity_comment', 'check_in', 'new_suggestion', 'moment_tag', 'circle_invite', 'store_claim',
  'store_claim_approved', 'premium_signup', 'did_you_know'];

test('categories match the old switch', () => {
  const derived = Object.fromEntries(Object.keys(TYPES).map((t) => [t, categoryFor(t)]).filter(([, c]) => c));
  expect(derived).toEqual(OLD_CATEGORIES);
  expect(categoryFor('unknown')).toBeNull();
});

test('preference keys match the old typeMap', () => {
  const derived = Object.fromEntries(Object.keys(TYPES).map((t) => [t, prefKeyFor(t)]).filter(([, k]) => k));
  expect(derived).toEqual(OLD_TYPE_MAP);
  expect(prefKeyFor('unknown')).toBeNull();
});

test('badge-worthy set matches the old set', () => {
  const derived = Object.keys(TYPES).filter(shouldBadge).sort();
  expect(derived).toEqual([...OLD_BADGE_WORTHY].sort());
  expect(shouldBadge('unknown')).toBe(false);
});

test('every row is complete', () => {
  for (const [type, row] of Object.entries(TYPES)) {
    expect(Object.keys(row).sort()).toEqual(['badge', 'category', 'pref'], type);
  }
});
