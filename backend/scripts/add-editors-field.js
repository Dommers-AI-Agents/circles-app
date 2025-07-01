// Migration script to add editors field to existing circles
const { initializeFirebase, getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

async function addEditorsField() {
  try {
    await initializeFirebase();
    const db = getFirestore();
    
    console.log('Starting circle migration to add editors field...');
    
    // Get all circles
    const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES).get();
    
    console.log(`Found ${circlesSnapshot.size} circles to check`);
    
    const batch = db.batch();
    let updateCount = 0;
    
    circlesSnapshot.docs.forEach(doc => {
      const data = doc.data();
      
      // Only update if editors field is missing
      if (data.editors === undefined) {
        batch.update(doc.ref, {
          editors: [],
          updatedAt: new Date().toISOString()
        });
        updateCount++;
      }
    });
    
    if (updateCount > 0) {
      await batch.commit();
      console.log(`Successfully updated ${updateCount} circles with editors field`);
    } else {
      console.log('All circles already have editors field');
    }
    
    console.log('Migration completed successfully');
    process.exit(0);
  } catch (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  }
}

addEditorsField();