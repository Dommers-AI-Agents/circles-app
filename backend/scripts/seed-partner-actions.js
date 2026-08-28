// backend/scripts/seed-partner-actions.js
//
// Seeds / updates the `partnerActions` catalog read by partnerActionsService
// (place-detail partner deep links). Idempotent: each group is keyed by a stable
// doc id and written with { merge: true }, so re-running updates URLs/flags in
// place rather than creating duplicates.
//
//   DRY_RUN=true node scripts/seed-partner-actions.js   # print, write nothing
//   node scripts/seed-partner-actions.js                # live upsert
//
// Template variables ({name} {address} {city} {lat} {lng} {googlePlaceId}) are
// substituted URL-encoded on the iOS client. Square brackets in templates MUST
// stay pre-encoded (%5B/%5D) — raw brackets make URL(string:) return nil.
// Affiliate swap later = edit webUrlTemplate here (or in Firestore) and re-run.

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();

const DRY_RUN = process.env.DRY_RUN === 'true';
const COLLECTION = 'partnerActions';

const GROUPS = [
  {
    id: 'delivery',
    title: 'Delivery',
    icon: 'takeoutbag.and.cup.and.straw.fill',
    sheetTitle: 'Order delivery with…',
    categories: ['restaurant', 'cafe', 'bar'],
    order: 10,
    enabled: true,
    providers: [
      {
        id: 'doordash',
        title: 'DoorDash',
        webUrlTemplate: 'https://www.doordash.com/search/store/{name}%20{city}',
        enabled: true
      },
      {
        id: 'ubereats',
        title: 'Uber Eats',
        webUrlTemplate: 'https://www.ubereats.com/search?q={name}',
        enabled: true
      }
    ]
  },
  {
    id: 'reserve',
    title: 'Reserve',
    icon: 'fork.knife',
    sheetTitle: 'Book a table with…',
    categories: ['restaurant'],
    order: 20,
    enabled: true,
    providers: [
      {
        id: 'opentable',
        title: 'OpenTable',
        webUrlTemplate: 'https://www.opentable.com/s?term={name}&latitude={lat}&longitude={lng}&covers=2',
        enabled: true
      }
    ]
  },
  {
    id: 'ride',
    title: 'Ride',
    icon: 'car.fill',
    sheetTitle: 'Get a ride with…',
    categories: ['*'],
    order: 30,
    enabled: true,
    providers: [
      {
        id: 'uber',
        title: 'Uber',
        appScheme: 'uber',
        appUrlTemplate: 'uber://?action=setPickup&pickup=my_location&dropoff%5Blatitude%5D={lat}&dropoff%5Blongitude%5D={lng}&dropoff%5Bnickname%5D={name}',
        webUrlTemplate: 'https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff%5Blatitude%5D={lat}&dropoff%5Blongitude%5D={lng}&dropoff%5Bnickname%5D={name}',
        enabled: true
      },
      {
        id: 'lyft',
        title: 'Lyft',
        appScheme: 'lyft',
        appUrlTemplate: 'lyft://ridetype?id=lyft&destination%5Blatitude%5D={lat}&destination%5Blongitude%5D={lng}',
        webUrlTemplate: 'https://ride.lyft.com/',
        enabled: true
      }
    ]
  }
];

async function run() {
  console.log(`🌱 Seeding ${GROUPS.length} partner action groups into '${COLLECTION}'${DRY_RUN ? ' (DRY RUN)' : ''}`);

  for (const group of GROUPS) {
    const { id, ...fields } = group;
    const payload = { ...fields, updatedAt: new Date().toISOString() };

    if (DRY_RUN) {
      console.log(`  • ${id} → ${JSON.stringify(payload)}`);
      continue;
    }

    await db.collection(COLLECTION).doc(id).set(payload, { merge: true });
    console.log(`  ✅ upserted ${id} (${group.providers.length} providers, enabled=${group.enabled})`);
  }
  console.log('Done.');
  process.exit(0);
}

run().catch(err => { console.error(err); process.exit(1); });
