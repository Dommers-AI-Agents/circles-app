/**
 * Copy for the shared-widget landing page (`/app/widget/:id`) and the weekly
 * email. GENERATED from website/widgets/widgets.json (the one source, which
 * also feeds the website and the app's "i" sheet) by
 * `node website/tools/build-widgets-page.js` — don't edit by hand.
 *
 * An id with no row still gets a working page and App Store fallback with
 * generic wording, so a widget the server hasn't heard of yet never breaks.
 */
const WIDGETS = require('./widgetCatalog.generated.json');


const GENERIC = { title: 'A widget', blurb: 'One of the mini-apps inside FavCircles', emoji: '✨' };

/** Never throws and never 404s — an unknown id is a widget we haven't listed yet. */
const widgetCopy = (id) => WIDGETS[id] || GENERIC;

module.exports = { WIDGETS, GENERIC, widgetCopy };
