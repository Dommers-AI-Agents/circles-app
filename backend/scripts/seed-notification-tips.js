// backend/scripts/seed-notification-tips.js
//
// Seeds / updates the `notificationTips` catalog read by tipsService. Idempotent:
// each tip is keyed by a stable slug doc id and written with { merge: true }, so
// re-running updates copy/flags in place rather than creating duplicates.
//
// Only seed tips whose `target` is a deep-link the iOS app already routes
// (Phase 1 wired `all_places_map` and `create_wallet`). Adding a tip for a brand
// new target before the app can handle it would deep-link to a dead end.
//
//   DRY_RUN=true node scripts/seed-notification-tips.js   # print, write nothing
//   node scripts/seed-notification-tips.js                # live upsert
//
// `order` controls send sequence (ascending). `enabled:false` parks a tip
// without deleting it. `requires:'hasPlaces'` only sends to users with ≥1 saved
// place (unknown counts still send — see tipsService.userMatchesRequirement).
//
// `surfaces` picks the delivery channel: absent/["push"] = the 2×/week push
// job; ["home"] = the home-screen daily card (homePromptService). ⚠️ Do not
// seed a ["home"] card until a backend carrying tipsService.tipMatchesSurface
// is deployed — an older server would push it to everyone. `requires:
// 'noWidgetData'` / 'noVideoViews' are home-only suppression predicates.

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();

const DRY_RUN = process.env.DRY_RUN === 'true';
const COLLECTION = 'notificationTips';

const TIPS = [
  {
    id: 'all-places-worldwide',
    title: 'Your places, one map 🗺️',
    body: 'Did you know you can see all your favorite places saved around the world in one view? Tap to explore your map.',
    target: 'all_places_map',
    requires: 'hasPlaces',
    surfaces: ['push', 'home'],
    order: 10,
    enabled: true
  },
  {
    id: 'favcoins-are-crypto',
    title: 'Your FavCoins are real crypto 🌵',
    body: 'Did you know your FavCoins are real crypto coins? Create your own Cactus wallet right inside FavCircles.',
    target: 'create_wallet',
    surfaces: ['push', 'home'],
    order: 20,
    enabled: true
  },
  // ---- Home daily cards (never pushed) ----
  {
    id: 'home-widgets-tab',
    title: 'Have you seen the Widgets tab?',
    body: 'Water, habits, workouts, bill splits, postcards — little tools that live right on your home screen.',
    actionLabel: 'Show me',
    target: 'widgets_tab',
    requires: 'noWidgetData',
    surfaces: ['home'],
    order: 100,
    enabled: true
  },
  // Every target below is one the SHIPPED app routes (widgets_tab /
  // moments_tab / all_places_map / create_wallet). A tip that deep-links to a
  // target the installed build can't open renders a "Show me" that does
  // nothing — the exact dead button App Review rejects. Widget-specific tips
  // open the Widgets tab for now; switch them to target 'widget' +
  // data.widgetId once the build carrying that route is out (re-running this
  // script updates them in place).
  {
    id: 'home-postcard',
    title: 'Send a postcard 📮',
    body: 'Digital, or printed and mailed for $3.99 — pick a photo, write a note, done. It lives in the Postcard widget.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 90,
    enabled: true
  },
  {
    id: 'home-heartbeat',
    title: 'Check your heart rate ❤️',
    body: 'Fingertip over the camera, or a Bluetooth strap. The Heartbeat widget keeps a log — not a medical device, just a nudge to notice.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 120,
    enabled: true
  },
  {
    id: 'home-workouts',
    title: 'Log a workout 💪',
    body: 'Track your sessions, and see what your Inner Circle has been doing in the Workouts widget.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 130,
    enabled: true
  },
  {
    id: 'home-sleep-sounds',
    title: 'Fall asleep to rain 🌧️',
    body: 'Rain, thunder, indoor hum — mix your own in the Sleep Sounds widget.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 140,
    enabled: true
  },
  {
    id: 'home-water',
    title: 'Drink more water 💧',
    body: 'Log a cup in one tap and get a gentle reminder — quiet hours respected — from the Water widget.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 150,
    enabled: true
  },
  {
    id: 'home-habits',
    title: 'Keep a streak going ✅',
    body: 'Pick a few daily habits and check them off. The Habits widget shows the streak.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 160,
    enabled: true
  },
  {
    id: 'home-bill-split',
    title: 'Split the bill 🧾',
    body: 'Dinner with friends? The Bill Split widget does the math, tip included.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 170,
    enabled: true
  },
  {
    id: 'home-stocks',
    title: 'Watch your stocks 📈',
    body: 'Named watchlists, the indexes, bitcoin and the 10-year — all on one card in the Stocks widget.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 180,
    enabled: true
  },
  {
    id: 'home-calories',
    title: 'Track what you eat 🍽️',
    body: 'A quick calorie log that lives on your home screen — the Calories widget.',
    actionLabel: 'Open Widgets',
    target: 'widgets_tab',
    surfaces: ['home'],
    order: 190,
    enabled: true
  },
  {
    id: 'home-scroll-moments',
    title: 'Have you scrolled the Moments?',
    body: 'Short clips and photos from the people you follow, at the places they love.',
    actionLabel: 'Take a look',
    target: 'moments_tab',
    requires: 'noVideoViews',
    surfaces: ['home'],
    order: 110,
    enabled: true
  }
];

async function run() {
  console.log(`🌱 Seeding ${TIPS.length} tips into '${COLLECTION}'${DRY_RUN ? ' (DRY RUN)' : ''}`);

  for (const tip of TIPS) {
    const { id, ...fields } = tip;
    const payload = { ...fields, updatedAt: new Date().toISOString() };

    if (DRY_RUN) {
      console.log(`  • ${id} → ${JSON.stringify(payload)}`);
      continue;
    }

    await db.collection(COLLECTION).doc(id).set(payload, { merge: true });
    console.log(`  ✅ upserted ${id} (target=${tip.target}, enabled=${tip.enabled})`);
  }

  console.log(DRY_RUN ? '🌱 Dry run complete — nothing written.' : '🌱 Seed complete.');
  process.exit(0);
}

run().catch(err => {
  console.error('❌ Seed failed:', err);
  process.exit(1);
});
