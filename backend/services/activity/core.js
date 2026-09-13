// backend/services/activity/core.js
// Activity service — shared helpers: the activity log writer and the place-photo resolver.
// Split from services/activityService.js (Phase 6); that path is now a barrel.

const { admin, getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const db = getFirestore();


// Resolve a place's thumbnail (photos are {url} objects or bare strings),
// falling back to the canonical globalPlaces record. Best-effort → null.
const resolvePlacePhoto = async (placeId) => {
  const firstUrl = (data) => {
    const first = (data.photos || [])[0];
    return typeof first === 'string' ? first : (first && first.url) || null;
  };
  try {
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    if (!placeDoc.exists) return null;
    const data = placeDoc.data();
    let url = firstUrl(data);
    if (!url && data.globalPlaceId) {
      const g = await db.collection('globalPlaces').doc(data.globalPlaceId).get();
      if (g.exists) url = firstUrl(g.data());
    }
    return url;
  } catch (e) {
    console.error('⚠️ resolvePlacePhoto failed:', e.message);
    return null;
  }
};


// General activity logging for various types
const logActivity = async (activityData) => {
  try {
    const { type, actorId, visibility = 'connections', ...metadata } = activityData;
    
    const activityDoc = {
      type,
      actorId,
      visibility,
      metadata,
      createdAt: new Date().toISOString()
    };
    
    // Save to activities collection
    await db.collection(COLLECTIONS.ACTIVITIES).add(activityDoc);
    
    // If visibility is connections, update connection documents
    if (visibility === 'connections') {
      // Get all connections of the actor
      const [connections1, connections2] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', actorId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('connectedUserId', '==', actorId)
          .where('status', '==', 'accepted')
          .get()
      ]);
      
      const batch = db.batch();
      const allConnections = [...connections1.docs, ...connections2.docs];
      
      allConnections.forEach(doc => {
        const connectionData = doc.data();
        const connectionRef = doc.ref;
        
        // Determine the other user's ID
        const otherUserId = connectionData.userId === actorId 
          ? connectionData.connectedUserId 
          : connectionData.userId;
        
        const activity = {
          type,
          ...metadata,
          actorId,
          createdAt: new Date().toISOString(),
          viewedBy: [actorId]
        };
        
        // Update connection with new activity
        batch.update(connectionRef, {
          hasNewActivity: true,
          recentActivity: admin.firestore.FieldValue.arrayUnion(activity),
          updatedAt: new Date().toISOString()
        });
      });
      
      await batch.commit();
    }
    
    console.log(`✅ Logged ${type} activity for user ${actorId}`);
  } catch (error) {
    console.error('Error logging activity:', error);
    throw error;
  }
};

module.exports = {
  logActivity,
  // Shared with the sibling submodules only; the barrel keeps it private.
  resolvePlacePhoto,
};
