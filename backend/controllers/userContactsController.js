// backend/controllers/userContactsController.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const emailService = require('../services/emailService');

const db = getFirestore();

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
  if (cleaned.length > 10 && !cleaned.startsWith('+')) {
    return `+${cleaned}`;
  }
  return cleaned;
};

// Sync user's contacts with existing Circles users
const syncContacts = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { contacts } = req.body;
    
    if (!contacts || !Array.isArray(contacts)) {
      return res.status(400).json({
        success: false,
        message: 'Contacts array is required'
      });
    }

    console.log(`📱 Syncing ${contacts.length} contacts for user ${userId}`);

    // Extract all emails and phone numbers from contacts
    const emails = [];
    const phoneNumbers = [];
    
    contacts.forEach(contact => {
      if (contact.emails && Array.isArray(contact.emails)) {
        emails.push(...contact.emails.map(e => e.toLowerCase()));
      }
      if (contact.phoneNumbers && Array.isArray(contact.phoneNumbers)) {
        phoneNumbers.push(...contact.phoneNumbers.map(p => normalizePhoneNumber(p)).filter(Boolean));
      }
    });

    // Remove duplicates
    const uniqueEmails = [...new Set(emails)];
    const uniquePhoneNumbers = [...new Set(phoneNumbers)];

    console.log(`📧 Found ${uniqueEmails.length} unique emails and ${uniquePhoneNumbers.length} unique phone numbers`);

    // Query for users with matching emails or phone numbers
    const matchedUsers = [];
    const processedUserIds = new Set();

    // Query by emails (Firestore doesn't support 'in' with more than 30 items)
    const emailChunks = [];
    for (let i = 0; i < uniqueEmails.length; i += 30) {
      emailChunks.push(uniqueEmails.slice(i, i + 30));
    }

    for (const chunk of emailChunks) {
      const emailQuery = await db.collection(COLLECTIONS.USERS)
        .where('email', 'in', chunk)
        .get();
      
      emailQuery.forEach(doc => {
        if (doc.id !== userId && !processedUserIds.has(doc.id)) {
          processedUserIds.add(doc.id);
          const userData = doc.data();
          matchedUsers.push({
            id: doc.id,
            email: userData.email,
            displayName: userData.displayName,
            profilePicture: userData.profilePicture,
            bio: userData.bio,
            placesCount: userData.placesCount || 0,
            circlesCount: userData.circlesCount || 0,
            isVerified: userData.isVerified || false
          });
        }
      });
    }

    // Query by phone numbers
    const phoneChunks = [];
    for (let i = 0; i < uniquePhoneNumbers.length; i += 30) {
      phoneChunks.push(uniquePhoneNumbers.slice(i, i + 30));
    }

    for (const chunk of phoneChunks) {
      const phoneQuery = await db.collection(COLLECTIONS.USERS)
        .where('phoneNumber', 'in', chunk)
        .get();
      
      phoneQuery.forEach(doc => {
        if (doc.id !== userId && !processedUserIds.has(doc.id)) {
          processedUserIds.add(doc.id);
          const userData = doc.data();
          matchedUsers.push({
            id: doc.id,
            email: userData.email,
            displayName: userData.displayName,
            profilePicture: userData.profilePicture,
            bio: userData.bio,
            placesCount: userData.placesCount || 0,
            circlesCount: userData.circlesCount || 0,
            isVerified: userData.isVerified || false
          });
        }
      });
    }

    // Get existing connections for the user
    const connectionsQuery = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .get();
    
    const existingConnections = new Map();
    connectionsQuery.forEach(doc => {
      const connection = doc.data();
      existingConnections.set(connection.connectedUserId, connection.status);
    });

    // Add connection status to matched users
    const usersWithConnectionStatus = matchedUsers.map(user => ({
      ...user,
      connectionStatus: existingConnections.get(user.id) || 'none'
    }));

    console.log(`✅ Found ${matchedUsers.length} Circles users from contacts`);

    res.json({
      success: true,
      matchedUsers: usersWithConnectionStatus,
      totalContacts: contacts.length,
      matchedCount: matchedUsers.length
    });

  } catch (error) {
    console.error('Error syncing contacts:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to sync contacts',
      error: error.message
    });
  }
};

