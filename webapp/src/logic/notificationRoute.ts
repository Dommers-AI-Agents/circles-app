// Where a tapped notification goes on the web. The web twin of the iOS
// table (ios/Circles-iOS-UIKit/Logic/NotificationTapRouter.swift) over the
// types the server sends (backend/services/notificationTypes.js), mapped to
// the screens the web app has. Things that live only in the iPhone app
// (widgets, moments, orders) land on the nearest thing the web can show:
// the place or the person when the row names one, else the Activity feed.
type Data = Record<string, unknown> | null | undefined;

const field = (data: Data, key: string): string | null => {
  const value = data ? data[key] : null;
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  return null;
};

const enc = encodeURIComponent;
const FEED = '/feed';
const PEOPLE = '/people';

/** The mark on a row with no sender photo (iOS Logic/NotificationRowStyle.swift). */
export function notificationMark(type: string): string {
  switch (type) {
    case 'place_like': case 'place_liked': case 'circle_liked': return '❤️';
    case 'place_comment': case 'place_commented': case 'activity_comment': case 'circle_commented': return '💬';
    case 'activity_reaction': return '👍';
    case 'connection_request': case 'follow_request': return '🤝';
    case 'connection_accepted': case 'follow_request_accepted': case 'new_follower': case 'user_followed': return '👥';
    case 'new_message': return '✉️';
    case 'new_suggestion': return '💡';
    case 'check_in': case 'checkin': case 'check_in_response': return '📍';
    case 'moment_tag': return '🎬';
    case 'store_claim': case 'store_claim_approved': case 'store_alert': case 'store_nudge': return '🏪';
    case 'milestone': return '🏆';
    case 'favcoin_claim_settled': return '🪙';
    case 'did_you_know': return '✨';
    default:
      if (type.startsWith('care_')) return '💗';
      if (type.startsWith('event_') || type.startsWith('club_')) return '🎉';
      if (type.startsWith('run_')) return '🏃';
      if (type.startsWith('order_') || type.startsWith('waitlist_') || type.startsWith('receipt_')) return '🏪';
      return '🔔';
  }
}

export function notificationPath(type: string | null | undefined, data?: Data): string {
  const placeId = field(data, 'placeId') || field(data, 'globalPlaceId');
  const circleId = field(data, 'circleId');
  const conversationId = field(data, 'conversationId');
  const venueId = field(data, 'venueId');
  const fromUser = field(data, 'fromUserId') || field(data, 'actorId');
  const place = placeId ? `/place/${enc(placeId)}` : null;
  const circle = circleId ? `/circle/${enc(circleId)}` : null;
  const user = fromUser ? `/user/${enc(fromUser)}` : null;

  switch (type || '') {
    case 'new_message':
      return conversationId ? `/messages/${enc(conversationId)}` : '/messages';

    // Requests to answer, and the first-week "follow a few people" nudge: the people screen
    case 'connection_request': case 'follow_request': case 'starter_follow':
      return PEOPLE;

    case 'connection_accepted': {
      const by = field(data, 'acceptedByUserId') || fromUser;
      return by ? `/user/${enc(by)}` : PEOPLE;
    }
    case 'new_follower': case 'user_followed': case 'follow_request_accepted':
      return user || PEOPLE;

    // A followed store's news or its automatic nudge: its rewards card when
    // the row names the store, else its place page (where iOS goes)
    case 'store_alert': case 'store_nudge':
      return venueId ? `/rewards/${enc(venueId)}` : place || '/rewards';

    case 'new_suggestion': case 'suggestion_received': case 'suggestion_accepted':
      return place || user || FEED;

    case 'new_place':
      return circle || place || FEED;
    case 'circle_liked': case 'circle_commented': case 'circle_invite':
      return circle || FEED;

    // The bell stores place_like / place_comment; pushes say place_liked / place_commented
    case 'place_like': case 'place_liked': case 'place_comment': case 'place_commented':
    case 'check_in': case 'checkin': case 'check_in_response':
    case 'waitlist_ready': case 'waitlist_update': case 'receipt_result':
    case 'video_uploaded': case 'video_liked': case 'moment_uploaded': case 'moment_liked': case 'moment_tag':
      return place || FEED;

    // A reaction opens what the activity was about; older rows carry only the activity
    case 'activity_reaction':
      return place || circle || FEED;
    case 'activity_update': case 'activity_like': case 'activity_comment': case 'activity_notification':
      return FEED;

    case 'store_claim': case 'store_claim_approved':
      return '/me';
    case 'favcoin_claim_settled':
      return '/rewards';
    case 'starter_map': case 'all_places_map':
      return '/';

    default:
      // A type this table doesn't know: route on what the row carries
      if (field(data, 'activityId')) return FEED;
      if (circle) return circle;
      if (place) return place;
      if (conversationId) return `/messages/${enc(conversationId)}`;
      if (user) return user;
      return FEED;
  }
}
