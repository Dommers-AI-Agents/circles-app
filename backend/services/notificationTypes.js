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
  milestone:               { category: 'MILESTONE',               pref: 'milestones',             badge: false },
  engagement_reminder:     { category: 'ENGAGEMENT_REMINDER',     pref: 'reengagement',           badge: false },
  weekly_summary:          { category: 'WEEKLY_SUMMARY',          pref: null,                     badge: false },
  monthly_summary:         { category: 'MONTHLY_SUMMARY',         pref: null,                     badge: false },
  special_event:           { category: 'SPECIAL_EVENT',           pref: null,                     badge: false },
  network_growth:          { category: 'NETWORK_GROWTH',          pref: null,                     badge: false },
  did_you_know:            { category: null,                      pref: 'tips',                   badge: true },
  daily_quote:             { category: null,                      pref: 'dailyQuote',             badge: false },
  nextbar_round:           { category: null,                      pref: 'socialActivity',         badge: false },
  nextbar_result:          { category: null,                      pref: 'socialActivity',         badge: false },
  postcard_order:          { category: null,                      pref: 'socialActivity',         badge: false },
  fridgemail:              { category: null,                      pref: 'socialActivity',         badge: false },
  care_invite:             { category: null,                      pref: 'careCheckins',           badge: false },
  care_ask:                { category: 'CARE_ASK',                pref: 'careCheckins',           badge: false },
  // One push type per question kind: the Lock Screen buttons differ (see
  // careCheckin/questionBank.js). Only builds that registered the category
  // are sent these; older parents keep getting plain care_ask.
  care_ask_done:           { category: 'CARE_DONE',               pref: 'careCheckins',           badge: false },
  care_ask_yesno:          { category: 'CARE_YESNO',              pref: 'careCheckins',           badge: false },
  care_ask_scale:          { category: 'CARE_SCALE',              pref: 'careCheckins',           badge: false },
  care_ask_text:           { category: 'CARE_TEXT',               pref: 'careCheckins',           badge: false },
  care_answer:             { category: null,                      pref: 'careCheckins',           badge: false },
  care_accepted:           { category: null,                      pref: 'careCheckins',           badge: false },
  // Family members on a check-in: asked for (parent decides) or invited by the
  // owner (they decide); the parent hears who joined and can remove anyone.
  care_watcher_request:    { category: null,                      pref: 'careCheckins',           badge: false },
  care_watcher_invite:     { category: null,                      pref: 'careCheckins',           badge: false },
  care_watcher_accepted:   { category: null,                      pref: 'careCheckins',           badge: false },
  care_watcher_declined:   { category: null,                      pref: 'careCheckins',           badge: false },
  care_watcher_joined:     { category: null,                      pref: 'careCheckins',           badge: false },
  care_watcher_removed:    { category: null,                      pref: 'careCheckins',           badge: false },
  care_silence:            { category: null,                      pref: 'careCheckins',           badge: false }
};

const row = (type) => TYPES[type] || {};
/** APNs category for a type, or null (no Lock Screen actions). */
const categoryFor = (type) => row(type).category || null;
/** The notificationPreferences key that mutes a type; null = can't be muted. */
const prefKeyFor = (type) => row(type).pref || null;
/** Whether a push of this type adds to the app badge. */
const shouldBadge = (type) => !!row(type).badge;

module.exports = { TYPES, categoryFor, prefKeyFor, shouldBadge };
