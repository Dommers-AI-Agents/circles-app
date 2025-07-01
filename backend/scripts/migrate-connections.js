// Migration script to add activity tracking fields to existing connections
const { initializeFirebase, getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

async function migrateConnections() {
  try {
    await initializeFirebase();
    const db = getFirestore();
    
    console.log('Starting connection migration...');
    
    // Get all connections
    const connectionsSnapshot = await db.collection(COLLECTIONS.CONNECTIONS).get();
    
    console.log(`Found ${connectionsSnapshot.size} connections to migrate`);
    
    const batch = db.batch();
    let updateCount = 0;
    
    connectionsSnapshot.docs.forEach(doc => {
      const data = doc.data();
      const updates = {};
      
      // Add missing activity tracking fields with defaults
      if (data.viewCount === undefined) {
        updates.viewCount = 0;
      }
      if (data.lastViewedAt === undefined) {
        updates.lastViewedAt = null;
      }
      if (data.recentActivity === undefined) {
        updates.recentActivity = [];
      }
      if (data.hasNewActivity === undefined) {
        updates.hasNewActivity = false;
      }
      if (data.lastInteractionAt === undefined) {
        updates.lastInteractionAt = null;
      }
      if (data.interactionCount === undefined) {
        updates.interactionCount = 0;
      }
      if (data.lastAccessedCircles === undefined) {
        updates.lastAccessedCircles = [];
      }
      
      // Only update if there are changes
      if (Object.keys(updates).length > 0) {
        batch.update(doc.ref, updates);
        updateCount++;
      }
    });
    
    if (updateCount > 0) {
      await batch.commit();
      console.log(`Successfully updated ${updateCount} connections`);
    } else {
      console.log('No connections needed updating');
    }
    
    console.log('Migration completed successfully');
    process.exit(0);
  } catch (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  }
}

migrateConnections();