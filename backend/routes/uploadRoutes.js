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
    
    // CRITICAL: Image Size Validation
    // Max size is 1MB for base64 encoded images to prevent storage costs
    // This limit is coordinated with iOS app compression in PlaceService.swift
    // DO NOT increase without updating iOS compression logic
    const imageSizeMB = image.length / (1024 * 1024);
    const imageSizeKB = image.length / 1024;
    
    // Base64 encoding adds ~33% overhead, so 1MB limit for encoded data
    // This translates to roughly 750KB for the actual image
    const maxSizeMB = 1; // 1MB - DO NOT CHANGE without updating iOS
    
    if (imageSizeMB > maxSizeMB) {
      console.error(`Image too large: ${imageSizeMB.toFixed(2)} MB (${imageSizeKB.toFixed(0)} KB)`);
      return res.status(413).json({
        success: false,
        message: `Image too large: ${imageSizeMB.toFixed(2)} MB. Maximum allowed size is ${maxSizeMB} MB. Please ensure iOS app is compressing images properly.`
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