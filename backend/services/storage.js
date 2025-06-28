// backend/services/storage.js
const { getStorage } = require('../config/firebase');
const { v4: uuidv4 } = require('uuid');

// Upload image to Firebase Storage
const uploadImage = async (base64Data, filename) => {
  try {
    // Remove data URL prefix if present
    const base64 = base64Data.replace(/^data:image\/\w+;base64,/, '');
    
    // Generate unique filename
    const ext = filename.split('.').pop() || 'jpg';
    const uniqueFilename = `circles/${uuidv4()}.${ext}`;
    
    // Get storage bucket
    const storage = getStorage();
    
    // Check for Firebase Storage configuration
    const bucketName = process.env.FIREBASE_STORAGE_BUCKET || 
                      process.env.GCS_BUCKET_NAME || 
                      (process.env.FIREBASE_PROJECT_ID ? `${process.env.FIREBASE_PROJECT_ID}.appspot.com` : null);
    
    if (!bucketName) {
      console.error('Firebase Storage Error: No bucket name configured');
      console.error('Please set one of the following environment variables:');
      console.error('- FIREBASE_STORAGE_BUCKET (e.g., your-project.appspot.com)');
      console.error('- GCS_BUCKET_NAME');
      console.error('- FIREBASE_PROJECT_ID (will use {project-id}.appspot.com)');
      throw new Error('Firebase Storage bucket not configured');
    }
    
    console.log('Using storage bucket:', bucketName);
    
    // Check if storage is initialized properly
    if (!storage || !storage.bucket) {
      console.error('Firebase Storage Error: Storage not properly initialized');
      console.error('Make sure Firebase Admin SDK is initialized with proper credentials');
      throw new Error('Firebase Storage not initialized');
    }
    
    const bucket = storage.bucket(bucketName);
    const file = bucket.file(uniqueFilename);
    
    // Convert base64 to buffer
    const buffer = Buffer.from(base64, 'base64');
    
    // Create a write stream
    const stream = file.createWriteStream({
      metadata: {
        contentType: `image/${ext}`,
        metadata: {
          firebaseStorageDownloadTokens: uuidv4() // This makes the file publicly accessible with a token
        }
      },
      resumable: false
    });
    
    // Return a promise that resolves when upload is complete
    return new Promise((resolve, reject) => {
      stream.on('error', (error) => {
        console.error('Stream upload error:', error);
        console.error('Error details:', {
          code: error.code,
          message: error.message,
          statusCode: error.statusCode,
          bucketName: bucketName,
          filename: uniqueFilename
        });
        reject(error);
      });
      
      stream.on('finish', async () => {
        try {
          // Make the file public
          await file.makePublic();
          
          // Get the public URL - use firebasestorage.googleapis.com for new format
          const publicUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodeURIComponent(uniqueFilename)}?alt=media`;
          console.log('File uploaded successfully:', publicUrl);
          
          resolve(publicUrl);
        } catch (error) {
          console.error('Error making file public:', error);
          console.error('makePublic error details:', {
            code: error.code,
            message: error.message,
            statusCode: error.statusCode,
            bucketName: bucketName,
            filename: uniqueFilename
          });
          reject(error);
        }
      });
      
      // Write the buffer to the stream
      stream.end(buffer);
    });
  } catch (error) {
    console.error('Error uploading image:', error);
    throw error;
  }
};

// Delete image from Firebase Storage
const deleteImage = async (imageUrl) => {
  try {
    if (!imageUrl || (!imageUrl.includes('firebasestorage.googleapis.com') && !imageUrl.includes('storage.googleapis.com'))) {
      return; // Not a Firebase Storage URL
    }
    
    let filename;
    
    // Handle new Firebase Storage URL format
    if (imageUrl.includes('firebasestorage.googleapis.com')) {
      // Extract filename from URL like: https://firebasestorage.googleapis.com/v0/b/bucket/o/circles%2Ffilename.jpg?alt=media
      const match = imageUrl.match(/\/o\/(.+?)\?/);
      if (match) {
        filename = decodeURIComponent(match[1]);
      }
    } else if (imageUrl.includes('storage.googleapis.com')) {
      // Handle storage.googleapis.com format
      // Extract filename from URL like: https://storage.googleapis.com/bucket-name/path/to/file.jpg
      const match = imageUrl.match(/storage\.googleapis\.com\/[^\/]+\/(.+)$/);
      if (match) {
        filename = match[1];
      }
    }
    
    if (!filename) {
      console.error('Could not extract filename from URL:', imageUrl);
      return;
    }
    
    // Get storage bucket
    const storage = getStorage();
    const bucketName = process.env.FIREBASE_STORAGE_BUCKET || `${process.env.FIREBASE_PROJECT_ID}.appspot.com`;
    const bucket = storage.bucket(bucketName);
    const file = bucket.file(filename);
    
    // Delete the file
    await file.delete();
    console.log('File deleted successfully:', filename);
  } catch (error) {
    console.error('Error deleting image:', error);
    // Don't throw error for deletion failures - it's not critical
  }
};

module.exports = {
  uploadImage,
  deleteImage
};