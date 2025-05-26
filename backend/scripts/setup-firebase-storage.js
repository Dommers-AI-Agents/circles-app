// Script to check and setup Firebase Storage
const admin = require('firebase-admin');
const path = require('path');

async function checkFirebaseStorage() {
  console.log('🔍 Checking Firebase Storage configuration...\n');
  
  try {
    // Initialize Firebase if not already initialized
    if (admin.apps.length === 0) {
      const serviceAccountPath = path.join(__dirname, '../config/firebase-service-account.json');
      const serviceAccount = require(serviceAccountPath);
      
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: serviceAccount.project_id,
        storageBucket: `${serviceAccount.project_id}.appspot.com`
      });
      
      console.log('✅ Firebase initialized with project:', serviceAccount.project_id);
    }
    
    // Try to access the storage bucket
    const bucket = admin.storage().bucket();
    console.log('📦 Default bucket name:', bucket.name);
    
    // Try to list files to verify access
    console.log('\n🔍 Testing bucket access...');
    const [files] = await bucket.getFiles({ maxResults: 1 });
    console.log('✅ Successfully accessed storage bucket!');
    console.log('📊 Files in bucket:', files.length);
    
    // Get bucket metadata
    const [metadata] = await bucket.getMetadata();
    console.log('\n📋 Bucket metadata:');
    console.log('  - Name:', metadata.name);
    console.log('  - Location:', metadata.location);
    console.log('  - Storage class:', metadata.storageClass);
    console.log('  - Created:', metadata.timeCreated);
    
    console.log('\n✅ Firebase Storage is properly configured!');
    console.log('\n📝 Use this bucket name in your .env file:');
    console.log(`FIREBASE_STORAGE_BUCKET=${bucket.name}`);
    
  } catch (error) {
    console.error('\n❌ Error accessing Firebase Storage:', error.message);
    
    if (error.code === 404) {
      console.log('\n⚠️  The storage bucket does not exist or is not accessible.');
      console.log('\n📝 To fix this:');
      console.log('1. Go to Firebase Console: https://console.firebase.google.com');
      console.log('2. Select your "circles-app" project');
      console.log('3. Navigate to "Storage" in the left sidebar');
      console.log('4. Click "Get Started" if you haven\'t set up Storage yet');
      console.log('5. Follow the setup wizard (choose your region)');
      console.log('6. Once created, the bucket name will be shown at the top');
      console.log('7. Update your .env file with the correct bucket name');
    } else if (error.code === 403) {
      console.log('\n⚠️  Permission denied. The service account might not have Storage access.');
      console.log('\n📝 To fix this:');
      console.log('1. Go to Firebase Console > Project Settings > Service Accounts');
      console.log('2. Make sure your service account has "Storage Admin" role');
      console.log('3. Or go to Google Cloud Console > IAM & Admin');
      console.log('4. Find your service account and add "Storage Admin" role');
    }
  }
  
  process.exit(0);
}

checkFirebaseStorage();