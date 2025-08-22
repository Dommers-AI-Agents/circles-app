// backend/controllers/circleGroupController.js
const admin = require('../config/firebase');
const db = admin.firestore();
const { v4: uuidv4 } = require('uuid');

// Get all circle groups for the current user
exports.getGroups = async (req, res) => {
  try {
    const userId = req.userId;
    
    // Fetch all groups owned by the user
    const groupsSnapshot = await db.collection('circleGroups')
      .where('owner', '==', userId)
      .orderBy('createdAt', 'desc')
      .get();
    
    const groups = [];
    
    for (const doc of groupsSnapshot.docs) {
      const groupData = doc.data();
      const group = {
        id: doc.id,
        ...groupData,
        createdAt: groupData.createdAt?.toDate?.() || groupData.createdAt,
        updatedAt: groupData.updatedAt?.toDate?.() || groupData.updatedAt
      };
      
      // Optionally fetch the circles within each group
      if (groupData.circleIds && groupData.circleIds.length > 0) {
        const circlesSnapshot = await db.collection('circles')
          .where(admin.firestore.FieldPath.documentId(), 'in', groupData.circleIds.slice(0, 10)) // Firestore limit
          .get();
        
        group.circles = circlesSnapshot.docs.map(circleDoc => ({
          id: circleDoc.id,
          ...circleDoc.data()
        }));
      }
      
      groups.push(group);
    }
    
    res.json({
      success: true,
      data: groups
    });
  } catch (error) {
    console.error('Error fetching circle groups:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch circle groups',
      error: error.message
    });
  }
};

// Get a specific circle group
exports.getGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const userId = req.userId;
    
    const groupDoc = await db.collection('circleGroups').doc(groupId).get();
    
    if (!groupDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle group not found'
      });
    }
    
    const groupData = groupDoc.data();
    
    // Check if user has access to this group
    if (groupData.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }
    
    const group = {
      id: groupDoc.id,
      ...groupData,
      createdAt: groupData.createdAt?.toDate?.() || groupData.createdAt,
      updatedAt: groupData.updatedAt?.toDate?.() || groupData.updatedAt
    };
    
    // Fetch the circles within the group
    if (groupData.circleIds && groupData.circleIds.length > 0) {
      const circlesSnapshot = await db.collection('circles')
        .where(admin.firestore.FieldPath.documentId(), 'in', groupData.circleIds.slice(0, 10))
        .get();
      
      group.circles = circlesSnapshot.docs.map(circleDoc => ({
        id: circleDoc.id,
        ...circleDoc.data()
      }));
    }
    
    res.json({
      success: true,
      data: group
    });
  } catch (error) {
    console.error('Error fetching circle group:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch circle group',
      error: error.message
    });
  }
};

