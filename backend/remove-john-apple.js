const { initializeFirebase, getFirestore } = require('./config/firebase');

// Initialize Firebase
initializeFirebase();

const db = getFirestore();

async function removeJohnApple() {
  console.log('🗑️  Removing "John Apple " user...\n');

  const userId = '3577086e03364a1a9bd6ba02a43cd53c';

  try {
    const userDoc = await db.collection('users').doc(userId).get();

    if (!userDoc.exists) {
      console.log('User not found');
      return;
    }

    const userData = userDoc.data();
    console.log(`Found user: ${userData.displayName}`);
    console.log(`Email: ${userData.email}`);

    // Count related data
    const circlesSnapshot = await db.collection('circles')
      .where('owner', '==', userId)
      .get();

    const placesSnapshot = await db.collection('places')
      .where('userId', '==', userId)
      .get();

    console.log(`\nData to delete:`);
    console.log(`  - User account: 1`);
    console.log(`  - Circles: ${circlesSnapshot.size}`);
    console.log(`  - Places: ${placesSnapshot.size}`);

    // Delete circles
    if (!circlesSnapshot.empty) {
      const batch = db.batch();
      circlesSnapshot.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      console.log(`\n✓ Deleted ${circlesSnapshot.size} circles`);
    }

    // Delete places
    if (!placesSnapshot.empty) {
      const batch = db.batch();
      placesSnapshot.docs.forEach(doc => batch.delete(doc.ref));
      await batch.commit();
      console.log(`✓ Deleted ${placesSnapshot.size} places`);
    }

    // Delete user
    await userDoc.ref.delete();
    console.log(`✓ Deleted user account`);
    console.log(`\n✅ User "John Apple " completely removed`);

  } catch (error) {
    console.error('Error:', error);
  }
}

removeJohnApple()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
