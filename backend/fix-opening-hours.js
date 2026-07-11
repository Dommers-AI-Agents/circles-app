// Repair: some places have openingHours stored as an array of Google weekday_text
// strings ("Monday: 11:00 AM – 11:00 PM"). The iOS OpeningHour decoder requires
// objects with an integer `day`, and one malformed place fails the decode of any
// response containing it (e.g. the check-in screen's my-places call).
//
// Converts string entries to { day, hours } objects. iOS already handles the
// legacy `hours` string field and parses/falls back sensibly.
//
// Usage:
//   node fix-opening-hours.js           # dry run
//   node fix-opening-hours.js --apply   # write fixes

const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();
const db = getFirestore();

const APPLY = process.argv.includes('--apply');

// iOS uses 0=Sunday..6=Saturday
const DAY_INDEX = {
  sunday: 0, monday: 1, tuesday: 2, wednesday: 3,
  thursday: 4, friday: 5, saturday: 6
};

function convert(openingHours) {
  return openingHours.map((entry, i) => {
    if (typeof entry !== 'string') return entry; // already an object
    const dayName = entry.split(':')[0].trim().toLowerCase();
    const day = DAY_INDEX[dayName] != null ? DAY_INDEX[dayName] : i % 7;
    return { day, hours: entry };
  });
}

async function main() {
  console.log(`🔍 Scanning all places for string-format openingHours... (${APPLY ? 'APPLY' : 'DRY RUN'})\n`);

  const snapshot = await db.collection('places').get();
  const broken = snapshot.docs.filter(doc => {
    const oh = doc.data().openingHours;
    return Array.isArray(oh) && oh.some(e => typeof e === 'string');
  });
  // Also catch object entries missing an integer day
  const brokenDay = snapshot.docs.filter(doc => {
    const oh = doc.data().openingHours;
    return Array.isArray(oh) && oh.every(e => typeof e !== 'string') &&
           oh.some(e => e && typeof e === 'object' && !Number.isInteger(e.day));
  });

  if (broken.length === 0 && brokenDay.length === 0) {
    console.log('✅ No malformed openingHours found. Nothing to do.');
    return;
  }

  for (const doc of broken) {
    const p = doc.data();
    console.log(`  ${doc.id}  "${p.name}"  addedBy=${p.addedBy}  (string entries: ${p.openingHours.filter(e => typeof e === 'string').length})`);
  }
  for (const doc of brokenDay) {
    const p = doc.data();
    console.log(`  ${doc.id}  "${p.name}"  addedBy=${p.addedBy}  (object entries missing integer day)`);
  }
  console.log(`\n${broken.length} place(s) with string entries, ${brokenDay.length} with day-less objects.`);

  if (!APPLY) {
    console.log('\nDry run only. Re-run with --apply to convert to { day, hours } objects.');
    return;
  }

  const batch = db.batch();
  for (const doc of broken) {
    batch.update(doc.ref, {
      openingHours: convert(doc.data().openingHours),
      updatedAt: new Date().toISOString()
    });
  }
  for (const doc of brokenDay) {
    const fixed = doc.data().openingHours.map((e, i) => (
      e && typeof e === 'object' && !Number.isInteger(e.day) ? { ...e, day: i % 7 } : e
    ));
    batch.update(doc.ref, { openingHours: fixed, updatedAt: new Date().toISOString() });
  }
  await batch.commit();
  console.log(`\n✅ Fixed ${broken.length + brokenDay.length} place(s).`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
