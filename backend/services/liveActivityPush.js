// backend/services/liveActivityPush.js
//
// One Live Activity push (iOS lock screen / Dynamic Island) through FCM's HTTP
// v1 API. firebase-admin 13.3 has no live_activity_token field, so this posts
// the message itself. `token` is the activity's own push token for update/end,
// or the app's push-to-start token for start (iOS 17.2+). FCM still needs the
// phone's FCM registration token to route it.
//
// Shared by the event display (eventLiveActivityService) and the How Are You?
// question (careCheckin/liveActivity).

const APNS_TOPIC = `${process.env.IOS_BUNDLE_ID || 'com.favcircles.circles'}.push-type.liveactivity`;

/** The `aps` dictionary (pure, tested). Times are Unix seconds. */
function buildAps({ event, state, attributesType, attributes, alert, staleDate, dismissalDate, now }) {
  const aps = { timestamp: now, event, 'content-state': state };
  if (event === 'start') {
    aps['attributes-type'] = attributesType;
    aps.attributes = attributes;
  }
  if (alert) aps.alert = alert;
  if (staleDate) aps['stale-date'] = staleDate;
  if (dismissalDate) aps['dismissal-date'] = dismissalDate;
  return aps;
}

/**
 * @param {object} p
 * @param {'start'|'update'|'end'} p.event
 * @returns {Promise<true|false|'gone'>} 'gone' = the token is dead; forget it
 */
async function sendLiveActivity({ fcmToken, token, event, state, attributesType, attributes, alert,
  staleDate, dismissalDate, urgent = false }) {
  if (!fcmToken || !token) return false;
  const admin = require('firebase-admin');
  const projectId = process.env.FIREBASE_PROJECT_ID || admin.app().options.projectId;
  const access = await admin.app().options.credential.getAccessToken();
  const now = Math.floor(Date.now() / 1000);
  const aps = buildAps({ event, state, attributesType, attributes, alert, staleDate, dismissalDate, now });
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${access.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token: fcmToken,
        apns: {
          live_activity_token: token,
          headers: {
            'apns-push-type': 'liveactivity',
            'apns-topic': APNS_TOPIC,
            'apns-priority': urgent || event !== 'update' ? '10' : '5'
          },
          payload: { aps }
        }
      }
    })
  });
  if (res.ok) return true;
  const body = await res.text().catch(() => '');
  if (res.status === 404 || /UNREGISTERED|NOT_FOUND/.test(body)) return 'gone';
  console.error(`🔒 live activity ${event} push ${res.status}: ${body.slice(0, 200)}`);
  return false;
}

module.exports = { sendLiveActivity, buildAps, APNS_TOPIC };
