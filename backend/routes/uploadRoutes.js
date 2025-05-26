// backend/routes/uploadRoutes.js
const express = require('express');
const { uploadImage } = require('../services/storage');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply auth middleware
router.use(protect);

// @desc    Upload an image
// @route   POST /api/upload/image
// @access  Private
router.post('/image', async (req, res, next) => {
  try {
    const { image, filename } = req.body;
    
    // Debug logging
    console.log('Upload request received:', {
      hasImage: !!image,
      imageLength: image ? image.length : 0,
      filename: filename
    });
    
    if (!image) {
      return res.status(400).json({
        success: false,
        message: 'No image data provided'
      });
    }
    
    // Upload image to Firebase Storage
    const imageUrl = await uploadImage(image, filename || 'image.jpg');
    console.log('Image saved to Firebase Storage:', imageUrl);
    
    // Return the Firebase Storage URL directly
    res.status(200).json({
      success: true,
      url: imageUrl
    });
  } catch (error) {
    console.error('Error in image upload:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to upload image'
    });
  }
});

module.exports = router;