// backend/services/notificationTypes.js
//
// Every push type in one table: the APNs category (Lock Screen buttons the
// app registers), the preference key that can mute it, and whether it adds
// to the badge. These were three separate tables in two files that had
// drifted; adding a type now means adding one row here.
//
// Types without a category show as plain notifications (the app registers
// Lock Screen actions only for the categories listed; see
// NotificationCategoryRegistry.swift). A type without a pref key can't be
// muted from Settings; widget-driven types are switched off in the widget.
//
// `record: true` = the push also leaves a row in the in-app Notifications
// list (the bell), written by notificationService.sendToUser itself, so a
// person can catch up on anything they missed. For requests, answers and
// news about YOUR things — never for reminders, digests or friends' activity
// (that's the feed). Types whose senders write their own row (new_message,
// connection_request, place_like …) leave this off, or they'd get two.
//
// `urgent: true` = sent Time Sensitive: it comes through Focus / Do Not
// Disturb and stays at the top of the Lock Screen for an hour. Only for
// something a person is waiting on right now — the How Are You? questions
// and the family alert that one went unanswered (Wes, 2026-10-02). Whether
// a banner stays on screen until tapped is the person's own Banner Style
// setting; the widget offers a shortcut to it.
const TYPES = {
  new_message:             { category: 'NEW_MESSAGE',             pref: 'newMessages',            badge: true },
  connection_request:      { category: 'CONNECTION_REQUEST',      pref: 'connectionRequests',     badge: true },
  connection_accepted:     { category: null,                      pref: 'connectionRequests',     badge: true },
  new_suggestion:          { category: 'PLACE_SUGGESTION',        pref: 'newSuggestions',         badge: true },
  new_place:               { category: 'ACTIVITY_UPDATE',         pref: 'newPlaces',              badge: false },
  place_like:              { category: 'ACTIVITY_UPDATE',         pref: 'socialActivity',         badge: true },
  place_comment:           { category: 'ACTIVITY_UPDATE',         pref: 'socialActivity',         badge: true },
  circle_invite:           { category: null,                      pref: 'circleInvites',          badge: true },
  check_in:                { category: 'CHECK_IN',                pref: 'checkIns',               badge: true },
  daily_summary:           { category: 'DAILY_SUMMARY',           pref: 'dailySummary',           badge: false },
  discovery_prompt:        { category: 'DISCOVERY_PROMPT',        pref: 'discoveryPrompts',       badge: false },
  weekend_recommendations: { category: 'WEEKEND_RECOMMENDATIONS', pref: 'weekendRecommendations', badge: false },
  social_activity:         { category: 'SOCIAL_ACTIVITY',         pref: 'socialActivity',         badge: false },
  social_notification:     { category: null,                      pref: 'socialActivity',         badge: false },
  new_follower:            { category: null,                      pref: 'newFollowers',           badge: true },
  activity_reaction:       { category: null,                      pref: null,                     badge: true },
  activity_comment:        { category: null,                      pref: null,                     badge: true },
  moment_tag:              { category: null,                      pref: null,                     badge: true },
  store_claim:             { category: null,                      pref: null,                     badge: true },
  store_claim_approved:    { category: null,                      pref: null,                     badge: true },
  premium_signup:          { category: null,                      pref: null,                     badge: true },
  // Operational alerts to the admin account (services/adminAlerts.js)
  admin_alert:             { category: null,                      pref: null,                     badge: false },
  milestone:               { category: 'MILESTONE',               pref: 'milestones',             badge: false, record: true },
  engagement_reminder:     { category: 'ENGAGEMENT_REMINDER',     pref: 'reengagement',           badge: false },
  weekly_summary:          { category: 'WEEKLY_SUMMARY',          pref: null,                     badge: false },
  monthly_summary:         { category: 'MONTHLY_SUMMARY',         pref: null,                     badge: false },
  special_event:           { category: 'SPECIAL_EVENT',           pref: null,                     badge: false },
  network_growth:          { category: 'NETWORK_GROWTH',          pref: null,                     badge: false },
  did_you_know:            { category: null,                      pref: 'tips',                   badge: true },
  daily_quote:             { category: null,                      pref: 'dailyQuote',             badge: false },
  nextbar_round:           { category: null,                      pref: 'socialActivity',         badge: false, record: true },
  nextbar_result:          { category: null,                      pref: 'socialActivity',         badge: false, record: true },
  // Events widget (Party Bus): invited, someone joined (to the coordinator),
  // new photos (≤1 per uploader per 15 min per event)
  event_invite:            { category: null,                      pref: 'socialActivity',         badge: false, record: true },
  event_joined:            { category: null,                      pref: 'socialActivity',         badge: false, record: true },
  event_photos:            { category: null,                      pref: 'socialActivity',         badge: false },
  // 2026-10-06: new photo challenges; roll call and the coordinator's
  // "where are you?" (not Time Sensitive: only How Are You? is, Wes 2026-10-02)
  event_challenge:         { category: null,                      pref: 'socialActivity',         badge: false },
  event_rollcall:          { category: null,                      pref: 'socialActivity',         badge: false },
  event_rollcall_ping:     { category: null,                      pref: 'socialActivity',         badge: false },
  // FavRun, shared (2026-10-06): invited to watch, each mile, finished,
  // a cheer (to the runner), someone started watching (to the runner)
  run_live_invite:         { category: null,                      pref: 'socialActivity',         badge: false, record: true },
  run_live_split:          { category: null,                      pref: 'socialActivity',         badge: false },
  run_live_finished:       { category: null,                      pref: 'socialActivity',         badge: false, record: true },
  run_cheer:               { category: null,                      pref: 'socialActivity',         badge: false },
  run_watcher_joined:      { category: null,                      pref: 'socialActivity',         badge: false },
  postcard_order:          { category: null,                      pref: 'socialActivity',         badge: false, record: true },
  fridgemail:              { category: null,                      pref: 'socialActivity',         badge: false, record: true },
  care_invite:             { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  care_ask:                { category: 'CARE_ASK',                pref: 'careCheckins',           badge: false, urgent: true },
  // One push type per question kind: the Lock Screen buttons differ (see
  // careCheckin/questionBank.js). Only builds that registered the category
  // are sent these; older parents keep getting plain care_ask.
  care_ask_done:           { category: 'CARE_DONE',               pref: 'careCheckins',           badge: false, urgent: true },
  care_ask_yesno:          { category: 'CARE_YESNO',              pref: 'careCheckins',           badge: false, urgent: true },
  care_ask_scale:          { category: 'CARE_SCALE',              pref: 'careCheckins',           badge: false, urgent: true },
  care_ask_text:           { category: 'CARE_TEXT',               pref: 'careCheckins',           badge: false, urgent: true },
  care_answer:             { category: null,                      pref: 'careCheckins',           badge: false },
  // Family support (2026-10-07): to the parent when family reacts / says
  // they're calling or coming; to the rest of the family when someone has it
  care_reaction:           { category: null,                      pref: 'careCheckins',           badge: false },
  // A comment on an answer (family → the parent; the parent's reply → family)
  care_comment:            { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  care_alert_response:     { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  care_alert_handled:      { category: null,                      pref: 'careCheckins',           badge: false },
  care_accepted:           { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  // Family members on a check-in: asked for (parent decides) or invited by the
  // owner (they decide); the parent hears who joined and can remove anyone.
  care_watcher_request:    { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  care_watcher_invite:     { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  care_watcher_accepted:   { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  care_watcher_declined:   { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  care_watcher_joined:     { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  care_watcher_removed:    { category: null,                      pref: 'careCheckins',           badge: false, record: true },
  // Pushes that had no row in this table (no pref key, category or badge)
  check_in_response:       { category: null,                      pref: 'checkIns',               badge: true, record: true },
  favcoin_claim_settled:   { category: null,                      pref: null,                     badge: false, record: true },
  reengagement:            { category: 'ENGAGEMENT_REMINDER',     pref: 'reengagement',           badge: false },
  activity_notification:   { category: 'ACTIVITY_UPDATE',         pref: 'socialActivity',         badge: false },
  care_silence:            { category: null,                      pref: 'careCheckins',           badge: false, record: true, urgent: true }
};

const row = (type) => TYPES[type] || {};
/** APNs category for a type, or null (no Lock Screen actions). */
const categoryFor = (type) => row(type).category || null;
/** The notificationPreferences key that mutes a type; null = can't be muted. */
const prefKeyFor = (type) => row(type).pref || null;
/** Whether a push of this type adds to the app badge. */
const shouldBadge = (type) => !!row(type).badge;
/** Whether sending this push also writes its Notifications-list row. */
const recordsRow = (type) => row(type).record === true;
/** Whether this push goes out Time Sensitive (see `urgent` above). */
const isUrgent = (type) => row(type).urgent === true;
/** A type the server knows (and so may store in the Notifications list). */
const isKnownType = (type) => Object.prototype.hasOwnProperty.call(TYPES, type);

module.exports = { TYPES, categoryFor, prefKeyFor, shouldBadge, recordsRow, isUrgent, isKnownType };
