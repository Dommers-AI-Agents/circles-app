// What a shared home tab's landing page says (`/app/tab/:slug`). Only the
// tabs the app offers a Share button for have a row; the slug is the public
// name the app's HomeContentSegment.shareSlug produces. Anything else gets
// the generic FavCircles pitch rather than a 404, because a link someone
// already sent must still lead to the app.
const TABS = {
  local: {
    title: 'Local',
    blurb: 'Deals at places near you, and what\'s on nearby.',
    emoji: '📍'
  },
  widgets: {
    title: 'Widgets',
    blurb: 'Mini-apps for everyday life: water, workouts, events, postcards and more.',
    emoji: '🧩'
  }
};

const GENERIC = { title: 'FavCircles', blurb: 'Favorite places, shared with the people you trust.', emoji: '⭕️' };

const tabCopy = (slug) => TABS[String(slug || '').toLowerCase()] || GENERIC;

module.exports = { TABS, GENERIC, tabCopy };
