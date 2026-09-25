/**
 * Copy for the shared-widget landing page (`/app/widget/:id`).
 *
 * Mirrors the descriptors in the favcircles-widgets package. It is a mirror,
 * not the source of truth, and it does not have to be complete: an id with no
 * row here still gets a working page and a working App Store fallback, just
 * generic wording. So a new widget ships without touching the backend, and
 * adding a row later only improves the link preview.
 */
const WIDGETS = {
  billsplit: { title: 'Bill Split', blurb: 'Split the check and the tip with friends in seconds.', emoji: '🧾' },
  calories: { title: 'Calories', blurb: 'Log meals and macros in a couple of taps.', emoji: '🥗' },
  fridgemail: { title: 'Fridge Mail', blurb: "Your kids' drawings, printed and mailed to Grandma every week.", emoji: '🎨' },
  habits: { title: 'Habits', blurb: 'Keep daily habits with one-tap check-ins and streaks.', emoji: '✅' },
  heartbeat: { title: 'Heartbeat', blurb: 'Measure your heart rate directly from your phone camera.', emoji: '❤️' },
  howareyou: { title: 'How Are You?', blurb: 'Check on Mom or Dad a few times a day — they answer with one tap from their Lock Screen.', emoji: '💬' },
  nextbar: { title: 'NextBar', blurb: 'Your next bar, picked from the places your friends actually go.', emoji: '🍸' },
  postcard: { title: 'Postcard', blurb: 'Send a real postcard from a trip photo, printed and mailed for you.', emoji: '📮' },
  quotes: { title: 'Quotes', blurb: 'A good line a few times a day, on the topics you pick.', emoji: '💭' },
  sleepsounds: { title: 'Sleep Sounds', blurb: 'Mix rain, ocean and fire into a sleep sound that fades out on its own.', emoji: '🌙' },
  stocks: { title: 'Stocks', blurb: 'Follow your stocks, indexes, rates and crypto at a glance.', emoji: '📈' },
  water: { title: 'Water', blurb: 'Track your water through the day and get a nudge when you fall behind.', emoji: '💧' },
  workouts: { title: 'Workouts', blurb: 'Log sets, reps and PRs, and see your progress over time.', emoji: '🏋️' }
};

const GENERIC = { title: 'A widget', blurb: 'One of the mini-apps inside FavCircles', emoji: '✨' };

/** Never throws and never 404s — an unknown id is a widget we haven't listed yet. */
const widgetCopy = (id) => WIDGETS[id] || GENERIC;

module.exports = { WIDGETS, GENERIC, widgetCopy };
