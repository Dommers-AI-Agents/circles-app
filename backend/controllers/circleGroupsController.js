// backend/controllers/circleGroupsController.js
const { getFirestore, FieldValue, Timestamp } = require('../config/firebase');
const { createCircleGroup } = require('../models/FirestoreModels');

// Get all circle groups for the current user
exports.getMyCircleGroups = async (req, res) => {
  try {
    const userId = req.user.uid;
    const db = getFirestore();
    
    const snapshot = await db.collection('circleGroups')
      .where('owner', '==', userId)
      .orderBy('createdAt', 'desc')
      .get();
    
    const groups = [];
    snapshot.forEach(doc => {
      groups.push({
        _id: doc.id,
        ...doc.data()
      });
    });
    
    res.json({
      success: true,
      data: groups
    });
  } catch (error) {
    console.error('Error getting circle groups:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get circle groups',
      error: error.message
    });
  }
};

// Create a new circle group
exports.createCircleGroup = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { name, description, circleIds = [] } = req.body;
    
    if (!name) {
      return res.status(400).json({
        success: false,
        message: 'Group name is required'
      });
    }
    
    const db = getFirestore();
    
    // Use the createCircleGroup function from FirestoreModels
    const groupData = createCircleGroup({
      name,
      description: description || '',
      circleIds,
      coverImages: [], // TODO: Extract cover images from circles
      privacy: 'private'
    }, userId);
    
    const docRef = await db.collection('circleGroups').add(groupData);
    
    res.status(201).json({
      success: true,
      data: {
        _id: docRef.id,
        ...groupData
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
exports.updateCircleGroup = async (req, res) => {
  try {
    const userId = req.user.uid;
    const groupId = req.params.id;
    const { name, description, circleIds } = req.body;
    
    const db = getFirestore();
    const groupRef = db.collection('circleGroups').doc(groupId);
    
    // Check if group exists and belongs to user
    const groupDoc = await groupRef.get();
    if (!groupDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle group not found'
      });
    }
    
    if (groupDoc.data().owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to update this group'
      });
    }
    
    const updateData = {
      updatedAt: new Date().toISOString()
    };
    
    if (name !== undefined) updateData.name = name;
    if (description !== undefined) updateData.description = description;
    if (circleIds !== undefined) updateData.circleIds = circleIds;
    
    await groupRef.update(updateData);
    
    const updatedDoc = await groupRef.get();
    
    res.json({
      success: true,
      data: {
        _id: updatedDoc.id,
        ...updatedDoc.data()
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

// Delete a circle group
exports.deleteCircleGroup = async (req, res) => {
  try {
    const userId = req.user.uid;
    const groupId = req.params.id;
    
    const db = getFirestore();
    const groupRef = db.collection('circleGroups').doc(groupId);
    
    // Check if group exists and belongs to user
    const groupDoc = await groupRef.get();
    if (!groupDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle group not found'
      });
    }
    
    if (groupDoc.data().owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to delete this group'
      });
    }
    
    await groupRef.delete();
    
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

// Add a circle to a group
exports.addCircleToGroup = async (req, res) => {
  try {
    const userId = req.user.uid;
    const groupId = req.params.id;
    const { circleId } = req.body;
    
    if (!circleId) {
      return res.status(400).json({
        success: false,
        message: 'Circle ID is required'
      });
    }
    
    const db = getFirestore();
    const groupRef = db.collection('circleGroups').doc(groupId);
    
    // Check if group exists and belongs to user
    const groupDoc = await groupRef.get();
    if (!groupDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle group not found'
      });
    }
    
    if (groupDoc.data().owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to modify this group'
      });
    }
    
    // Check if circle belongs to user
    const circleDoc = await db.collection('circles').doc(circleId).get();
    if (!circleDoc.exists || circleDoc.data().userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Circle not found or does not belong to you'
      });
    }
    
    await groupRef.update({
      circleIds: FieldValue.arrayUnion(circleId),
      updatedAt: new Date().toISOString()
    });
    
    const updatedDoc = await groupRef.get();
    
    res.json({
      success: true,
      data: {
        _id: updatedDoc.id,
        ...updatedDoc.data()
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

// Remove a circle from a group
exports.removeCircleFromGroup = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { groupId, circleId } = req.params;
    
    const db = getFirestore();
    const groupRef = db.collection('circleGroups').doc(groupId);
    
    // Check if group exists and belongs to user
    const groupDoc = await groupRef.get();
    if (!groupDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle group not found'
      });
    }
    
    if (groupDoc.data().owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to modify this group'
      });
    }
    
    await groupRef.update({
      circleIds: FieldValue.arrayRemove(circleId),
      updatedAt: new Date().toISOString()
    });
    
    const updatedDoc = await groupRef.get();
    
    res.json({
      success: true,
      data: {
        _id: updatedDoc.id,
        ...updatedDoc.data()
      }
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