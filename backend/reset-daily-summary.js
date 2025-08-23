const admin = require('firebase-admin');
const serviceAccount = require('./config/firebase-service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function resetDailySummary() {
  try {
    const wesleyQuery = await db.collection('users')
      .where('email', '==', 'sgroiwes@gmail.com')
      .limit(1)
      .get();
    
    if (!wesleyQuery.empty) {
      const wesleyId = wesleyQuery.docs[0].id;
      
      console.log('Resetting daily summary for Wesley (ID:', wesleyId + ')');
      
      // Set lastDailySummary to yesterday
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      
      await db.collection('users').doc(wesleyId).update({
        lastDailySummary: yesterday.toISOString()
      });
      
      console.log('✅ Reset lastDailySummary to:', yesterday.toISOString());
      console.log('You can now receive today\'s daily summary');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

resetDailySummary();