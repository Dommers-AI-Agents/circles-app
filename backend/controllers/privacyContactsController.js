// backend/controllers/privacyContactsController.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const crypto = require('crypto');

const db = getFirestore();

/**
 * Privacy-preserving contact sync using hashed identifiers
 * Complies with Apple Guidelines 5.1.1 by not storing raw contact data
 */

// Helper function to hash a string using SHA256
const sha256Hash = (input) => {
  return crypto.createHash('sha256').update(input).digest('hex');
};

// Helper function to normalize email
const normalizeEmail = (email) => {
  if (!email) return null;
  
  let normalized = email.trim().toLowerCase();
  
  // Handle Gmail dot normalization
  if (normalized.includes('@gmail.com')) {
    const [username, domain] = normalized.split('@');
    const cleanUsername = username.replace(/\./g, '');
    normalized = `${cleanUsername}@${domain}`;
  }
  
  return normalized;
};

// Helper function to normalize phone numbers
const normalizePhoneNumber = (phone) => {
  if (!phone) return null;
  
  // Remove all non-numeric characters
  const cleaned = phone.replace(/\D/g, '');
  
  // Handle US numbers (assume US if 10 digits without country code)
  if (cleaned.length === 10) {
    return `+1${cleaned}`;
  }
  
  // Add + if missing for international numbers
  if (cleaned.length > 10 && !cleaned.startsWith('1')) {
    return `+${cleaned}`;
  }
  
  // If it starts with 1 and is 11 digits, add +
  if (cleaned.length === 11 && cleaned.startsWith('1')) {
    return `+${cleaned}`;
  }
  
  return cleaned;
};

// Privacy-preserving contact sync
const privacySyncContacts = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { hashedContacts, privacyMode } = req.body;
    
    if (!hashedContacts || !Array.isArray(hashedContacts)) {
      return res.status(400).json({
        success: false,
        message: 'Hashed contacts array is required'
      });
    }
    
    if (!privacyMode) {
      return res.status(400).json({
        success: false,
        message: 'Privacy mode must be enabled for this endpoint'
      });
    }

    console.log(`🔒 Privacy sync: Processing ${hashedContacts.length} hashed contacts for user ${userId}`);

    // Extract all hashed identifiers
    const allHashedEmails = new Set();
    const allHashedPhones = new Set();
    
    hashedContacts.forEach(contact => {
      if (contact.hashedEmails && Array.isArray(contact.hashedEmails)) {
        contact.hashedEmails.forEach(hash => allHashedEmails.add(hash));
      }
      if (contact.hashedPhoneNumbers && Array.isArray(contact.hashedPhoneNumbers)) {
        contact.hashedPhoneNumbers.forEach(hash => allHashedPhones.add(hash));
      }
    });

    console.log(`🔍 Searching for matches among ${allHashedEmails.size} email hashes and ${allHashedPhones.size} phone hashes`);

    // Get all users and hash their identifiers for matching
    const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
    const matchedUsers = [];
    const processedUserIds = new Set();

    // Process each user in the database
    for (const doc of usersSnapshot.docs) {
      if (doc.id === userId) continue; // Skip the requesting user
      
      const userData = doc.data();
      let isMatch = false;
      
      // Hash user's email and check for match
      if (userData.email) {
        const normalizedEmail = normalizeEmail(userData.email);
        const hashedEmail = sha256Hash(normalizedEmail);
        
        if (allHashedEmails.has(hashedEmail)) {
          isMatch = true;
        }
      }
      
      // Hash user's phone and check for match
      if (!isMatch && userData.phoneNumber) {
        const normalizedPhone = normalizePhoneNumber(userData.phoneNumber);
        if (normalizedPhone) {
          const hashedPhone = sha256Hash(normalizedPhone);
          
          if (allHashedPhones.has(hashedPhone)) {
            isMatch = true;
          }
        }
      }
      
      // If match found, add to results
      if (isMatch && !processedUserIds.has(doc.id)) {
        processedUserIds.add(doc.id);
        
        // Get user's circles count for the response
        const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
          .where('owner', '==', doc.id)
          .get();
        
        let totalPlaces = 0;
        let circlesCount = circlesSnapshot.size;
        
        circlesSnapshot.forEach(circleDoc => {
          const circle = circleDoc.data();
          totalPlaces += (circle.placesCount || 0);
        });
        
        matchedUsers.push({
          id: doc.id,
          email: userData.email,
          displayName: userData.displayName,
          profilePicture: userData.profilePicture,
          bio: userData.bio,
          phoneNumber: userData.phoneNumber,
          placesCount: totalPlaces,
          circlesCount: circlesCount,
          followersCount: userData.followersCount || 0,
          followingCount: userData.followingCount || 0,
          isVerified: userData.isVerified || false
        });
      }
    }

    // Get existing connections for context
    const [outgoingConnectionsQuery, incomingConnectionsQuery] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .get()
    ]);
    
    const existingConnections = new Map();
    const connectionDirections = new Map();
    
    // Process connections
    outgoingConnectionsQuery.forEach(doc => {
      const connection = doc.data();
      existingConnections.set(connection.connectedUserId, connection.status);
      connectionDirections.set(connection.connectedUserId, 'outgoing');
    });
    
    incomingConnectionsQuery.forEach(doc => {
      const connection = doc.data();
      if (!existingConnections.has(connection.userId)) {
        existingConnections.set(connection.userId, connection.status);
        connectionDirections.set(connection.userId, 'incoming');
      }
    });

    // Get current user's following list
    const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const currentUserData = currentUserDoc.data();
    const userFollowing = new Set(currentUserData.following || []);

    // Add connection status to matched users
    const usersWithConnectionStatus = matchedUsers.map(user => {
      const connectionStatus = existingConnections.get(user.id) || 'none';
      const connectionDirection = connectionDirections.get(user.id) || 'none';
      const isFollowing = userFollowing.has(user.id);
      
      return {
        ...user,
        connectionStatus,
        connectionDirection,
        isFollowing
      };
    });

    console.log(`✅ Privacy sync complete: Found ${matchedUsers.length} matches without exposing raw contact data`);

    // Log privacy-preserving sync for audit
    await db.collection('privacy_sync_logs').add({
      userId,
      timestamp: new Date(),
      hashedContactsCount: hashedContacts.length,
      matchedCount: matchedUsers.length,
      privacyMode: true,
      // Don't log any actual contact data or hashes
    });

    res.json({
      success: true,
      matchedUsers: usersWithConnectionStatus,
      totalContacts: hashedContacts.length,
      matchedCount: matchedUsers.length
    });

  } catch (error) {
    console.error('Error in privacy sync:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to sync contacts',
      error: error.message
    });
  }
};

