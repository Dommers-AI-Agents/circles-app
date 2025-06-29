// backend/config/firebase.js
const admin = require('firebase-admin');
const path = require('path');

// Initialize Firebase Admin SDK
const initializeFirebase = () => {
  try {
    // Check if Firebase is already initialized
    if (admin.apps.length > 0) {
      console.log('🔥 Firebase already initialized');
      return true;
    }

    if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
      // Production: Use service account from environment variable
      const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_KEY);
      
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        projectId: process.env.FIREBASE_PROJECT_ID,
        storageBucket: process.env.FIREBASE_STORAGE_BUCKET
      });
    } else if (process.env.NODE_ENV === 'production') {
      // Production: Use default Google Cloud credentials
      admin.initializeApp({
        projectId: process.env.FIREBASE_PROJECT_ID,
        storageBucket: process.env.FIREBASE_STORAGE_BUCKET
      });
    } else {
      // Development: Try service account file first, then use mock
      const serviceAccountPath = path.join(__dirname, 'firebase-service-account.json');
      
      try {
        const serviceAccount = require(serviceAccountPath);
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount),
          projectId: serviceAccount.project_id,
          storageBucket: process.env.FIREBASE_STORAGE_BUCKET || `${serviceAccount.project_id}.appspot.com`
        });
        console.log('🔥 Firebase initialized with service account');
      } catch (error) {
        console.log('⚠️  Firebase service account file not found. Using mock auth for development');
        console.log('   To use real Firebase:');
        console.log('   1. Download service account key from Firebase Console');
        console.log('   2. Save as backend/config/firebase-service-account.json');
        
        // Return mock Firebase for development
        return initializeMockFirebase();
      }
    }

    console.log('🔥 Firebase Admin SDK initialized successfully');
    return true;
  } catch (error) {
    console.error('❌ Firebase initialization failed:', error.message);
    return initializeMockFirebase();
  }
};

// Mock Firebase for development when no credentials are available
const initializeMockFirebase = () => {
  console.log('🔧 Using mock Firebase for development');
  
  global.mockFirebase = {
    firestore: () => ({
      collection: (name) => ({
        doc: (id) => ({
          id,
          get: () => Promise.resolve({ exists: false, data: () => null }),
          set: (data) => Promise.resolve(),
          update: (data) => Promise.resolve(),
          delete: () => Promise.resolve()
        }),
        add: (data) => Promise.resolve({ id: 'mock-' + Date.now() }),
        where: () => ({
          get: () => Promise.resolve({ docs: [] })
        }),
        orderBy: () => ({
          get: () => Promise.resolve({ docs: [] })
        }),
        get: () => Promise.resolve({ docs: [] })
      })
    }),
    auth: () => ({
      verifyIdToken: async (token) => {
        try {
          const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString());
          return {
            uid: payload.sub || 'mock-user-' + Date.now(),
            email: payload.email || 'mock@example.com',
            name: payload.name || 'Mock User',
            picture: payload.picture
          };
        } catch (error) {
          return {
            uid: 'mock-user-' + Date.now(),
            email: 'mock@example.com',
            name: 'Mock User'
          };
        }
      }
    }),
    storage: () => ({
      bucket: () => ({
        file: (name) => ({
          createWriteStream: () => ({
            on: (event, callback) => {
              if (event === 'finish') {
                setTimeout(() => callback(), 100);
              }
            },
            end: () => {}
          }),
          makePublic: () => Promise.resolve(),
          getSignedUrl: () => Promise.resolve([`https://mock-storage.com/${name}`])
        })
      })
    })
  };
  
  return true;
};

// Get Firestore instance
const getFirestore = () => {
  if (global.mockFirebase) {
    return global.mockFirebase.firestore();
  }
  return admin.firestore();
};

// Get Firebase Storage instance
const getStorage = () => {
  if (global.mockFirebase) {
    return global.mockFirebase.storage();
  }
  return admin.storage();
};

// Get Firebase Auth instance
const getAuth = () => {
  if (global.mockFirebase) {
    return global.mockFirebase.auth();
  }
  return admin.auth();
};

// Get Firebase Messaging instance
const getMessaging = () => {
  if (global.mockFirebase) {
    return {
      sendMulticast: async (message) => {
        console.log('🔔 Mock: Would send notification to', message.tokens?.length || 0, 'devices');
        return {
          successCount: message.tokens?.length || 0,
          failureCount: 0,
          responses: message.tokens?.map(() => ({ success: true })) || []
        };
      }
    };
  }
  return admin.messaging();
};

module.exports = {
  initializeFirebase,
  getFirestore,
  getStorage,
  getAuth,
  getMessaging,
  admin: global.mockFirebase ? null : admin
};