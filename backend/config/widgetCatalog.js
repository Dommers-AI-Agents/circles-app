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
  billsplit: { title: 'Bill Split', blurb: 'Split the check, add the tip', emoji: '🧾' },
  calories: { title: 'Calories', blurb: 'Quick-add meals and macros', emoji: '🥗' },
  fridgemail: { title: 'Fridge Mail', blurb: "Kids' drawings, mailed to Grandma every week", emoji: '🎨' },
  habits: { title: 'Habits', blurb: 'Daily check-ins and streaks', emoji: '✅' },
  heartbeat: { title: 'Heartbeat', blurb: 'Your pulse, from the camera or a strap', emoji: '❤️' },
  howareyou: { title: 'How Are You?', blurb: 'Check on Mom or Dad, a few times a day', emoji: '💬' },
  nextbar: { title: 'NextBar', blurb: 'Your next bar, picked from your circles', emoji: '🍸' },
  postcard: { title: 'Postcard', blurb: 'Send a postcard from your trip', emoji: '📮' },
  quotes: { title: 'Quotes', blurb: 'Good lines at the times you pick', emoji: '💭' },
  sleepsounds: { title: 'Sleep Sounds', blurb: 'Rain, ocean, fire — mix and drift off', emoji: '🌙' },
  stocks: { title: 'Stocks', blurb: 'Indexes, rates, crypto and the stocks you follow', emoji: '📈' },
  water: { title: 'Water', blurb: 'Tap to log each glass', emoji: '💧' },
  workouts: { title: 'Workouts', blurb: 'Log sets, reps and PRs', emoji: '🏋️' }
};

const GENERIC = { title: 'A widget', blurb: 'One of the mini-apps inside FavCircles', emoji: '✨' };

/** Never throws and never 404s — an unknown id is a widget we haven't listed yet. */
const widgetCopy = (id) => WIDGETS[id] || GENERIC;

module.exports = { WIDGETS, GENERIC, widgetCopy };