// Create a new circle group
exports.createGroup = async (req, res) => {
  try {
    const { name, circleIds } = req.body;
    const userId = req.userId;
    
    if (!name || !circleIds || circleIds.length < 2) {
      return res.status(400).json({
        success: false,
        message: 'Name and at least 2 circle IDs are required'
      });
    }
    
    // Verify that all circles belong to the user
    const circlesSnapshot = await db.collection('circles')
      .where(admin.firestore.FieldPath.documentId(), 'in', circleIds)
      .where('owner', '==', userId)
      .get();
    
    if (circlesSnapshot.size !== circleIds.length) {
      return res.status(403).json({
        success: false,
        message: 'One or more circles do not belong to you'
      });
    }
    
    // Get cover images from the first 4 circles
    const coverImages = [];
    circlesSnapshot.docs.slice(0, 4).forEach(doc => {
      const circleData = doc.data();
      if (circleData.coverImage) {
        coverImages.push(circleData.coverImage);
      }
    });
    
    // Create the group
    const groupId = uuidv4();
    const groupData = {
      name,
      circleIds,
      coverImages,
      owner: userId,
      circleCount: circleIds.length,
      privacy: 'private', // Default to private, can be updated later
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    
    await db.collection('circleGroups').doc(groupId).set(groupData);
    
    // Update each circle to mark it as part of this group
    const batch = db.batch();
    circleIds.forEach((circleId, index) => {
      const circleRef = db.collection('circles').doc(circleId);
      batch.update(circleRef, {
        groupId,
        orderInGroup: index,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });
    await batch.commit();
    
    res.status(201).json({
      success: true,
      data: {
        id: groupId,
        ...groupData,
        createdAt: new Date(),
        updatedAt: new Date()
      }
    });
  } catch (error) {
    console.error('Error creating circle group:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create circle group',
      error: error.message
    });
  }
};

// Update a circle group
exports.updateGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { name, circleIds } = req.body;
    const userId = req.userId;
    
    const groupRef = db.collection('circleGroups').doc(groupId);
    const groupDoc = await groupRef.get();
    
    if (!groupDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle group not found'
      });
    }
    
    const groupData = groupDoc.data();
    
    if (groupData.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }
    
    const updates = {
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    };
    
    if (name) {
      updates.name = name;
    }
    
    if (circleIds && circleIds.length >= 2) {
      // Verify all circles belong to the user
      const circlesSnapshot = await db.collection('circles')
        .where(admin.firestore.FieldPath.documentId(), 'in', circleIds)
        .where('owner', '==', userId)
        .get();
      
      if (circlesSnapshot.size !== circleIds.length) {
        return res.status(403).json({
          success: false,
          message: 'One or more circles do not belong to you'
        });
      }
      
      // Update cover images
      const coverImages = [];
      circlesSnapshot.docs.slice(0, 4).forEach(doc => {
        const circleData = doc.data();
        if (circleData.coverImage) {
          coverImages.push(circleData.coverImage);
        }
      });
      
      updates.circleIds = circleIds;
      updates.coverImages = coverImages;
      updates.circleCount = circleIds.length;
      
      // Update circles' group associations
      const batch = db.batch();
      
      // Remove old circles from group
      const oldCircleIds = groupData.circleIds || [];
      oldCircleIds.forEach(circleId => {
        if (!circleIds.includes(circleId)) {
          const circleRef = db.collection('circles').doc(circleId);
          batch.update(circleRef, {
            groupId: admin.firestore.FieldValue.delete(),
            orderInGroup: admin.firestore.FieldValue.delete(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp()
          });
        }
      });
      
      // Add/update new circles
      circleIds.forEach((circleId, index) => {
        const circleRef = db.collection('circles').doc(circleId);
        batch.update(circleRef, {
          groupId,
          orderInGroup: index,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });
      
      await batch.commit();
    }
    
    await groupRef.update(updates);
    
    const updatedDoc = await groupRef.get();
    const updatedData = updatedDoc.data();
    
    res.json({
      success: true,
      data: {
        id: groupId,
        ...updatedData,
        createdAt: updatedData.createdAt?.toDate?.() || updatedData.createdAt,
        updatedAt: updatedData.updatedAt?.toDate?.() || updatedData.updatedAt
      }
    });
  } catch (error) {
    console.error('Error updating circle group:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update circle group',
      error: error.message
    });
  }
};

// Delete a circle group (ungroups the circles)
exports.deleteGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const userId = req.userId;
    
    const groupRef = db.collection('circleGroups').doc(groupId);
    const groupDoc = await groupRef.get();
    
    if (!groupDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle group not found'
      });
    }
    
    const groupData = groupDoc.data();
    
    if (groupData.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }
    
    // Remove group association from all circles
    const batch = db.batch();
    const circleIds = groupData.circleIds || [];
    
    circleIds.forEach(circleId => {
      const circleRef = db.collection('circles').doc(circleId);
      batch.update(circleRef, {
        groupId: admin.firestore.FieldValue.delete(),
        orderInGroup: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    });
    
    // Delete the group
    batch.delete(groupRef);
    
    await batch.commit();
    
    res.json({
      success: true,
      message: 'Circle group deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting circle group:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete circle group',
      error: error.message
    });
  }
};

