// backend/controllers/userCategoriesController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');

const db = getFirestore();

// @desc    Get user's custom categories
// @route   GET /api/users/categories
// @access  Private
exports.getUserCategories = async (req, res, next) => {
  try {
    console.log('🔍 getUserCategories called');
    console.log('🔍 User:', req.user ? req.user.uid : 'NO USER');
    
    if (!req.user || !req.user.uid) {
      console.error('❌ No user found in request');
      return res.status(401).json({
        success: false,
        message: 'User not authenticated'
      });
    }
    
    const userId = req.user.uid;
    console.log(`🔍 Fetching categories for user: ${userId}`);
    
    try {
      const categoriesSnapshot = await db.collection(COLLECTIONS.USER_CATEGORIES)
        .where('userId', '==', userId)
        .orderBy('createdAt', 'desc')
        .get();
      
      const categories = serializeQuerySnapshot(categoriesSnapshot);
      console.log(`✅ Found ${categories.length} categories for user ${userId}`);
      
      // Return empty array if no categories exist (not an error)
      return res.status(200).json({
        success: true,
        data: categories || []
      });
    } catch (queryError) {
      // Handle case where collection doesn't exist or index is missing
      if (queryError.code === 9 || queryError.message?.includes('index')) {
        console.log('⚠️ Collection or index not found, returning empty categories');
        return res.status(200).json({
          success: true,
          data: []
        });
      }
      throw queryError;
    }
  } catch (error) {
    console.error('❌ Error fetching user categories:', error);
    console.error('Error details:', error.message);
    console.error('Error stack:', error.stack);
    next(error);
  }
};

// @desc    Create custom category
// @route   POST /api/users/categories
// @access  Private
exports.createCategory = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { name, type, icon, color, subcategories } = req.body;
    
    // Validate required fields
    if (!name || !type) {
      return res.status(400).json({
        success: false,
        message: 'Name and type are required'
      });
    }
    
    // Validate type
    if (!['place', 'circle', 'both'].includes(type)) {
      return res.status(400).json({
        success: false,
        message: 'Type must be "place", "circle", or "both"'
      });
    }
    
    // Check if category name already exists for this user
    const existingCategory = await db.collection(COLLECTIONS.USER_CATEGORIES)
      .where('userId', '==', userId)
      .where('name', '==', name)
      .get();
    
    if (!existingCategory.empty) {
      return res.status(409).json({
        success: false,
        message: 'Category with this name already exists'
      });
    }
    
    const categoryData = {
      userId,
      name: name.trim(),
      type,
      icon: icon || null,
      color: color || null,
      subcategories: subcategories || [],
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    
    const docRef = await db.collection(COLLECTIONS.USER_CATEGORIES).add(categoryData);
    const newDoc = await docRef.get();
    const category = serializeDoc(newDoc);
    
    console.log(`✅ Custom category created: ${name} for user ${userId}`);
    
    res.status(201).json({
      success: true,
      data: category
    });
  } catch (error) {
    console.error('Error creating category:', error);
    next(error);
  }
};

// @desc    Update custom category
// @route   PUT /api/users/categories/:id
// @access  Private
exports.updateCategory = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const categoryId = req.params.id;
    const { name, type, icon, color, subcategories } = req.body;
    
    const categoryRef = db.collection(COLLECTIONS.USER_CATEGORIES).doc(categoryId);
    const categoryDoc = await categoryRef.get();
    
    if (!categoryDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Category not found'
      });
    }
    
    const category = categoryDoc.data();
    
    // Verify ownership
    if (category.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to update this category'
      });
    }
    
    // Validate type if provided
    if (type && !['place', 'circle', 'both'].includes(type)) {
      return res.status(400).json({
        success: false,
        message: 'Type must be "place", "circle", or "both"'
      });
    }
    
    // Check for duplicate name if name is being changed
    if (name && name !== category.name) {
      const existingCategory = await db.collection(COLLECTIONS.USER_CATEGORIES)
        .where('userId', '==', userId)
        .where('name', '==', name)
        .get();
      
      if (!existingCategory.empty) {
        return res.status(409).json({
          success: false,
          message: 'Category with this name already exists'
        });
      }
    }
    
    const updateData = {
      updatedAt: new Date().toISOString()
    };
    
    if (name !== undefined) updateData.name = name.trim();
    if (type !== undefined) updateData.type = type;
    if (icon !== undefined) updateData.icon = icon;
    if (color !== undefined) updateData.color = color;
    if (subcategories !== undefined) updateData.subcategories = subcategories;
    
    await categoryRef.update(updateData);
    
    const updatedDoc = await categoryRef.get();
    const updatedCategory = serializeDoc(updatedDoc);
    
    console.log(`✅ Custom category updated: ${categoryId} for user ${userId}`);
    
    res.status(200).json({
      success: true,
      data: updatedCategory
    });
  } catch (error) {
    console.error('Error updating category:', error);
    next(error);
  }
};

// @desc    Delete custom category
// @route   DELETE /api/users/categories/:id
// @access  Private
exports.deleteCategory = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const categoryId = req.params.id;
    
    const categoryRef = db.collection(COLLECTIONS.USER_CATEGORIES).doc(categoryId);
    const categoryDoc = await categoryRef.get();
    
    if (!categoryDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Category not found'
      });
    }
    
    const category = categoryDoc.data();
    
    // Verify ownership
    if (category.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this category'
      });
    }
    
    // Check if category is being used by any circles or places
    const [circlesUsingCategory, placesUsingCategory] = await Promise.all([
      db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', userId)
        .where('customCategoryId', '==', categoryId)
        .limit(1)
        .get(),
      db.collection(COLLECTIONS.PLACES)
        .where('userId', '==', userId)
        .where('customCategoryId', '==', categoryId)
        .limit(1)
        .get()
    ]);
    
    if (!circlesUsingCategory.empty || !placesUsingCategory.empty) {
      return res.status(409).json({
        success: false,
        message: 'Cannot delete category that is being used by circles or places. Please update them first.'
      });
    }
    
    await categoryRef.delete();
    
    console.log(`✅ Custom category deleted: ${categoryId} for user ${userId}`);
    
    res.status(200).json({
      success: true,
      message: 'Category deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting category:', error);
    next(error);
  }
};

// @desc    Get predefined categories
// @route   GET /api/users/categories/predefined
// @access  Private
exports.getPredefinedCategories = async (req, res, next) => {
  try {
    // Define predefined categories that work for both circles and places
    const predefinedCategories = [
      { id: 'travel', name: 'Travel', type: 'both', icon: 'airplane', color: '#007AFF' },
      { id: 'food', name: 'Food & Dining', type: 'both', icon: 'fork.knife', color: '#FF9500' },
      { id: 'shopping', name: 'Shopping', type: 'both', icon: 'bag', color: '#FF2D92' },
      { id: 'entertainment', name: 'Entertainment', type: 'both', icon: 'tv', color: '#AF52DE' },
      { id: 'health', name: 'Health & Wellness', type: 'both', icon: 'heart', color: '#FF3B30' },
      { id: 'services', name: 'Services', type: 'both', icon: 'wrench', color: '#34C759' },
      { id: 'education', name: 'Education', type: 'both', icon: 'book', color: '#5856D6' },
      { id: 'business', name: 'Business', type: 'both', icon: 'briefcase', color: '#8E8E93' },
      { id: 'other', name: 'Other', type: 'both', icon: 'ellipsis', color: '#6D6D70' }
    ];
    
    res.status(200).json({
      success: true,
      data: predefinedCategories
    });
  } catch (error) {
    console.error('Error fetching predefined categories:', error);
    next(error);
  }
};