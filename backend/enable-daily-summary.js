const admin = require('firebase-admin');
const serviceAccount = require('./config/firebase-service-account.json');
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function enableDailySummary() {
  const userEmail = 'sgroiwes@gmail.com';
  
  try {
    // Find user
    const userSnapshot = await db.collection('users').where('email', '==', userEmail).limit(1).get();
    
    if (userSnapshot.empty) {
      console.log('❌ User not found');
      return;
    }
    
    const userDoc = userSnapshot.docs[0];
    const userId = userDoc.id;
    const user = userDoc.data();
    
    console.log('👤 Enabling daily summary for:', user.displayName || user.email);
    
    // Update notification preferences
    const currentPrefs = user.notificationPreferences || {};
    const updatedPrefs = {
      ...currentPrefs,
      dailySummary: true
    };
    
    await userDoc.ref.update({
      notificationPreferences: updatedPrefs,
      updatedAt: new Date().toISOString()
    });
    
    console.log('✅ Daily summary enabled!');
    console.log('\nUpdated notification preferences:');
    console.log(JSON.stringify(updatedPrefs, null, 2));
    
    // Now trigger a test summary
    console.log('\n📊 Triggering test daily summary...');
    const dailySummaryService = require('./services/dailySummaryService');
    await dailySummaryService.generateAndSendSummary({ 
      id: userId, 
      ...user,
      notificationPreferences: updatedPrefs 
    });
    
    console.log('✅ Test summary sent!');
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
  
  process.exit(0);
}

enableDailySummary();