// Get suggested users (users with most places saved)
const getSuggestedUsers = async (req, res) => {
  try {
    const userId = req.user.uid;
    const limit = parseInt(req.query.limit) || 10;

    console.log(`🌟 Getting suggested users for user ${userId}, limit: ${limit}`);

    // Get all users first (since placesCount field might not exist)
    // We'll calculate actual places from their circles
    const usersQuery = await db.collection(COLLECTIONS.USERS)
      .limit(100) // Get more users to filter from
      .get();
    
    console.log(`📊 Found ${usersQuery.size} total users in database`);
    
    // Get existing connections for the user
    const connectionsQuery = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .get();
    
    const connectedUserIds = new Set();
    connectionsQuery.forEach(doc => {
      const connection = doc.data();
      if (connection.status === 'accepted') {
        connectedUserIds.add(connection.connectedUserId);
      }
    });

    // Filter and format users
    let skippedNoPlaces = 0;
    let skippedConnected = 0;
    const userCandidates = [];
    
    // First pass: collect all eligible users
    for (const doc of usersQuery.docs) {
      const userData = doc.data();
      
      if (doc.id === userId) {
        console.log(`⏭️ Skipping current user`);
        continue;
      }
      
      if (connectedUserIds.has(doc.id)) {
        console.log(`⏭️ Skipping already connected user: ${userData.displayName}`);
        skippedConnected++;
        continue;
      }
      
      // Get actual places count from circles
      const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', doc.id)
        .get();
      
      let totalPlaces = 0;
      let circlesCount = circlesSnapshot.size;
      
      circlesSnapshot.forEach(circleDoc => {
        const circle = circleDoc.data();
        totalPlaces += (circle.placesCount || 0);
      });
      
      // Only include users with at least 1 place
      if (totalPlaces > 0) {
        console.log(`✅ Found user: ${userData.displayName} (${totalPlaces} places across ${circlesCount} circles)`);
        userCandidates.push({
          id: doc.id,
          email: userData.email,
          displayName: userData.displayName,
          profilePicture: userData.profilePicture,
          bio: userData.bio,
          placesCount: totalPlaces, // Use actual count from circles
          circlesCount: circlesCount,
          followersCount: userData.followersCount || 0,
          connectionsCount: userData.connectionsCount || 0,
          isVerified: userData.isVerified || false,
          _actualPlacesCount: totalPlaces // For sorting
        });
      } else {
        console.log(`⏭️ Skipping user with 0 places: ${userData.displayName}`);
        skippedNoPlaces++;
      }
    }
    
    // Sort by actual places count and take the limit
    userCandidates.sort((a, b) => b._actualPlacesCount - a._actualPlacesCount);
    const topUsers = userCandidates.slice(0, limit).map(user => {
      delete user._actualPlacesCount; // Remove sorting field
      return user;
    });

    console.log(`✅ Found ${topUsers.length} suggested users`);
    console.log(`📊 Skipped: ${skippedConnected} connected, ${skippedNoPlaces} with no places`);

    res.json({
      success: true,
      suggestedUsers: topUsers,
      count: topUsers.length
    });

  } catch (error) {
    console.error('Error getting suggested users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get suggested users',
      error: error.message
    });
  }
};

// Send invitations to non-users
const inviteContacts = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { invites } = req.body;
    
    if (!invites || !Array.isArray(invites)) {
      return res.status(400).json({
        success: false,
        message: 'Invites array is required'
      });
    }

    // Get inviting user's info
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const invitingUser = userDoc.data();
    const inviterName = invitingUser.displayName || 'A friend';

    console.log(`📨 Sending ${invites.length} invitations from ${inviterName}`);

    const results = {
      sent: [],
      failed: []
    };

    // Send invitations
    for (const invite of invites) {
      try {
        if (invite.type === 'email' && invite.email) {
          // Send email invitation
          await emailService.sendAppInvitation(
            invite.email,
            inviterName,
            invite.contactName
          );
          results.sent.push({ type: 'email', recipient: invite.email });
          
        } else if (invite.type === 'sms' && invite.phoneNumber) {
          // For SMS, we'll return the formatted message and let the client handle it
          // since SMS sending requires additional setup (Twilio, etc.)
          const message = `${inviterName} invited you to join Circles - the app for sharing your favorite places! Download: https://circles-app.com/download`;
          results.sent.push({ 
            type: 'sms', 
            recipient: invite.phoneNumber,
            message: message,
            clientSend: true // Flag to indicate client should send via native SMS
          });
        }
      } catch (error) {
        console.error(`Failed to send invite to ${invite.email || invite.phoneNumber}:`, error);
        results.failed.push({
          recipient: invite.email || invite.phoneNumber,
          error: error.message
        });
      }
    }

    console.log(`✅ Sent ${results.sent.length} invitations, ${results.failed.length} failed`);

    res.json({
      success: true,
      results,
      sentCount: results.sent.length,
      failedCount: results.failed.length
    });

  } catch (error) {
    console.error('Error sending invitations:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send invitations',
      error: error.message
    });
  }
};

module.exports = {
  syncContacts,
  getSuggestedUsers,
  inviteContacts
};