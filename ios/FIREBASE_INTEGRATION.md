# Firebase Integration Guide for Circles iOS App

## Overview
This guide documents the Firebase integration for the Circles iOS app, including authentication setup and SwiftUI conversion.

## Current Architecture

### Hybrid Approach
The app now uses a hybrid authentication approach:
1. **Firebase Auth** - Handles all authentication providers (Google, Facebook, Apple, Email/Password)
2. **Backend API** - Syncs Firebase users with your custom backend for business logic

### Authentication Flow
1. User signs in with any provider using Firebase Auth
2. Firebase issues an ID token
3. App syncs with your backend using the Firebase ID token
4. Backend verifies the token and creates/updates user in your database
5. Backend returns JWT for API access

## Setup Instructions

### 1. Add Firebase SDK to Xcode Project

Open your project in Xcode and add Firebase:

1. Go to **File → Add Package Dependencies...**
2. Enter URL: `https://github.com/firebase/firebase-ios-sdk`
3. Version: Up to Next Major Version: **11.2.0**
4. Select these products:
   - ✅ FirebaseAnalytics
   - ✅ FirebaseAuth
   - ✅ FirebaseFirestore
   - ✅ FirebaseStorage

### 2. Verify Configuration Files

Ensure these files are properly configured:
- ✅ `GoogleService-Info.plist` - Already in project
- ✅ `Info.plist` - Contains URL schemes and OAuth client IDs
- ✅ `CirclesApp.swift` - Initializes Firebase on app launch

### 3. Authentication Providers

#### Google Sign-In
- Uses Firebase Google Auth Provider
- Client ID from `GoogleService-Info.plist`
- Handles authentication directly with Firebase

#### Facebook Login
- Uses Firebase Facebook Auth Provider
- Requires Facebook App ID in `Info.plist`
- OAuth handled by Facebook SDK

#### Apple Sign-In
- Uses Firebase Apple Auth Provider
- Requires Sign in with Apple capability
- Generates nonce for security

#### LinkedIn (Special Case)
- Not directly supported by Firebase
- Goes through your backend
- Backend can create Firebase custom tokens if needed

#### Email/Password
- Direct Firebase Auth implementation
- Includes email verification requirement
- Password strength validation

## Code Structure

### Key Files Modified

1. **CirclesApp.swift**
   - Initializes Firebase on app launch
   - Configures Google Sign-In with Firebase client ID

2. **AuthManager.swift**
   - Added Firebase Auth state listener
   - Syncs Firebase auth state with backend
   - Maintains backward compatibility

3. **FirebaseAuthManager.swift** (New)
   - Complete Firebase Auth implementation
   - Handles all authentication methods
   - Maps Firebase errors to app errors

4. **AuthService.swift**
   - Added Firebase token verification methods
   - `syncFirebaseUser()` - Syncs Firebase user with backend
   - `verifyFirebaseToken()` - Verifies Firebase ID tokens

## Backend Requirements

Your backend needs these endpoints:

### 1. Firebase User Sync
```
POST /auth/firebase/sync
Body: {
  "firebaseIdToken": "...",
  "uid": "firebase-uid",
  "email": "user@example.com",
  "displayName": "User Name",
  "photoURL": "https://..."
}
Response: {
  "success": true,
  "token": "jwt-token",
  "user": { ... }
}
```

### 2. Firebase Token Verification
```
POST /auth/firebase/verify
Body: {
  "firebaseIdToken": "..."
}
Response: {
  "success": true,
  "token": "jwt-token",
  "user": { ... }
}
```

## SwiftUI Migration

### Completed Components

✅ **Views Created:**
- All authentication views (Login, Register, Email Login)
- Main navigation (TabView, ContentView)
- Circles views (Home, Create, Detail, Edit)
- Places views (Add, Detail)
- Profile views (Profile, Edit)
- Discover view

✅ **Managers Created:**
- AuthManager (Firebase-integrated)
- CircleManager
- UserManager
- PlaceManager

✅ **Supporting Components:**
- NetworkMonitor
- UpdateChecker
- ImageCropperView wrapper

### Migration Strategy

1. **Gradual Migration**: SwiftUI views coexist with UIKit
2. **Shared Services**: Both UI frameworks use the same managers
3. **State Management**: Uses `@StateObject` and `@EnvironmentObject`
4. **Firebase Integration**: Fully integrated in SwiftUI version

## Testing Authentication

### Test Each Provider:
1. **Email/Password**
   - Register new account
   - Verify email sent
   - Login after verification

2. **Google Sign-In**
   - Sign in with Google account
   - Verify Firebase auth state
   - Check backend sync

3. **Facebook Login**
   - Login with Facebook
   - Verify permissions granted
   - Check user data sync

4. **Apple Sign-In**
   - Sign in with Apple ID
   - Test both email share/hide options
   - Verify name handling

5. **LinkedIn**
   - OAuth flow through Safari
   - Backend handles token exchange
   - Verify user creation

## Troubleshooting

### Common Issues:

1. **"No such module 'Firebase'"**
   - Add Firebase SDK via Xcode (see Setup Instructions)

2. **Google Sign-In not working**
   - Verify URL schemes in Info.plist
   - Check GoogleService-Info.plist is in project

3. **Facebook Login fails**
   - Verify Facebook App ID in Info.plist
   - Check Facebook app settings

4. **Backend sync fails**
   - Ensure backend has Firebase Admin SDK
   - Verify endpoints exist
   - Check network connectivity

## Next Steps

1. **Complete Firebase SDK Addition** in Xcode
2. **Test All Authentication Methods**
3. **Update Backend** to handle Firebase tokens
4. **Consider Adding**:
   - Firebase Analytics events
   - Firestore for real-time data
   - Firebase Storage for images
   - Push notifications via FCM

## Security Considerations

- Firebase ID tokens expire after 1 hour
- Backend should verify tokens on each request
- Store sensitive data in your backend, not Firebase
- Use Firebase Security Rules if using Firestore/Storage
- Enable App Check for additional security