// Verify that notifications are using standardized field names
const { initializeFirebase, getFirestore } = require('./config/firebase');
const { COLLECTIONS } = require('./models/FirestoreModels');

// Initialize Firebase
initializeFirebase();
const db = getFirestore();

// Wesley's ID
const WESLEY_ID = '111819744557116370195';

async function verifyStandardizedNotifications() {
  try {
    console.log('🔍 Verifying standardized notification fields\n');
    
    // Get Wesley's notifications
    const notificationsSnapshot = await db.collection(COLLECTIONS.NOTIFICATIONS)
      .where('userId', '==', WESLEY_ID)
      .orderBy('createdAt', 'desc')
      .limit(5)
      .get();
    
    console.log(`Checking ${notificationsSnapshot.size} recent notifications for Wesley:\n`);
    
    let allStandardized = true;
    
    notificationsSnapshot.forEach(doc => {
      const notif = doc.data();
      console.log(`Type: ${notif.type}`);
      console.log(`Title: ${notif.title}`);
      
      if (notif.data) {
        // Check for old field names
        if (notif.data.senderId || notif.data.senderName || notif.data.senderPhoto) {
          console.log('❌ OLD FIELDS FOUND:');
          if (notif.data.senderId) console.log(`   senderId: ${notif.data.senderId}`);
          if (notif.data.senderName) console.log(`   senderName: ${notif.data.senderName}`);
          if (notif.data.senderPhoto) console.log(`   senderPhoto: ${notif.data.senderPhoto}`);
          allStandardized = false;
        }
        
        // Check for new field names
        if (notif.data.fromUserId || notif.data.fromUserName || notif.data.fromUserPhoto) {
          console.log('✅ Standardized fields:');
          if (notif.data.fromUserId) console.log(`   fromUserId: ${notif.data.fromUserId}`);
          if (notif.data.fromUserName) console.log(`   fromUserName: ${notif.data.fromUserName}`);
          if (notif.data.fromUserPhoto) console.log(`   fromUserPhoto: ${notif.data.fromUserPhoto || 'null (no photo)'}`);
        }
      }
      console.log('---\n');
    });
    
    if (allStandardized) {
      console.log('✅ SUCCESS: All notifications are using standardized field names!');
      console.log('\nStandardized fields:');
      console.log('  - fromUserId (replaces senderId)');
      console.log('  - fromUserName (replaces senderName)');
      console.log('  - fromUserPhoto (replaces senderPhoto)');
    } else {
      console.log('⚠️  WARNING: Some notifications still have old field names');
      console.log('Please run the migration script again.');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

// Run the verification
verifyStandardizedNotifications()
  .then(() => {
    console.log('\n✅ Verification completed');
    process.exit(0);
  })
  .catch(error => {
    console.error('❌ Fatal error:', error);
    process.exit(1);
  });