// Add a circle to an existing group
exports.addCircleToGroup = async (req, res) => {
  try {
    const { id: circleId } = req.params;
    const { groupId } = req.body;
    const userId = req.userId;
    
    if (!groupId) {
      return res.status(400).json({
        success: false,
        message: 'Group ID is required'
      });
    }
    
    // Verify circle ownership
    const circleDoc = await db.collection('circles').doc(circleId).get();
    if (!circleDoc.exists || circleDoc.data().owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Circle not found or access denied'
      });
    }
    
    // Verify group ownership
    const groupRef = db.collection('circleGroups').doc(groupId);
    const groupDoc = await groupRef.get();
    
    if (!groupDoc.exists || groupDoc.data().owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Group not found or access denied'
      });
    }
    
    const groupData = groupDoc.data();
    const circleIds = groupData.circleIds || [];
    
    if (circleIds.includes(circleId)) {
      return res.status(400).json({
        success: false,
        message: 'Circle is already in this group'
      });
    }
    
    // Add circle to group
    circleIds.push(circleId);
    
    // Update cover images if needed
    const coverImages = [...(groupData.coverImages || [])];
    if (coverImages.length < 4 && circleDoc.data().coverImage) {
      coverImages.push(circleDoc.data().coverImage);
    }
    
    const batch = db.batch();
    
    // Update group
    batch.update(groupRef, {
      circleIds,
      coverImages,
      circleCount: circleIds.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    // Update circle
    batch.update(db.collection('circles').doc(circleId), {
      groupId,
      orderInGroup: circleIds.length - 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    await batch.commit();
    
    const updatedGroupDoc = await groupRef.get();
    const updatedData = updatedGroupDoc.data();
    
    res.json({
      success: true,
      data: {
        id: groupId,
        ...updatedData,
        createdAt: updatedData.createdAt?.toDate?.() || updatedData.createdAt,
        updatedAt: updatedData.updatedAt?.toDate?.() || updatedData.updatedAt
      }
    });
  } catch (error) {
    console.error('Error adding circle to group:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to add circle to group',
      error: error.message
    });
  }
};

// Remove a circle from its group
exports.removeCircleFromGroup = async (req, res) => {
  try {
    const { id: circleId } = req.params;
    const userId = req.userId;
    
    // Get the circle
    const circleRef = db.collection('circles').doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists || circleDoc.data().owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Circle not found or access denied'
      });
    }
    
    const circleData = circleDoc.data();
    const groupId = circleData.groupId;
    
    if (!groupId) {
      return res.status(400).json({
        success: false,
        message: 'Circle is not in a group'
      });
    }
    
    // Get the group
    const groupRef = db.collection('circleGroups').doc(groupId);
    const groupDoc = await groupRef.get();
    
    if (!groupDoc.exists) {
      // Group doesn't exist, just remove the groupId from circle
      await circleRef.update({
        groupId: admin.firestore.FieldValue.delete(),
        orderInGroup: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      return res.json({
        success: true,
        message: 'Circle removed from group'
      });
    }
    
    const groupData = groupDoc.data();
    let circleIds = groupData.circleIds || [];
    
    // Remove circle from group's circle list
    circleIds = circleIds.filter(id => id !== circleId);
    
    const batch = db.batch();
    
    if (circleIds.length < 2) {
      // If less than 2 circles remain, delete the group
      batch.delete(groupRef);
      
      // Remove group association from remaining circles
      circleIds.forEach(id => {
        batch.update(db.collection('circles').doc(id), {
          groupId: admin.firestore.FieldValue.delete(),
          orderInGroup: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });
    } else {
      // Update the group with remaining circles
      const coverImages = [];
      
      // Get cover images from remaining circles
      const remainingCirclesSnapshot = await db.collection('circles')
        .where(admin.firestore.FieldPath.documentId(), 'in', circleIds.slice(0, 4))
        .get();
      
      remainingCirclesSnapshot.docs.forEach(doc => {
        const data = doc.data();
        if (data.coverImage) {
          coverImages.push(data.coverImage);
        }
      });
      
      batch.update(groupRef, {
        circleIds,
        coverImages,
        circleCount: circleIds.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      
      // Update order for remaining circles
      circleIds.forEach((id, index) => {
        batch.update(db.collection('circles').doc(id), {
          orderInGroup: index,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });
    }
    
    // Remove group association from the removed circle
    batch.update(circleRef, {
      groupId: admin.firestore.FieldValue.delete(),
      orderInGroup: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    await batch.commit();
    
    res.json({
      success: true,
      message: circleIds.length < 2 ? 'Circle removed and group deleted' : 'Circle removed from group'
    });
  } catch (error) {
    console.error('Error removing circle from group:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to remove circle from group',
      error: error.message
    });
  }
};