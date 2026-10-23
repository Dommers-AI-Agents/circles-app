/**
 * "What's new" in the weekly email (Wes, 2026-10-19: "add a lot more info
 * that someone can scroll through — widgets, new features"). Newest first.
 *
 * `minVersion`: the app build that has it. An entry stays hidden until that
 * version is live in the App Store (the email checks), and anyone on an older
 * build is told to update. Leave it off for server-side changes everyone
 * already has. Add a row when you ship something people will notice.
 */
module.exports = [
  {
    date: '2026-10-22', emoji: '🐶', title: 'Can I Pet Dat Dog',
    body: 'For dog people: post your pup in the Dog Park and tap Pet on everyone else\'s, get a funny dog thing every day, and keep your dog\'s vaccines, vet, insurance and the vet\'s paperwork in one place.',
    minVersion: '1.4.1', link: '/app/widget/dogs'
  },
  {
    date: '2026-10-21', emoji: '👟', title: 'Clubs: run clubs, walk groups, book clubs',
    body: 'Start a club or join one from a link: weekly meetups everyone can say they\'re going to, events, an organizers\' bulletin and a message board for the whole club.',
    minVersion: '1.4.1', link: '/app/widget/clubs'
  },
  {
    date: '2026-10-19', emoji: '💬', title: 'How Are You?: comment any time',
    body: 'Answered already? Your recent answers are listed under the question. Tap one to add a comment, and your family gets a notification.',
    minVersion: '1.4.1', link: '/app/widget/howareyou'
  },
  {
    date: '2026-10-19', emoji: '💳', title: 'All your subscriptions in one place',
    body: 'Settings → Subscriptions shows everything you pay for (Premium, Fridge Mail), what it costs, when it renews, and how to cancel.',
    minVersion: '1.4.1'
  },
  {
    date: '2026-10-19', emoji: '🌤️', title: 'Weather: swipe between your cities',
    body: 'Save a few cities in the Weather widget and swipe left and right between them, like the Weather app.',
    minVersion: '1.4.1', link: '/app/widget/weather'
  },
  {
    date: '2026-10-18', emoji: '📮', title: 'See which postcards went by mail',
    body: 'Your sent postcards are tagged Mailed, In the app or Email, with a picture of each card and where it is in the mail.',
    minVersion: '1.4.1', link: '/app/widget/postcard'
  },
  {
    date: '2026-10-18', emoji: '📍', title: 'Place pages you can trust',
    body: "Every place now shows its own hours, phone number and website, filled in from Google and kept on the place itself."
  },
  {
    date: '2026-10-18', emoji: '🤗', title: 'Kinder How Are You? reactions',
    body: "A reaction now fits the answer: on a hard day your 🙏 says “Hoping it gets better soon” instead of “Glad to hear it.”",
    link: '/app/widget/howareyou'
  },
  {
    date: '2026-10-17', emoji: '🥕', title: 'Farmers markets with days and hours',
    body: "The Locals tab shows nearby farmers markets with a photo and when they're open, checked against two sources. Tap one for its place page."
  },
  {
    date: '2026-10-17', emoji: '🖼️', title: 'Add places from your photos',
    body: 'Add Place → Add from photos finds the cafés, restaurants, parks and venues in your camera roll: pick photos, scan a month or a trip, or build your whole map. You choose which to keep.',
    minVersion: '1.4.0', link: '/app/open?path=add-place'
  },
  {
    date: '2026-10-15', emoji: '🎟️', title: 'The Locals tab',
    body: "What's happening near you: specials from local shops, concerts and games, library events and farmers markets, all on one tab."
  }
];
