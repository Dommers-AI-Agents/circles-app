// backend/services/activity/describe.js
// What an activity was, in words the owner recognises, and where tapping a
// notification about it should land (Wes, 2026-11-10: "reacted 👍 to your
// activity" didn't say which one, and the tap only opened Home).
//   describeActivity(activity) → { phrase, target }
//   phrase: "your check-in at Ed's Tavern"
//   target: { placeId } | { videoId } | { circleId } — keys the app's
//           NotificationTapRouter already understands; {} = the feed.

const clean = (s) => String(s || '').replace(/\s+/g, ' ').trim();

function describeActivity(activity) {
  const a = activity || {};
  const meta = a.metadata || {};
  const name = clean(a.targetName);
  const placeName = clean(meta.placeName) || name;
  const placeId = meta.placeId || null;
  const at = (what) => (placeName ? `${what} at ${placeName}` : what);
  const of = (what) => (name ? `${what} ${name}` : what);
  const place = (id) => (id ? { placeId: id } : {});

  switch (a.type) {
    case 'check_in':
      return { phrase: at('your check-in'), target: place(placeId) };
    case 'place_added':
      return { phrase: of('your save of'), target: place(placeId || a.targetId) };
    case 'place_liked':
      return { phrase: of('your like of'), target: place(placeId || a.targetId) };
    case 'place_commented':
      return { phrase: name ? `your comment on ${name}` : 'your comment', target: place(placeId || a.targetId) };
    case 'comment_liked': {
      // targetName is "Comment on <place>"
      const on = name.replace(/^comment on\s+/i, '');
      return { phrase: on ? `your comment on ${on}` : 'your comment', target: place(placeId) };
    }
    case 'photo_uploaded':
      return { phrase: at('your photo'), target: place(placeId || a.targetId) };
    case 'global_place_liked':
      return { phrase: at('your like of a photo'), target: place(placeId) };
    case 'video_uploaded':
      return { phrase: at('your moment'), target: a.targetId ? { videoId: a.targetId } : place(placeId) };
    case 'video_liked': {
      const what = name.replace(/^moment at\s+/i, '');
      return { phrase: what ? `your like of a moment at ${what}` : 'your like of a moment',
        target: a.targetId ? { videoId: a.targetId } : place(placeId) };
    }
    case 'circle_created':
      return { phrase: name ? `your new circle "${name}"` : 'your new circle', target: a.targetId ? { circleId: a.targetId } : {} };
    case 'venue_offer':
    case 'venue_announcement':
      return { phrase: name ? `your post for ${name}` : 'your post', target: place(placeId || a.targetId) };
    case 'workout_shared':
      return { phrase: name ? `your workout "${name}"` : 'your workout', target: {} };
    case 'run_shared':
      return { phrase: 'your run', target: {} };
    case 'fridgemail_sent':
      return { phrase: name ? `your Fridge Mail to ${name}` : 'your Fridge Mail', target: {} };
    default:
      return { phrase: 'your activity', target: {} };
  }
}

/** "reacted 👍 to your check-in at X" / "… and 4 more" for a group. */
function reactionBody(name, emoji, activity, count = 1) {
  const { phrase } = describeActivity(activity);
  if (count <= 1) return `${name} reacted ${emoji} to ${phrase}`;
  if (phrase === 'your activity') return `${name} reacted ${emoji} to ${count} of your activities`;
  return `${name} reacted ${emoji} to ${phrase} and ${count - 1} more`;
}

module.exports = { describeActivity, reactionBody };
