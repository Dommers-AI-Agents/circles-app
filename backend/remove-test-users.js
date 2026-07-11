const { initializeFirebase, getFirestore } = require('./config/firebase');

// Initialize Firebase
initializeFirebase();

const db = getFirestore();

const testUsersToRemove = [
  'test4',
  'test6',
  'wesley2',
  'wesley5',
  'wesley6',
  'John Apple',
  'Apple User'
];

async function removeTestUsers() {
  console.log('🗑️  Starting test user removal...\n');

  for (const displayName of testUsersToRemove) {
    try {
      console.log(`\n🔍 Searching for user: "${displayName}"`);

      // Find user by display name
      const usersSnapshot = await db.collection('users')
        .where('displayName', '==', displayName)
        .get();

      if (usersSnapshot.empty) {
        console.log(`   ⚠️  User "${displayName}" not found`);
        continue;
      }

      for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const userData = userDoc.data();

        console.log(`   ✓ Found user: ${userId}`);
        console.log(`   Email: ${userData.email || 'N/A'}`);

        // Count related data before deletion
        const circlesSnapshot = await db.collection('circles')
          .where('owner', '==', userId)
          .get();

        const placesSnapshot = await db.collection('places')
          .where('userId', '==', userId)
          .get();

        console.log(`   Data to delete:`);
        console.log(`     - User account: 1`);
        console.log(`     - Circles: ${circlesSnapshot.size}`);
        console.log(`     - Places: ${placesSnapshot.size}`);

        // Delete user's circles
        if (!circlesSnapshot.empty) {
          const batch = db.batch();
          circlesSnapshot.docs.forEach(doc => batch.delete(doc.ref));
          await batch.commit();
          console.log(`   ✓ Deleted ${circlesSnapshot.size} circles`);
        }

        // Delete user's places
        if (!placesSnapshot.empty) {
          const batch = db.batch();
          placesSnapshot.docs.forEach(doc => batch.delete(doc.ref));
          await batch.commit();
          console.log(`   ✓ Deleted ${placesSnapshot.size} places`);
        }

        // Delete user document
        await userDoc.ref.delete();
        console.log(`   ✓ Deleted user account`);
        console.log(`   ✅ User "${displayName}" completely removed`);
      }
    } catch (error) {
      console.error(`   ❌ Error removing user "${displayName}":`, error.message);
    }
  }

  console.log('\n✅ Test user removal complete!');
}

removeTestUsers()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
