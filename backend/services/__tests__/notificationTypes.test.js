// The one table reproduces the three it replaced, plus the rows added since
// (daily_quote: mutable via notificationPreferences.dailyQuote).
const { TYPES, categoryFor, prefKeyFor, shouldBadge, recordsRow, isUrgent, isKnownType } = require('../notificationTypes');

const OLD_CATEGORIES = {
  new_message: 'NEW_MESSAGE', connection_request: 'CONNECTION_REQUEST', new_suggestion: 'PLACE_SUGGESTION',
  new_place: 'ACTIVITY_UPDATE', place_like: 'ACTIVITY_UPDATE', place_comment: 'ACTIVITY_UPDATE',
  daily_summary: 'DAILY_SUMMARY', discovery_prompt: 'DISCOVERY_PROMPT', weekend_recommendations: 'WEEKEND_RECOMMENDATIONS',
  social_activity: 'SOCIAL_ACTIVITY', milestone: 'MILESTONE', check_in: 'CHECK_IN', engagement_reminder: 'ENGAGEMENT_REMINDER',
  weekly_summary: 'WEEKLY_SUMMARY', monthly_summary: 'MONTHLY_SUMMARY', special_event: 'SPECIAL_EVENT',
  network_growth: 'NETWORK_GROWTH', care_ask: 'CARE_ASK',
  care_ask_done: 'CARE_DONE', care_ask_yesno: 'CARE_YESNO', care_ask_scale: 'CARE_SCALE', care_ask_text: 'CARE_TEXT',
  // 2026-10-01: pushes that were sent without a row here
  reengagement: 'ENGAGEMENT_REMINDER', activity_notification: 'ACTIVITY_UPDATE'
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
  care_ask_done: 'careCheckins', care_ask_yesno: 'careCheckins', care_ask_scale: 'careCheckins', care_ask_text: 'careCheckins',
  care_watcher_request: 'careCheckins', care_watcher_invite: 'careCheckins', care_watcher_accepted: 'careCheckins',
  care_watcher_declined: 'careCheckins', care_watcher_joined: 'careCheckins', care_watcher_removed: 'careCheckins',
  daily_quote: 'dailyQuote',
  check_in_response: 'checkIns', reengagement: 'reengagement', activity_notification: 'socialActivity'
};
const OLD_BADGE_WORTHY = ['new_message', 'connection_request', 'connection_accepted', 'place_like', 'place_comment', 'new_follower',
  'activity_reaction', 'activity_comment', 'check_in', 'new_suggestion', 'moment_tag', 'circle_invite', 'store_claim',
  'store_claim_approved', 'premium_signup', 'did_you_know', 'check_in_response'];

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
    expect(Object.keys(row).filter((k) => k !== 'record' && k !== 'urgent').sort()).toEqual(['badge', 'category', 'pref'], type);
  }
});

test('the rows a person can catch up on in Notifications (Wes, 2026-10-01)', () => {
  const recorded = Object.keys(TYPES).filter(recordsRow).sort();
  expect(recorded).toEqual([
    'care_accepted', 'care_invite', 'care_silence', 'care_watcher_accepted', 'care_watcher_declined',
    'care_watcher_invite', 'care_watcher_joined', 'care_watcher_removed', 'care_watcher_request',
    'check_in_response', 'favcoin_claim_settled', 'fridgemail', 'milestone', 'nextbar_result',
    'nextbar_round', 'postcard_order'
  ]);
  // Reminders, digests and the questions themselves stay push-only
  ['engagement_reminder', 'reengagement', 'daily_summary', 'weekly_summary', 'daily_quote', 'care_ask', 'care_answer',
    'activity_notification', 'new_place'].forEach((t) => expect(recordsRow(t)).toBe(false));
  // Types whose senders write their own row never double up
  ['new_message', 'connection_request', 'place_like', 'new_suggestion', 'check_in', 'did_you_know'].forEach((t) => expect(recordsRow(t)).toBe(false));
  expect(isKnownType('care_watcher_invite')).toBe(true);
  expect(isKnownType('nope')).toBe(false);
});


test('only the How Are You? questions and the unanswered alert go out Time Sensitive (Wes, 2026-10-02)', () => {
  expect(Object.keys(TYPES).filter(isUrgent).sort()).toEqual([
    'care_ask', 'care_ask_done', 'care_ask_scale', 'care_ask_text', 'care_ask_yesno', 'care_silence'
  ]);
  expect(isUrgent('new_message')).toBe(false);
  expect(isUrgent('unknown')).toBe(false);
});
