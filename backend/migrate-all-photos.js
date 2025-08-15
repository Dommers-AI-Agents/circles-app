const axios = require('axios');
const admin = require('firebase-admin');
const serviceAccount = require('./config/firebase-service-account.json');
const { downloadAndUploadMultipleImages } = require('./services/storage');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'circles-app-83b67'
});

const db = admin.firestore();

async function migratePhotos() {
  try {
    console.log('🔄 Starting photo migration...');
    
    // Query for places with Google API URLs
    const placesSnapshot = await db.collection('places').get();
    
    const placesToMigrate = [];
    const migrationResults = [];
    
    // Find places with actual Google Places API URLs (not Firebase URLs)
    placesSnapshot.forEach(doc => {
      const place = doc.data();
      
      if (place.photos && place.photos.length > 0) {
        const googleUrls = place.photos.filter(photo => 
          typeof photo === 'string' && (
            photo.includes('maps.googleapis.com') || 
            photo.includes('photoreference=')
          )
        );
        
        if (googleUrls.length > 0) {
          placesToMigrate.push({
            id: doc.id,
            name: place.name,
            photos: place.photos,
            googleUrls: googleUrls
          });
        }
      }
    });
    
    console.log(`📊 Found ${placesToMigrate.length} places with Google Places API URLs`);
    
    if (placesToMigrate.length === 0) {
      console.log('✅ No places need migration!');
      process.exit(0);
    }
    
    // Process each place
    for (const place of placesToMigrate) {
      try {
        console.log(`\nProcessing: ${place.name} (${place.id})`);
        console.log(`  Google URLs to migrate: ${place.googleUrls.length}`);
        
        // Download and upload Google photos
        const { uploadedUrls, errors } = await downloadAndUploadMultipleImages(place.googleUrls);
        
        if (uploadedUrls.length > 0) {
          // Filter out Google URLs and add Firebase URLs
          const nonGoogleUrls = place.photos.filter(photo => 
            !photo.includes('maps.googleapis.com') && 
            !photo.includes('photoreference=')
          );
          
          const newPhotos = [...nonGoogleUrls, ...uploadedUrls];
          
          // Update the place in Firestore
          await db.collection('places').doc(place.id).update({
            photos: newPhotos,
            updatedAt: new Date().toISOString()
          });
          
          migrationResults.push({
            placeId: place.id,
            placeName: place.name,
            status: 'success',
            migratedCount: uploadedUrls.length,
            failedCount: errors.length
          });
          
          console.log(`  ✅ Migrated ${uploadedUrls.length} photos`);
        } else {
          migrationResults.push({
            placeId: place.id,
            placeName: place.name,
            status: 'failed',
            error: 'No photos could be migrated',
            errors: errors
          });
          
          console.error(`  ❌ Failed to migrate photos`);
        }
      } catch (error) {
        console.error(`  ❌ Error: ${error.message}`);
        migrationResults.push({
          placeId: place.id,
          placeName: place.name,
          status: 'error',
          error: error.message
        });
      }
      
      // Small delay to avoid rate limiting
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    
    // Summary
    const successCount = migrationResults.filter(r => r.status === 'success').length;
    const failedCount = migrationResults.filter(r => r.status !== 'success').length;
    
    console.log('\n' + '='.repeat(50));
    console.log('📊 Migration Summary:');
    console.log(`  Total places processed: ${migrationResults.length}`);
    console.log(`  ✅ Successful: ${successCount}`);
    console.log(`  ❌ Failed: ${failedCount}`);
    
    if (failedCount > 0) {
      console.log('\nFailed migrations:');
      migrationResults.filter(r => r.status !== 'success').forEach(r => {
        console.log(`  - ${r.placeName}: ${r.error || 'Unknown error'}`);
      });
    }
    
    process.exit(0);
  } catch (error) {
    console.error('Fatal error:', error);
    process.exit(1);
  }
}

// Run the migration
migratePhotos();