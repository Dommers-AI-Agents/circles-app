// The notification switches the Settings screen offers, and what each one
// really changes on the server. Each key is a `notificationPreferences` key
// that backend/services/notificationTypes.js maps push types to; the server
// checks it (notificationService.isNotificationEnabled) before the phone
// push, the browser push (services/webPush) and the email someone gets when
// no push can reach them (services/emailFallback). A missing key means on.

export interface NotificationPreferences {
  newMessages?: boolean;
  connectionRequests?: boolean;
  newFollowers?: boolean;
  socialActivity?: boolean;
  newSuggestions?: boolean;
  newPlaces?: boolean;
  storeAlerts?: boolean;
  /** 'storesOnly' = only stores whose bell is on, plus orders and lines */
  mode?: string;
  [key: string]: unknown;
}

export type SwitchKey = 'newMessages' | 'connectionRequests' | 'newFollowers' | 'socialActivity' | 'newSuggestions' | 'newPlaces' | 'storeAlerts';

export interface NotificationSwitch {
  key: SwitchKey;
  label: string;
  detail: string;
  /** Also turns off the email sent when no notification can reach you */
  email: boolean;
}

// The email column comes from emailFallback's EMAIL_TYPES: new_follower,
// place_comment, new_suggestion and store_alert are emailed, each behind
// its type's switch. Messages have their own email (unsubscribe link only).
export const SWITCHES: NotificationSwitch[] = [
  { key: 'newMessages', label: 'Messages', detail: 'When someone sends you a message.', email: false },
  { key: 'connectionRequests', label: 'Connections', detail: 'Invitations to connect, and when someone accepts yours.', email: false },
  { key: 'newFollowers', label: 'Followers', detail: 'New followers and requests to follow you.', email: true },
  { key: 'socialActivity', label: 'Likes, comments and events', detail: 'Likes and comments on your places, and event and club news.', email: true },
  { key: 'newSuggestions', label: 'Place suggestions', detail: 'When someone suggests a place for you.', email: true },
  { key: 'newPlaces', label: 'New places from your people', detail: 'When people you follow save somewhere new.', email: false },
  { key: 'storeAlerts', label: 'Stores you follow', detail: 'Specials and events from stores whose bell you turned on.', email: true }
];

export const STORES_ONLY = 'storesOnly';

export const isStoresOnly = (preferences: NotificationPreferences | null | undefined): boolean =>
  !!preferences && preferences.mode === STORES_ONLY;

/**
 * Whether this switch lets its notifications through. Missing = on. In
 * "Stores I follow only" every switch except the stores one is held off by
 * the mode, whatever it says.
 */
export function switchIsOn(preferences: NotificationPreferences | null | undefined, key: SwitchKey): boolean {
  if (isStoresOnly(preferences) && key !== 'storeAlerts') return false;
  return !preferences || preferences[key] !== false;
}

/** What a flip sends: just that one key (the server merges). */
export const flipOf = (key: SwitchKey, on: boolean): NotificationPreferences => ({ [key]: on });
