// Optimized version of getMyNetworkCircles with batch operations
const getMyNetworkCirclesOptimized = async (req, res) => {
  try {
    const userId = req.user.uid;
    console.log('🚀 [Optimized] Getting network circles for user:', userId);

    // Parallel fetch both connection queries
    const [connectionsQuery1, connectionsQuery2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);

    // Get connected user IDs
    const connectedUserIds = new Set();
    
    connectionsQuery1.docs.forEach(doc => {
      connectedUserIds.add(doc.data().connectedUserId);
    });
    
    connectionsQuery2.docs.forEach(doc => {
      connectedUserIds.add(doc.data().userId);
    });

    if (connectedUserIds.size === 0) {
      return res.status(200).json({
        success: true,
        data: []
      });
    }

    // Get circles from connected users
    const circlesQuery = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', 'in', Array.from(connectedUserIds))
      .where('privacy', 'in', ['public', 'myNetwork'])
      .get();
    
    const circles = circlesQuery.docs.map(doc => serializeDoc(doc));
    
    // OPTIMIZATION: Batch fetch all unique owner IDs
    const uniqueOwnerIds = [...new Set(circles.map(circle => circle.owner))];
    
    let ownersMap = new Map();
    
    // Firestore 'in' operator has a limit of 10 items
    // So we need to batch the requests
    const ownerBatches = [];
    for (let i = 0; i < uniqueOwnerIds.length; i += 10) {
      ownerBatches.push(uniqueOwnerIds.slice(i, i + 10));
    }
    
    // Fetch all owner details in parallel batches
    const ownerResults = await Promise.all(
      ownerBatches.map(batch => 
        db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', batch)
          .get()
      )
    );
    
    // Combine all results into the map
    ownerResults.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
        ownersMap.set(doc.id, serializeDoc(doc));
      });
    });
    
    // Enrich circles with owner details from map
    circles.forEach(circle => {
      circle.ownerDetails = ownersMap.get(circle.owner) || null;
    });

    console.log(`🚀 [Optimized] Returning ${circles.length} circles with batch-loaded owners`);

    res.status(200).json({
      success: true,
      data: circles
    });

  } catch (error) {
    console.error('Error fetching my network circles:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};