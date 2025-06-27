// Script to identify and optionally migrate old Firebase Storage URLs
const { initializeFirebase, getFirestore } = require('../config/firebase');
const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

async function findOldStorageUrls() {
  console.log('🔍 Searching for old Firebase Storage URLs...\n');
  
  // Initialize Firebase
  initializeFirebase();
  const db = getFirestore();
  
  const oldProjectId = 'circles-app-4902d';
  const newProjectId = 'circles-app-83b67';
  const oldUrls = [];
  
  try {
    // Check circles collection
    console.log('📋 Checking circles collection...');
    const circlesSnapshot = await db.collection('circles').get();
    
    circlesSnapshot.forEach(doc => {
      const data = doc.data();
      
      // Check cover image
      if (data.coverImage && data.coverImage.includes(oldProjectId)) {
        oldUrls.push({
          collection: 'circles',
          docId: doc.id,
          field: 'coverImage',
          url: data.coverImage,
          circleName: data.name
        });
      }
      
      // Check places within circle
      if (data.places && Array.isArray(data.places)) {
        data.places.forEach((place, index) => {
          if (place.imageUrl && place.imageUrl.includes(oldProjectId)) {
            oldUrls.push({
              collection: 'circles',
              docId: doc.id,
              field: `places[${index}].imageUrl`,
              url: place.imageUrl,
              circleName: data.name,
              placeName: place.name
            });
          }
        });
      }
    });
    
    // Check places collection
    console.log('📋 Checking places collection...');
    const placesSnapshot = await db.collection('places').get();
    
    placesSnapshot.forEach(doc => {
      const data = doc.data();
      
      if (data.imageUrl && data.imageUrl.includes(oldProjectId)) {
        oldUrls.push({
          collection: 'places',
          docId: doc.id,
          field: 'imageUrl',
          url: data.imageUrl,
          placeName: data.name
        });
      }
      
      // Check photos array
      if (data.photos && Array.isArray(data.photos)) {
        data.photos.forEach((photo, index) => {
          if (photo && photo.includes(oldProjectId)) {
            oldUrls.push({
              collection: 'places',
              docId: doc.id,
              field: `photos[${index}]`,
              url: photo,
              placeName: data.name
            });
          }
        });
      }
    });
    
    // Check users collection
    console.log('📋 Checking users collection...');
    const usersSnapshot = await db.collection('users').get();
    
    usersSnapshot.forEach(doc => {
      const data = doc.data();
      
      if (data.profilePicture && data.profilePicture.includes(oldProjectId)) {
        oldUrls.push({
          collection: 'users',
          docId: doc.id,
          field: 'profilePicture',
          url: data.profilePicture,
          userName: data.displayName || data.email
        });
      }
    });
    
    // Display results
    console.log('\n📊 Summary:');
    console.log(`Found ${oldUrls.length} URLs from old Firebase project (${oldProjectId})\n`);
    
    if (oldUrls.length > 0) {
      console.log('📋 Affected documents:');
      oldUrls.forEach((item, index) => {
        console.log(`\n${index + 1}. ${item.collection}/${item.docId}`);
        console.log(`   Field: ${item.field}`);
        console.log(`   Name: ${item.circleName || item.placeName || item.userName}`);
        console.log(`   URL: ${item.url.substring(0, 80)}...`);
      });
      
      console.log('\n⚠️  These URLs are pointing to the old Firebase project and will return 403 errors.');
      console.log('\n📝 Options to fix this:');
      console.log('1. Remove these image references (set to null)');
      console.log('2. Manually re-upload the images through the app');
      console.log('3. If you have access to the old project, copy the images');
      
      // Ask if user wants to remove the references
      rl.question('\nDo you want to remove these old image references? (yes/no): ', async (answer) => {
        if (answer.toLowerCase() === 'yes') {
          console.log('\n🔧 Removing old image references...');
          
          for (const item of oldUrls) {
            try {
              const docRef = db.collection(item.collection).doc(item.docId);
              
              if (item.field.includes('[')) {
                // Handle array fields
                console.log(`⚠️  Skipping array field ${item.field} - manual update required`);
              } else {
                // Simple field update
                await docRef.update({ [item.field]: null });
                console.log(`✅ Cleared ${item.collection}/${item.docId} - ${item.field}`);
              }
            } catch (error) {
              console.error(`❌ Error updating ${item.collection}/${item.docId}:`, error.message);
            }
          }
          
          console.log('\n✅ Cleanup complete!');
          console.log('📝 Users will need to re-upload images through the app.');
        } else {
          console.log('\n📝 No changes made. You can run this script again later.');
        }
        
        rl.close();
        process.exit(0);
      });
    } else {
      console.log('✅ No old Firebase Storage URLs found!');
      rl.close();
      process.exit(0);
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    rl.close();
    process.exit(1);
  }
}

// Run the script
findOldStorageUrls();