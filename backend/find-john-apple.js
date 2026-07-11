const { initializeFirebase, getFirestore } = require('./config/firebase');

// Initialize Firebase
initializeFirebase();

const db = getFirestore();

async function findJohnApple() {
  console.log('🔍 Searching for "John" users...\n');

  // Search for users with "John" in display name
  const usersSnapshot = await db.collection('users').get();

  const johnUsers = usersSnapshot.docs.filter(doc => {
    const displayName = doc.data().displayName || '';
    return displayName.toLowerCase().includes('john');
  });

  if (johnUsers.length === 0) {
    console.log('No users found with "John" in their name');
    return;
  }

  console.log(`Found ${johnUsers.length} user(s) with "John" in their name:\n`);

  for (const userDoc of johnUsers) {
    const userData = userDoc.data();
    console.log(`User ID: ${userDoc.id}`);
    console.log(`Display Name: ${userData.displayName}`);
    console.log(`Email: ${userData.email || 'N/A'}`);
    console.log('---');
  }
}

findJohnApple()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
