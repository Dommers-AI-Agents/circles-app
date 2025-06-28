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
      imageSizeMB: image ? (image.length / (1024 * 1024)).toFixed(2) : 0,
      filename: filename,
      userId: req.user?.uid || 'unknown'
    });
    
    if (!image) {
      return res.status(400).json({
        success: false,
        message: 'No image data provided'
      });
    }
    
    // Check if image is too large (should be much smaller now with compression)
    const imageSizeMB = image.length / (1024 * 1024);
    const imageSizeKB = image.length / 1024;
    
    if (imageSizeMB > 5) {
      console.error(`Image unexpectedly large: ${imageSizeMB.toFixed(2)} MB`);
      return res.status(413).json({
        success: false,
        message: `Image too large: ${imageSizeMB.toFixed(2)} MB. Images should be under 1 MB after compression.`
      });
    }
    
    // Log expected small size
    console.log(`Processing compressed image: ${imageSizeKB.toFixed(0)} KB`);
    
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
    console.error('Error stack:', error.stack);
    
    // Check for specific error types
    if (error.code === 'LIMIT_FILE_SIZE' || error.message?.includes('too large')) {
      return res.status(413).json({
        success: false,
        message: 'Request entity too large. Please reduce image size.'
      });
    }
    
    res.status(500).json({
      success: false,
      message: 'Failed to upload image',
      error: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

module.exports = router;