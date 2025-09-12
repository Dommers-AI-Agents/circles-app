// Migration script to standardize notification field names
// Converts senderId/senderName/senderPhoto to fromUserId/fromUserName/fromUserPhoto

const { initializeFirebase, getFirestore } = require('./config/firebase');
const { COLLECTIONS } = require('./models/FirestoreModels');

// Initialize Firebase
initializeFirebase();
const db = getFirestore();

async function migrateNotifications() {
  try {
    console.log('🔄 Starting notification field migration...\n');
    
    // Get all notifications
    const notificationsSnapshot = await db.collection(COLLECTIONS.NOTIFICATIONS).get();
    
    console.log(`Found ${notificationsSnapshot.size} total notifications to check\n`);
    
    let migratedCount = 0;
    let alreadyMigratedCount = 0;
    let batch = db.batch();
    let batchCount = 0;
    const BATCH_SIZE = 500; // Firestore batch limit
    
    for (const doc of notificationsSnapshot.docs) {
      const notification = doc.data();
      
      // Check if this notification needs migration
      if (notification.data && 
          (notification.data.senderId || 
           notification.data.senderName || 
           notification.data.senderPhoto)) {
        
        console.log(`📝 Migrating notification ${doc.id}`);
        console.log(`   Type: ${notification.type}`);
        console.log(`   Old fields: senderId=${notification.data.senderId}, senderName=${notification.data.senderName}`);
        
        // Create updated data object
        const updatedData = { ...notification.data };
        
        // Migrate fields
        if (notification.data.senderId) {
          updatedData.fromUserId = notification.data.senderId;
          delete updatedData.senderId;
        }
        
        if (notification.data.senderName) {
          updatedData.fromUserName = notification.data.senderName;
          delete updatedData.senderName;
        }
        
        if (notification.data.senderPhoto) {
          updatedData.fromUserPhoto = notification.data.senderPhoto;
          delete updatedData.senderPhoto;
        }
        
        // Update the document in the batch
        batch.update(doc.ref, { data: updatedData });
        batchCount++;
        migratedCount++;
        
        // Commit batch when it reaches the limit
        if (batchCount >= BATCH_SIZE) {
          await batch.commit();
          console.log(`✅ Committed batch of ${batchCount} updates`);
          batch = db.batch();
          batchCount = 0;
        }
      } else if (notification.data && 
                 (notification.data.fromUserId || 
                  notification.data.fromUserName || 
                  notification.data.fromUserPhoto)) {
        alreadyMigratedCount++;
      }
    }
    
    // Commit any remaining updates
    if (batchCount > 0) {
      await batch.commit();
      console.log(`✅ Committed final batch of ${batchCount} updates`);
    }
    
    console.log('\n📊 Migration Summary:');
    console.log(`   Total notifications: ${notificationsSnapshot.size}`);
    console.log(`   Migrated: ${migratedCount}`);
    console.log(`   Already using new format: ${alreadyMigratedCount}`);
    console.log(`   Other/No data: ${notificationsSnapshot.size - migratedCount - alreadyMigratedCount}`);
    
    if (migratedCount > 0) {
      console.log('\n✅ Migration completed successfully!');
      console.log('All message notifications now use standardized field names:');
      console.log('   fromUserId (was senderId)');
      console.log('   fromUserName (was senderName)');
      console.log('   fromUserPhoto (was senderPhoto)');
    } else {
      console.log('\n✅ No notifications needed migration - all already using standardized format!');
    }
    
  } catch (error) {
    console.error('❌ Migration failed:', error);
    throw error;
  }
}

// Verification function to check the migration
async function verifyMigration() {
  console.log('\n🔍 Verifying migration...\n');
  
  const notificationsSnapshot = await db.collection(COLLECTIONS.NOTIFICATIONS)
    .limit(20)
    .get();
  
  let hasOldFields = false;
  let hasNewFields = false;
  
  notificationsSnapshot.forEach(doc => {
    const notification = doc.data();
    if (notification.data) {
      if (notification.data.senderId || notification.data.senderName || notification.data.senderPhoto) {
        hasOldFields = true;
        console.log(`❌ Found old fields in notification ${doc.id}`);
      }
      if (notification.data.fromUserId || notification.data.fromUserName || notification.data.fromUserPhoto) {
        hasNewFields = true;
      }
    }
  });
  
  if (hasOldFields) {
    console.log('\n⚠️  Some notifications still have old field names!');
  } else if (hasNewFields) {
    console.log('\n✅ Verification passed! All checked notifications use new field names.');
  } else {
    console.log('\n📭 No notifications with user data fields found in sample.');
  }
}

// Run the migration
console.log('===========================================');
console.log('  NOTIFICATION FIELD MIGRATION SCRIPT');
console.log('===========================================\n');

migrateNotifications()
  .then(() => verifyMigration())
  .then(() => {
    console.log('\n✅ Migration process completed');
    process.exit(0);
  })
  .catch(error => {
    console.error('\n❌ Fatal error:', error);
    process.exit(1);
  });