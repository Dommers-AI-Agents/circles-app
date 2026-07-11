// Completely remove the 'test' user (test@favcircles.com) so the email can be
// re-registered for onboarding testing. Removes: Firebase Auth account,
// Firestore user doc, circles, places, connections, and following references.
//
// Usage:
//   node delete-test-user-complete.js           # dry run
//   node delete-test-user-complete.js --apply   # delete everything

require('dotenv').config();
const { initializeFirebase, getFirestore, getAuth } = require('./config/firebase');
initializeFirebase();
const db = getFirestore();
const auth = getAuth();

const EMAIL = 'test@favcircles.com';
const APPLY = process.argv.includes('--apply');

async function main() {
  console.log(`🗑️  Removing test user ${EMAIL}... (${APPLY ? 'APPLY' : 'DRY RUN'})\n`);

  // Locate Firestore user doc(s) by email
  const usersSnap = await db.collection('users').where('email', '==', EMAIL).get();
  if (usersSnap.empty) {
    console.log('No Firestore user doc found for that email.');
  }

  for (const userDoc of usersSnap.docs) {
    const userId = userDoc.id;
    console.log(`User doc: ${userId} (displayName: ${userDoc.data().displayName})`);

    const circles = await db.collection('circles').where('owner', '==', userId).get();
    const places = await db.collection('places').where('addedBy', '==', userId).get();
    const conns1 = await db.collection('connections').where('userId', '==', userId).get();
    const conns2 = await db.collection('connections').where('connectedUserId', '==', userId).get();
    const followers = await db.collection('users').where('following', 'array-contains', userId).get();

    console.log(`  circles: ${circles.size}, places: ${places.size}, connections: ${conns1.size + conns2.size}, followed-by: ${followers.size} user(s)`);
    followers.docs.forEach(d => console.log(`    - ${d.data().displayName} [${d.id}] follows this user`));

    if (!APPLY) continue;

    const batch = db.batch();
    circles.docs.forEach(d => batch.delete(d.ref));
    places.docs.forEach(d => batch.delete(d.ref));
    conns1.docs.forEach(d => batch.delete(d.ref));
    conns2.docs.forEach(d => batch.delete(d.ref));
    followers.docs.forEach(d => {
      const following = (d.data().following || []).filter(id => id !== userId);
      batch.update(d.ref, { following });
    });
    batch.delete(userDoc.ref);
    await batch.commit();
    console.log('  ✓ Firestore data deleted');
  }

  // Delete the Firebase Auth account so the email can be re-registered
  try {
    const authUser = await auth.getUserByEmail(EMAIL);
    console.log(`\nFirebase Auth account: ${authUser.uid}`);
    if (APPLY) {
      await auth.deleteUser(authUser.uid);
      console.log('  ✓ Firebase Auth account deleted');
    }
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      console.log('\nNo Firebase Auth account for that email.');
    } else {
      throw e;
    }
  }

  console.log(APPLY ? '\n✅ Test user fully removed - email is free to re-register.' : '\nDry run only. Re-run with --apply to delete.');
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
