const { initializeFirebase, getFirestore } = require('./config/firebase');

// Initialize Firebase
initializeFirebase();

const db = getFirestore();

async function fixUserSubscription() {
  console.log('🔧 Fixing subscription for sgroiwes@gmail.com...\n');

  // Find user by email
  const usersSnapshot = await db.collection('users').where('email', '==', 'sgroiwes@gmail.com').get();

  if (usersSnapshot.empty) {
    console.log('❌ User not found');
    return;
  }

  const userDoc = usersSnapshot.docs[0];
  const userId = userDoc.id;
  const currentData = userDoc.data();

  console.log('Current Status:', currentData.subscriptionStatus || 'none');
  console.log('Current Expiry:', currentData.subscriptionExpiryDate || 'none');

  // Update subscription to active
  const updateData = {
    subscriptionStatus: 'active',
    subscriptionExpiryDate: new Date('2026-11-27T23:59:59.000Z').toISOString(), // Set to 1 year from now
    isPremium: true,
    manuallyVerified: true,
    manualVerificationReason: 'Confirmed premium subscriber - subscription sync issue fixed',
    manualVerificationDate: new Date().toISOString(),
    lastReceiptVerification: new Date().toISOString()
  };

  await userDoc.ref.update(updateData);

  console.log('\n✅ Subscription updated successfully!');
  console.log('New Status: active');
  console.log('New Expiry: November 27, 2026');
  console.log('Premium Status: true');
  console.log('\nThe user should now have unlimited circles! 🎉');
}

fixUserSubscription()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('Error:', err);
    process.exit(1);
  });
