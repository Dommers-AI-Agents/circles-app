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
    // Get the bucket name from environment or use default
    const bucketName = process.env.FIREBASE_STORAGE_BUCKET || `${process.env.FIREBASE_PROJECT_ID}.appspot.com`;
    console.log('Using storage bucket:', bucketName);
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
        console.error('Upload error:', error);
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
    } else {
      // Handle old format
      const urlParts = imageUrl.split('/');
      filename = `circles/${urlParts[urlParts.length - 1]}`;
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