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
            phoneNumber: userData.phoneNumber,
            placesCount: 0, // Will be calculated later
            circlesCount: userData.circlesCount || 0,
            followersCount: userData.followersCount || 0,
            followingCount: userData.followingCount || 0,
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
            phoneNumber: userData.phoneNumber,
            placesCount: 0, // Will be calculated later
            circlesCount: userData.circlesCount || 0,
            followersCount: userData.followersCount || 0,
            followingCount: userData.followingCount || 0,
            isVerified: userData.isVerified || false
          });
        }
      });
    }

    // Get existing connections for the user (both directions)
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
    
    // Process outgoing connections
    outgoingConnectionsQuery.forEach(doc => {
      const connection = doc.data();
      existingConnections.set(connection.connectedUserId, connection.status);
      connectionDirections.set(connection.connectedUserId, 'outgoing');
    });
    
    // Process incoming connections
    incomingConnectionsQuery.forEach(doc => {
      const connection = doc.data();
      // If there's already an outgoing connection, keep that status
      if (!existingConnections.has(connection.userId)) {
        existingConnections.set(connection.userId, connection.status);
        connectionDirections.set(connection.userId, 'incoming');
      }
    });

    // Get current user's following list
    const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const currentUserData = currentUserDoc.data();
    const userFollowing = new Set(currentUserData.following || []);

    // Calculate actual places count for each matched user from their circles
    for (let user of matchedUsers) {
      const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', '==', user.id)
        .get();
      
      let totalPlaces = 0;
      let circlesCount = circlesSnapshot.size;
      
      circlesSnapshot.forEach(circleDoc => {
        const circle = circleDoc.data();
        totalPlaces += (circle.placesCount || 0);
      });
      
      // Update the user object with actual counts
      user.placesCount = totalPlaces;
      user.circlesCount = circlesCount;
    }

    // Add connection status and following info to matched users
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
// Core users who are always suggested first — the most content-rich accounts,
// so a brand-new user immediately has great places to discover
const CORE_SUGGESTED_EMAILS = [
  'sgroiwes@gmail.com',      // Wes
  'brittanyvans@gmail.com',  // Brittany
  'salasgroi@gmail.com'      // Sal
];

const getSuggestedUsers = async (req, res) => {
  try {
    const userId = req.user.uid;
    const limit = parseInt(req.query.limit) || 10;

    console.log(`🌟 Getting suggested users for user ${userId}, limit: ${limit}`);

    // Get users from database - we'll calculate and sort by place count later
    const usersQuery = await db.collection(COLLECTIONS.USERS)
      .limit(50) // Get more users to filter from
      .get();

    // Always include the core users, even if they fall outside the scan window
    const coreSnap = await db.collection(COLLECTIONS.USERS)
      .where('email', 'in', CORE_SUGGESTED_EMAILS)
      .get();
    const coreUserIds = new Set(coreSnap.docs.map(doc => doc.id));
    const candidateDocs = [
      ...coreSnap.docs,
      ...usersQuery.docs.filter(doc => !coreUserIds.has(doc.id))
    ];

    console.log(`📊 Found ${usersQuery.size} total users in database (+${coreSnap.size} core)`);
    
    // Get existing connections for the user — BOTH directions, and include
    // pending requests so we don't suggest people the user already reached out
    // to (or who reached out to them)
    const [connectionsQuery1, connectionsQuery2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', userId).get(),
      db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', userId).get()
    ]);

    const connectedUserIds = new Set();
    connectionsQuery1.forEach(doc => {
      const connection = doc.data();
      if (connection.status === 'accepted' || connection.status === 'pending') {
        connectedUserIds.add(connection.connectedUserId);
      }
    });
    connectionsQuery2.forEach(doc => {
      const connection = doc.data();
      if (connection.status === 'accepted' || connection.status === 'pending') {
        connectedUserIds.add(connection.userId);
      }
    });

    // Filter and format users
    let skippedNoPlaces = 0;
    let skippedConnected = 0;
    const userCandidates = [];
    
    // First pass: collect all eligible users
    for (const doc of candidateDocs) {
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
          _actualPlacesCount: totalPlaces, // For sorting
          _isCore: coreUserIds.has(doc.id) // Core users pin to the front
        });
      } else {
        console.log(`⏭️ Skipping user with 0 places: ${userData.displayName}`);
        skippedNoPlaces++;
      }
    }
    
    // Sort: core users first, then by actual places count; take the limit
    userCandidates.sort((a, b) => {
      if (a._isCore !== b._isCore) return a._isCore ? -1 : 1;
      return b._actualPlacesCount - a._actualPlacesCount;
    });
    const topUsers = userCandidates.slice(0, limit).map(user => {
      delete user._actualPlacesCount; // Remove sorting fields
      delete user._isCore;
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

    // Connect link: opens the app and auto-connects when installed,
    // otherwise redirects to the App Store (served by GET /connect/:userId)
    const inviteLink = `https://circles-backend-196924649787.us-central1.run.app/connect/${userId}`;

    // Send invitations
    for (const invite of invites) {
      try {
        if (invite.type === 'email' && invite.email) {
          // Send email invitation
          await emailService.sendAppInvitation(
            invite.email,
            inviterName,
            invite.contactName,
            inviteLink
          );
          results.sent.push({ type: 'email', recipient: invite.email });

        } else if (invite.type === 'sms' && invite.phoneNumber) {
          // For SMS, we'll return the formatted message and let the client handle it
          // since SMS sending requires additional setup (Twilio, etc.)
          const message = `${inviterName} invited you to join Circles - the app for sharing your favorite places! Join and connect with me: ${inviteLink}`;
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