// Get user's hashed identifiers (for client-side matching)
const getUserHashedIdentifiers = async (req, res) => {
  try {
    console.log('📋 Generating hashed user list for client-side matching');
    
    // Get all users with their hashed identifiers
    const usersSnapshot = await db.collection(COLLECTIONS.USERS).get();
    const hashedUsers = [];
    
    usersSnapshot.forEach(doc => {
      const userData = doc.data();
      const hashedIdentifiers = [];
      
      // Hash email if available
      if (userData.email) {
        const normalizedEmail = normalizeEmail(userData.email);
        hashedIdentifiers.push(sha256Hash(normalizedEmail));
      }
      
      // Hash phone if available
      if (userData.phoneNumber) {
        const normalizedPhone = normalizePhoneNumber(userData.phoneNumber);
        if (normalizedPhone) {
          hashedIdentifiers.push(sha256Hash(normalizedPhone));
        }
      }
      
      if (hashedIdentifiers.length > 0) {
        hashedUsers.push({
          userId: doc.id,
          hashes: hashedIdentifiers
        });
      }
    });
    
    console.log(`✅ Generated ${hashedUsers.length} hashed user entries for client-side matching`);
    
    res.json({
      success: true,
      hashedUsers,
      count: hashedUsers.length,
      timestamp: new Date()
    });
    
  } catch (error) {
    console.error('Error getting hashed identifiers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get hashed identifiers',
      error: error.message
    });
  }
};

// Delete synced contact data (for user privacy control)
const deleteSyncedData = async (req, res) => {
  try {
    const userId = req.user.uid;
    
    console.log(`🗑️ Deleting synced contact data for user ${userId}`);
    
    // Delete privacy sync logs for this user
    const logsSnapshot = await db.collection('privacy_sync_logs')
      .where('userId', '==', userId)
      .get();
    
    const batch = db.batch();
    logsSnapshot.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    await batch.commit();
    
    console.log(`✅ Deleted ${logsSnapshot.size} sync log entries for user ${userId}`);
    
    res.json({
      success: true,
      message: 'Synced contact data deleted successfully',
      deletedCount: logsSnapshot.size
    });
    
  } catch (error) {
    console.error('Error deleting synced data:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete synced data',
      error: error.message
    });
  }
};

module.exports = {
  privacySyncContacts,
  getUserHashedIdentifiers,
  deleteSyncedData
};