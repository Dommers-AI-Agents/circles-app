# CLAUDE.md - AI Assistant Knowledge Base for Circles App

This comprehensive guide contains essential context, architecture details, and implementation patterns for AI assistants working on the Circles app. Last updated: January 2025.

## Table of Contents
1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Tech Stack](#tech-stack)
4. [Project Structure](#project-structure)
5. [Backend Details](#backend-details)
6. [iOS Frontend Details](#ios-frontend-details)
7. [Database Schema](#database-schema)
8. [Authentication Flow](#authentication-flow)
9. [API Endpoints](#api-endpoints)
10. [Known Issues & Solutions](#known-issues--solutions)
11. [Recent Feature Implementations](#recent-feature-implementations)
12. [Deployment Guide](#deployment-guide)
13. [Development Workflow](#development-workflow)
14. [Code Style Guidelines](#code-style-guidelines)
15. [Testing Strategy](#testing-strategy)
16. [Troubleshooting Guide](#troubleshooting-guide)

## Project Overview

Circles is a social recommendation platform where users can:
- Create "circles" (curated collections) of their favorite places
- Share circles with their network connections
- Connect with other users and view their shared circles
- Like and comment on places within circles
- Send messages and place suggestions to connections
- Set privacy levels for circles (public, my network, private)

### Key Concepts
- **Circle**: A collection of places (restaurants, shops, etc.) curated by a user
- **Place**: A location with details from Google Places API plus user notes
- **Connection**: A bidirectional relationship between two users
- **Suggestion**: A place recommendation sent from one user to another
- **Privacy Levels**: Public (anyone), My Network (connections only), Private (owner only)

## Architecture

The app follows a client-server architecture:
- **Backend**: RESTful API built with Node.js/Express
- **Database**: Firebase Firestore (NoSQL)
- **Authentication**: Firebase Auth + JWT tokens
- **Storage**: Firebase Storage (images) + Google Cloud Storage
- **iOS App**: Native Swift/UIKit (not SwiftUI)
- **Deployment**: Google Cloud Run (containerized)

## Tech Stack

### Backend
- **Runtime**: Node.js 18+
- **Framework**: Express.js
- **Database**: Firebase Firestore
- **Authentication**: Firebase Auth + JWT
- **File Storage**: Firebase Storage, Google Cloud Storage
- **Email**: Nodemailer with Gmail SMTP
- **External APIs**: Apple Maps API (primary), Google Places API (photos only)
- **Dependencies**: See `/backend/package.json`

### iOS Frontend
- **Language**: Swift 5
- **UI Framework**: UIKit (NOT SwiftUI)
- **Architecture**: MVC with Service/Manager pattern
- **Networking**: URLSession with custom APIService
- **Image Loading**: Custom ImageService with caching
- **Authentication**: Firebase SDK + custom AuthService
- **Push Notifications**: Firebase Cloud Messaging

## Project Structure

```
circles-app/
├── backend/
│   ├── config/
│   │   ├── firebase.js         # Firebase initialization
│   │   └── database.js         # Database config
│   ├── controllers/
│   │   ├── firebaseAuthController.js    # Auth endpoints
│   │   ├── firebaseUserController.js    # User management
│   │   ├── firebaseCircleController.js  # Circle CRUD
│   │   ├── firebasePlaceController.js   # Place management
│   │   ├── connectionController.js      # User connections
│   │   ├── messagingController.js       # Messages/chat
│   │   └── suggestionController.js      # Place suggestions
│   ├── middleware/
│   │   ├── firebaseAuth.js     # JWT/Firebase auth middleware
│   │   └── errorHandler.js     # Global error handling
│   ├── models/
│   │   └── FirestoreModels.js  # Data models/schemas
│   ├── routes/
│   │   └── [feature]Routes.js  # Route definitions
│   ├── services/
│   │   ├── notificationService.js  # Push notifications
│   │   ├── emailService.js         # Email sending
│   │   └── googlePlacesService.js  # Google Places integration
│   ├── server.js               # Express app entry point
│   └── package.json
│
├── ios/
│   └── Circles-iOS-UIKit/
│       ├── Controllers/        # View Controllers
│       ├── Models/            # Data models
│       ├── Services/          # API/business logic
│       ├── Managers/          # Singleton managers
│       ├── Views/             # Custom UI components
│       └── Utilities/         # Helpers/extensions
│
├── CLAUDE.md                  # This file
├── TECH_DEBT.md              # Technical debt documentation
└── README.md                 # Basic project info
```

## Backend Details

### Key Controllers

1. **firebaseAuthController.js**
   - Handles login, registration, social auth
   - JWT token generation and refresh
   - Email verification

2. **firebaseUserController.js**
   - User profile CRUD
   - User search functionality
   - Preference management

3. **firebaseCircleController.js**
   - Circle creation, update, deletion
   - Circle sharing and privacy
   - Circle ordering

4. **firebasePlaceController.js**
   - Place CRUD within circles
   - Google Places integration
   - Like/comment functionality

5. **connectionController.js**
   - Connection requests (send, accept, decline)
   - Connection status management
   - Bidirectional connection queries

### Important Middleware

- **firebaseAuth.js**: Verifies JWT tokens, extracts user info, handles ID normalization
- **errorHandler.js**: Consistent error response formatting

### Services

- **notificationService.js**: Sends push notifications via FCM
- **emailService.js**: Email notifications using Gmail SMTP
- **googlePlacesService.js**: Fetches place details and photos

## iOS Frontend Details

### Architecture Patterns

1. **Service Layer Pattern**
   ```swift
   // Services are singletons that handle API calls
   UserService.shared.searchUsers(query: "john") { result in
       switch result {
       case .success(let users):
           // Handle users
       case .failure(let error):
           // Handle error
       }
   }
   ```

2. **Manager Pattern**
   ```swift
   // Managers handle business logic and state
   NetworkManager.shared.connections // Current user's connections
   CircleManager.shared.circles      // Current user's circles
   ```

3. **Delegate Pattern**
   ```swift
   // Used extensively for UI callbacks
   protocol CircleDetailDelegate: AnyObject {
       func circleDidUpdate(_ circle: Circle)
   }
   ```

### Key View Controllers

1. **CirclesHomeViewController**
   - Main screen with map/list toggle
   - Shows user's circles and places
   - Handles quick access (home/work)
   - Search functionality

2. **MyNetworkViewController**
   - Manages connections and shared circles
   - User search with real-time filtering
   - Connection request handling

3. **CircleDetailViewController**
   - Shows places within a circle
   - Handles place management
   - Circle sharing functionality

4. **ConnectionDetailViewController**
   - Shows a connection's shared circles
   - Access to their places
   - Activity tracking

### Custom UI Components

- **CircleCell**: Table view cell for circles
- **PlaceDetailView**: Detailed place information
- **ConnectionRequestMessageCell**: Special message cell for requests
- **HorizontalUserListView**: Scrollable user avatars

### Important Services

1. **APIService**: Central networking layer
2. **AuthService**: Authentication management
3. **ImageService**: Image downloading and caching
4. **NotificationService**: Push notification handling
5. **KeychainService**: Secure token storage

## Database Schema

### Firestore Collections

1. **users**
   ```javascript
   {
     _id: "userId",
     email: "user@example.com",
     displayName: "John Doe",
     profilePicture: "https://...",
     bio: "Travel enthusiast",
     location: "San Francisco, CA",
     preferences: {
       defaultHomeView: "map" // or "list"
     },
     createdAt: Timestamp
   }
   ```

2. **circles**
   ```javascript
   {
     _id: "circleId",
     name: "Favorite Restaurants",
     description: "My top dining spots",
     owner: "userId",
     privacy: "myNetwork", // "public", "private"
     sharedWith: ["userId1", "userId2"],
     places: ["placeId1", "placeId2"],
     createdAt: Timestamp,
     updatedAt: Timestamp
   }
   ```

3. **places**
   ```javascript
   {
     _id: "placeId",
     googlePlaceId: "ChIJ...",
     name: "Restaurant Name",
     address: "123 Main St",
     circleId: "circleId",
     userId: "ownerId",
     userNotes: "Great pasta!",
     category: "restaurant",
     likes: ["userId1", "userId2"],
     likesCount: 2,
     location: {
       lat: 37.7749,
       lng: -122.4194
     },
     photos: ["photoUrl1", "photoUrl2"],
     createdAt: Timestamp
   }
   ```

4. **connections**
   ```javascript
   {
     _id: "connectionId",
     userId: "userId1",
     connectedUserId: "userId2",
     status: "accepted", // "pending", "declined"
     createdAt: Timestamp,
     acceptedAt: Timestamp
   }
   ```

5. **messages**
   ```javascript
   {
     _id: "messageId",
     conversationId: "conversationId",
     senderId: "userId",
     content: "Check out this place!",
     type: "text", // "suggestion", "connection_request"
     suggestionData: { /* place details */ },
     timestamp: Timestamp,
     read: false
   }
   ```

## Authentication Flow

1. **Initial Login/Registration**
   - User provides credentials (email/password or social)
   - Backend validates with Firebase Auth
   - JWT token generated with user ID
   - Token stored in iOS Keychain
   - User data cached locally

2. **Token Management**
   - Access token expires in 30 days
   - Refresh token used to get new access token
   - iOS checks token validity before API calls
   - Auto-refresh if token expires soon

3. **Social Authentication**
   - Google Sign-In via Firebase
   - Apple Sign-In with JWT validation
   - LinkedIn OAuth (custom implementation)
   - Facebook Login (Firebase)

## API Endpoints

### Authentication
- `POST /api/auth/register` - New user registration
- `POST /api/auth/login` - Email/password login
- `POST /api/auth/firebase` - Social auth (Google, Apple, Facebook)
- `POST /api/auth/linkedin` - LinkedIn OAuth
- `POST /api/auth/refresh-token` - Refresh JWT token
- `POST /api/auth/logout` - Logout and invalidate token

### Users
- `GET /api/users/search?q={query}` - Search users
- `GET /api/users/:userId` - Get user profile
- `PUT /api/users/:userId` - Update user profile
- `PUT /api/users/preferences` - Update user preferences

### Circles
- `GET /api/circles` - Get user's circles
- `GET /api/circles/:circleId` - Get circle details
- `POST /api/circles` - Create new circle
- `PUT /api/circles/:circleId` - Update circle
- `DELETE /api/circles/:circleId` - Delete circle
- `PUT /api/circles/reorder` - Reorder circles
- `POST /api/circles/:circleId/track-view` - Track circle view (for activity tracking)

### Places
- `GET /api/circles/:circleId/places` - Get places in circle
- `POST /api/circles/:circleId/places` - Add place to circle
- `PUT /api/places/:placeId` - Update place
- `DELETE /api/places/:placeId` - Remove place
- `POST /api/places/:placeId/like` - Like/unlike place
- `GET /api/places/:placeId/comments` - Get place comments
- `POST /api/places/:placeId/comment` - Add comment
- `POST /api/places/:placeId/track-view` - Track place view (for activity tracking)

### Connections
- `GET /api/connections` - Get user's connections
- `POST /api/connections/request` - Send connection request
- `PUT /api/connections/:connectionId/accept` - Accept request
- `PUT /api/connections/:connectionId/decline` - Decline request
- `GET /api/users/network-circles` - Get network's shared circles

### Messages
- `GET /api/conversations` - Get all conversations
- `GET /api/conversations/:conversationId/messages` - Get messages
- `POST /api/messages` - Send message
- `PUT /api/messages/:messageId/read` - Mark as read

## Known Issues & Solutions

### 1. Complex User ID Format
**Issue**: System handles two ID formats
- Simple: `9b5eeac93282416c9bc6dcecbc49b40f`
- Complex: `000454.9b5eeac93282416c9bc6dcecbc49b40f.2127`

**Current Solution**: Always check both formats
```javascript
// Backend
const simpleUserId = currentUserId.includes('.') 
  ? currentUserId.split('.')[1] 
  : currentUserId;

if (user.id === currentUserId || user.id === simpleUserId) {
  // Handle user
}
```

**Future**: See migration plan in TECH_DEBT.md

### 2. Connection Status Inconsistency
**Issue**: Status can be "accepted" or "connected"
**Solution**: Check for both values
```swift
switch user.connectionStatus {
case "connected", "accepted":
    // User is connected
}
```

### 3. JWT Secret Missing
**Issue**: "secretOrPrivateKey must have a value"
**Solution**: Add to Cloud Run environment
```bash
gcloud run services update circles-backend \
  --update-env-vars JWT_SECRET=your-secret-key
```

### 4. List/Map Button
**Issue**: Button shows current view instead of destination
**Solution**: In CirclesHomeViewController.swift
```swift
// Show destination view, not current view
let title = isShowingMap ? "List" : "Map"
```

### 5. Activity Tracking Red Dots (Fixed January 2025)
**Issue**: Red dots showed for any activity within 7 days, not since last login
**Solution**: Track lastLogin timestamp and calculate hasRecentPlace dynamically
```javascript
// Now uses lastLogin instead of hardcoded 7 days
hasRecentPlace = recentActivity.some(activity => 
  activity.type === 'place' && 
  new Date(activity.createdAt) > lastLoginDate
);
```
**See**: Activity Tracking System implementation above

## Recent Feature Implementations

### 1. Network Circle Visibility (December 2024)
**Problem**: Users couldn't see "My Network" privacy circles from connections
**Solution**: Added bidirectional connection checks in getPlacesByCircleId
```javascript
// Check both directions for connections
const connection1 = await db.collection('connections')
  .where('userId', '==', req.user.uid)
  .where('connectedUserId', '==', circle.owner)
  .where('status', '==', 'accepted')
  .get();
```

### 2. Like/Comment System (December 2024)
**Implementation**:
- Added likes array to Place model
- Created like/unlike endpoint with toggle logic
- Added comment endpoints
- Push notifications for likes
- iOS UI updates with heart button

### 3. User Search & Connection Requests (December 2024)
**Features**:
- Real-time search filtering
- Connection request in message inbox
- Email notifications via Gmail SMTP
- Cancel pending requests
- Custom message cells for requests

### 4. Email Notifications (December 2024)
**Setup**:
```javascript
// Gmail SMTP configuration
transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD
  }
});
```

### 5. Efficient Places Count with placesCount Field (July 2025)
**Problem**: Profile page showed 0 places despite users having many places. Counting places by fetching all data was inefficient for scalability.
**Solution**: Added `placesCount` field to circles for O(1) counting
```javascript
// Backend: Added to Circle model
placesCount: circleData.placesCount || 0, // Count of places for efficient display

// Increment when adding places
await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update({
    places: [place.id, ...currentPlaces],
    placesCount: (circle.placesCount || 0) + 1,
    updatedAt: new Date().toISOString()
});
```
**Migration**: Run `node scripts/migrate_places_count.js` to populate existing data

### 6. Instagram-style Profile Page UI (July 2025)
**Implementation**:
- 3-column grid for circles (like Instagram posts)
- Square cells with overlay text
- Stats bar showing Circles, Places, Connections
- Floating add button with shadow
- Removed section headers for cleaner look
- Combined full name with bio text
**Note**: Fixed duplicate API call issue - APIService blocks duplicate GET requests

### 7. Activity Tracking System for New Places (January 2025)
**Problem**: Red dots incorrectly showed for any place added within 7 days, not just since last login. Red dots didn't clear when navigating through the hierarchy.
**Solution**: Comprehensive activity tracking with lastLogin-based detection and hierarchical clearing

#### Backend Implementation:
1. **Last Login Tracking**:
```javascript
// In firebaseAuthController.js - tracks when user logs in
const now = new Date().toISOString();
await userRef.update({
  lastLogin: now,
  updatedAt: now
});
```

2. **Enhanced Activity Tracking**:
```javascript
// In activityService.js - tracks place with context
const activity = {
  type: 'place',
  entityId: placeId,
  circleId: circleId,
  placeName: placeName || 'Unknown Place',
  circleName: circleName || 'Unknown Circle',
  createdAt: new Date().toISOString(),
  viewedAt: null // Tracks when viewed
};
```

3. **Dynamic hasRecentPlace Calculation**:
```javascript
// In connectionController.js - uses lastLogin instead of 7 days
const lastLoginDate = new Date(lastLogin);
hasRecentPlace = connectionData.recentActivity?.some(activity => 
  activity.type === 'place' && 
  new Date(activity.createdAt) > lastLoginDate
) || false;
```

4. **Circle-level New Place Indicators**:
```javascript
// In circleSharingController.js - adds hasNewPlaces to circles
circle.hasNewPlaces = newPlacesByCircle.has(circle._id);
circle.newPlacesCount = newPlacesByCircle.get(circle._id)?.length || 0;
```

#### New API Endpoints:
- `POST /api/circles/:id/track-view` - Track when a circle with new places is viewed
  - Body: `{ connectionUserId: "userId" }`
  - Marks activities in that circle as viewed
- `POST /api/places/:id/track-view` - Track when a specific place is viewed
  - Body: `{ connectionUserId: "userId" }`
  - Marks that place activity as viewed

#### iOS Implementation:
1. **Circle Model Updates**:
```swift
// Added to Circle model
var hasNewPlaces: Bool? // Indicates if circle has new places since last login
var newPlacesCount: Int? // Number of new places since last login
```

2. **Red Dot UI Components**:
- **CircleCell**: Shows red dot when `hasNewPlaces == true`
- **PlaceTableViewCell**: Shows red dot and "NEW" badge when `isNew == true`

3. **Navigation Flow**:
```swift
// HorizontalUserListView - Connection click
NetworkManager.shared.trackConnectionView(connectionId: connection.id)

// UserCirclesViewController - Circle click
if circle.hasNewPlaces == true {
    trackCircleView(circleId: circle.id)
}

// Tracks view and clears circle-level activity
APIService.shared.request(
    endpoint: "circles/\(circleId)/track-view",
    method: .post,
    body: ["connectionUserId": userId]
)
```

#### Activity Flow:
1. User A adds a new place to a circle
2. User B (connected to A) logs in and sees:
   - Red dot on User A's connection icon (hasRecentPlace = true)
   - Clicking the connection → navigates to UserCirclesViewController
   - Red dot on circles containing new places (hasNewPlaces = true)
   - Clicking a circle → tracks view and navigates to CircleDetailViewController
   - New places show with red dots and "NEW" badges (isNew = true)
3. Activity clears progressively as user navigates deeper

#### Migration Notes:
- Existing connections will show no activity until users log in (lastLogin populated)
- Activity older than 30 days is automatically cleaned up
- recentActivity array stores all activity types (circles, places)

## Deployment Guide

### Backend Deployment to Google Cloud Run

1. **Build and push Docker image**:
```bash
cd backend
gcloud builds submit --tag gcr.io/circles-backend/circles-api
```

2. **Deploy to Cloud Run**:
```bash
gcloud run deploy circles-backend \
  --image gcr.io/circles-backend/circles-api \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

3. **Update environment variables**:

**⚠️ CRITICAL: EXISTING ENVIRONMENT VARIABLES (January 2025) ⚠️**
```bash
# DO NOT DELETE THESE - they are currently set in production:
# - EMAIL_USER='noreply@circles-app.com'
# - APP_URL='https://circles-app.com'  
# - GMAIL_USER='circles.app.notifications@gmail.com'
# - GMAIL_APP_PASSWORD=[app-specific password]
# - JWT_SECRET=[secret key for JWT tokens]
# - JWT_EXPIRE='30d'
# - FIREBASE_PROJECT_ID='circles-app-83b67'
# - FIREBASE_STORAGE_BUCKET='circles-app-83b67.appspot.com'
```

**ALWAYS use --update-env-vars to add/modify variables:**
```bash
# ✅ CORRECT: Preserves existing variables
gcloud run services update circles-backend \
  --update-env-vars NEW_VAR=value \
  --region us-central1

# ❌ WRONG: Deletes ALL existing variables!
gcloud run services update circles-backend \
  --set-env-vars NEW_VAR=value \
  --region us-central1
```

**Example: Update multiple variables:**
```bash
gcloud run services update circles-backend \
  --update-env-vars VAR1=value1,VAR2=value2 \
  --region us-central1
```

**To fix image upload 500 errors:**
```bash
gcloud run services update circles-backend \
  --update-env-vars FIREBASE_STORAGE_BUCKET=circles-app-83b67.appspot.com \
  --region us-central1
```

### iOS App Deployment

1. Update version in Xcode
2. Archive and upload to App Store Connect
3. Submit for review with notes about:
   - Location usage (for place recommendations)
   - Photo library access (profile pictures)
   - Push notifications (connection requests)

## Development Workflow

### Adding New Features

1. **Backend API Endpoint**:
```javascript
// 1. Add route in routes/featureRoutes.js
router.post('/endpoint', auth, featureController.method);

// 2. Implement controller in controllers/
exports.method = async (req, res) => {
  try {
    // Implementation
    res.json({ success: true, data: result });
  } catch (error) {
    res.status(500).json({ 
      success: false, 
      message: error.message 
    });
  }
};
```

2. **iOS Integration**:
```swift
// 1. Add to appropriate Service
func newFeature(param: String, completion: @escaping (Result<Model, Error>) -> Void) {
    APIService.shared.request(
        endpoint: "endpoint",
        method: .post,
        body: ["param": param]
    ) { result in
        // Handle response
    }
}

// 2. Call from ViewController
Service.shared.newFeature(param: value) { result in
    DispatchQueue.main.async {
        switch result {
        case .success(let data):
            // Update UI
        case .failure(let error):
            // Show error
        }
    }
}
```

### Git Workflow
1. Create feature branch: `git checkout -b feature/description`
2. Make changes and test
3. Commit with clear messages
4. Push and create PR
5. Deploy backend if needed
6. Test on device/simulator

## Code Style Guidelines

### JavaScript (Backend)
- Use ES6+ features (arrow functions, destructuring)
- Async/await over promises
- Consistent error handling
- JSDoc comments for functions
- camelCase for variables, PascalCase for classes

### Swift (iOS)
- Follow Swift naming conventions
- Use guard for early returns
- Prefer structs over classes when possible
- Document public APIs
- Use MARK: comments for organization
- Avoid force unwrapping

### General
- Clear, descriptive variable names
- Keep functions small and focused
- Comment complex logic
- Handle edge cases
- Add logging for debugging

## Testing Strategy

### Backend Testing
- Unit tests for controllers (Jest)
- Integration tests for API endpoints
- Mock Firebase for isolated tests
- Test both ID formats in all queries

### iOS Testing
- Unit tests for Services/Managers
- UI tests for critical flows
- Test on multiple device sizes
- Test with poor network conditions
- Verify deep linking works

### Manual Testing Checklist
- [ ] User registration and login
- [ ] Creating and editing circles
- [ ] Adding places to circles
- [ ] Sending connection requests
- [ ] Viewing network circles
- [ ] Sending messages
- [ ] Push notifications
- [ ] Image upload
- [ ] Search functionality
- [ ] Privacy settings

## Troubleshooting Guide

### Common Backend Issues

1. **Firebase initialization fails**
   - Check service account file exists
   - Verify environment variables
   - Ensure correct project ID

2. **Authentication errors**
   - Verify JWT_SECRET is set
   - Check token expiration
   - Validate Firebase credentials

3. **Database queries fail**
   - Check Firestore indexes
   - Verify collection names
   - Handle both ID formats

4. **Email sending fails**
   - Verify Gmail credentials
   - Check app password (not regular password)
   - Ensure less secure apps enabled

### Common iOS Issues

1. **Network requests fail**
   - Check API base URL
   - Verify token is included
   - Check info.plist for ATS

2. **Images don't load**
   - Verify URLs are HTTPS
   - Check image caching
   - Handle placeholder images

3. **Push notifications don't work**
   - Verify APNs certificates
   - Check FCM configuration
   - Ensure permissions granted

4. **UI layout issues**
   - Test on different devices
   - Check constraint conflicts
   - Verify safe area usage

### Debugging Tips

1. **Enable verbose logging**:
```javascript
// Backend
console.log('🔍 Debug:', variable);

// iOS
print("🔍 Debug: \(variable)")
```

2. **Check Cloud Run logs**:

**⚠️ IMPORTANT: Always check Cloud Run logs when debugging backend issues!**

Basic log viewing:
```bash
# View recent logs
gcloud run services logs read circles-backend --limit=50 --region us-central1

# View logs with specific filters
gcloud run services logs read circles-backend --limit=30 --region us-central1 | grep -E "(error|Error|ERROR)"

# View logs for specific issues
gcloud run services logs read circles-backend --limit=30 --region us-central1 | grep -E "(upload|storage|bucket)" -i
```

Common log patterns to look for:
- `"The specified bucket does not exist"` - Firebase Storage misconfiguration
- `"secretOrPrivateKey must have a value"` - JWT_SECRET not set
- `"ECONNREFUSED"` - Database connection issues
- `"413 Request Entity Too Large"` - Image size limit exceeded
- `"Failed to upload image"` - Storage permission issues

Real-time log streaming:
```bash
gcloud run services logs tail circles-backend --region us-central1
```

3. **Monitor Firestore usage**:
   - Check Firebase Console
   - Look for hot spots
   - Verify security rules

4. **iOS debugging**:
   - Use breakpoints liberally
   - Check network traffic in proxy
   - Verify Keychain access

## Important Environment Variables

### Backend (Cloud Run)

**⚠️ CURRENT PRODUCTION VALUES (January 2025) - DO NOT OVERWRITE:**
```bash
# Authentication
JWT_SECRET=[already set - do not change]
JWT_EXPIRE=30d

# Firebase Configuration  
FIREBASE_PROJECT_ID=circles-app-83b67  # NOT circles-backend!
FIREBASE_STORAGE_BUCKET=circles-app-83b67.firebasestorage.app  # Required for image uploads

# Email Configuration
EMAIL_USER=noreply@circles-app.com
APP_URL=https://circles-app.com
GMAIL_USER=circles.app.notifications@gmail.com
GMAIL_APP_PASSWORD=[already set - app-specific password]

# Optional/Not Set
# GOOGLE_PLACES_API_KEY=<not currently set>
# NODE_ENV=production
```

**To add new variables without deleting existing ones:**
```bash
gcloud run services update circles-backend \
  --update-env-vars NEW_VAR=value \
  --region us-central1
```

### iOS Frontend Configuration

**API Environment Configuration (APIService.swift):**
```swift
// IMPORTANT: Current production URL - DO NOT change without updating backend
enum APIEnvironment {
    case development  // http://192.168.0.120:3001/api (local dev)
    case staging      // https://api-staging.circles-app.com/api (not active)
    case production   // https://circles-backend-196924649787.us-central1.run.app/api
}

// Current setting (lines 73-76):
#if DEBUG
private var environment: APIEnvironment = .production  // Uses production even in DEBUG
#else
private var environment: APIEnvironment = .production
#endif
```

**Other iOS Configuration Files:**
- **GoogleService-Info.plist**: Firebase configuration (required)
- **Bundle ID**: com.favcircles.circles
- **Info.plist**: Contains app permissions and settings
- **Keychain**: Stores JWT tokens securely

**⚠️ IMPORTANT: Image Compression Settings (PlaceService.swift):**
```swift
// DO NOT change these without updating backend
let maxSizeKB: Double = 1024  // 1MB limit
let compressionLevels: [Float] = [0.8, 0.6, 0.4, 0.2, 0.1, 0.05]
let resizeDimensions: [CGFloat] = [2048, 1920, 1280, 1024, 800, 640]
```

## Contact & Resources

- Firebase Console: https://console.firebase.google.com
- Google Cloud Console: https://console.cloud.google.com
- App Store Connect: https://appstoreconnect.apple.com

## Notes for AI Assistants

1. **Always check both user ID formats** when querying
2. **Run linting** before committing: `npm run lint`
3. **Test on real device** for location/camera features
4. **Use --update-env-vars** for Cloud Run updates
5. **ALWAYS check Cloud Run logs** when debugging backend issues:
   ```bash
   gcloud run services logs read circles-backend --limit=30 --region us-central1 | grep -i error
   ```
   The logs will show the actual error (e.g., "bucket does not exist", "JWT secret missing", etc.)
6. **Follow existing patterns** in the codebase
7. **Document significant changes** in this file
8. **For image upload issues**, check:
   - Firebase Storage bucket exists and name matches env var
   - Image size is under 1MB after base64 encoding
   - Firebase Storage permissions are configured correctly

## CRITICAL API USAGE POLICY

⚠️ **IMPORTANT: Cost-Efficient API Usage** ⚠️

1. **USE APPLE MAPS FOR EVERYTHING** except fetching photos
2. **ONLY use Google Places API for photos** - nothing else
3. **Apple Maps is MORE COST-EFFICIENT** than Google Maps
4. **See APIUsageGuidelines.md** for detailed policy

**Quick Reference:**
- ✅ Place search: Use MKLocalSearch (Apple)
- ✅ Geocoding: Use CLGeocoder (Apple)  
- ✅ Maps: Use MKMapView (Apple)
- ✅ Street View: Use Apple Look Around
- ✅ Navigation: Use Apple Maps
- ❌ ONLY Google: Fetching place photos

Remember: The app is actively used, so maintain backwards compatibility and test thoroughly before deploying changes.

## AI Assistant Guidelines

### Key Principles for AI Assistants

1. **Always Check for Duplicate Requests**
   - APIService blocks duplicate GET requests to prevent server overload
   - If you need the same data multiple times, fetch once and reuse
   - Example: Don't call `fetchUserCircles` twice - calculate all stats from one fetch

2. **Understand the Dual ID System**
   - Users can have simple IDs: `9b5eeac93282416c9bc6dcecbc49b40f`
   - Or complex IDs: `000454.9b5eeac93282416c9bc6dcecbc49b40f.2127`
   - Always check both formats when querying

3. **Performance & Scalability First**
   - Use dedicated counter fields (like `placesCount`) instead of array lengths
   - Avoid fetching all data just to count items
   - Think about millions of users with thousands of items each

4. **Follow Existing Patterns**
   - Check how similar features are implemented before creating new ones
   - Use the Service/Manager pattern consistently
   - Maintain the MVC architecture in iOS code

5. **Debug Effectively**
   - Add console.log/print statements to trace data flow
   - Check Cloud Run logs: `gcloud run services logs read circles-backend --limit=30 --region us-central1`
   - Use Xcode console for iOS debugging

6. **Common Pitfalls to Avoid**
   - Don't create new files unless absolutely necessary
   - Don't use `--set-env-vars` (it deletes all existing vars)
   - Don't assume a library is available - check package.json/Podfile first
   - Don't force unwrap optionals in Swift
   - Don't forget to update both iOS models when changing backend models

7. **Testing Checklist**
   - [ ] Test on real device (not just simulator)
   - [ ] Check both light and dark mode
   - [ ] Verify offline behavior
   - [ ] Test with empty states (no circles, no places, etc.)
   - [ ] Verify proper error handling
   - [ ] Check memory usage and performance

8. **When Making UI Changes**
   - Follow iOS Human Interface Guidelines
   - Maintain consistency with existing UI patterns
   - Test on different screen sizes (iPhone SE to Pro Max)
   - Consider accessibility (VoiceOver, Dynamic Type)

9. **Backend Best Practices**
   - Always use transactions for multi-document updates
   - Implement proper error handling with meaningful messages
   - Add indexes for Firestore queries (check firestore.indexes.json)
   - Use batch operations when updating multiple documents

10. **Deployment Process**
    - Build and test locally first
    - Deploy backend: build Docker image → deploy to Cloud Run
    - For iOS: increment build number → archive → upload to TestFlight
    - Monitor logs after deployment for any issues

### Quick Reference Commands

```bash
# Backend deployment
cd backend
gcloud builds submit --tag gcr.io/circles-app-83b67/circles-api --project circles-app-83b67
gcloud run deploy circles-backend --image gcr.io/circles-app-83b67/circles-api --platform managed --region us-central1 --project circles-app-83b67

# View logs
gcloud run services logs read circles-backend --limit=50 --region us-central1

# Update env vars (NEVER use --set-env-vars)
gcloud run services update circles-backend --update-env-vars KEY=value --region us-central1

# iOS build
cd ios
xcodebuild -project Circles-iOS.xcodeproj -scheme Circles-iOS -sdk iphonesimulator build
```

### Architecture Decision Records

1. **Why UIKit instead of SwiftUI?**
   - Project started before SwiftUI was mature
   - Better performance for complex layouts
   - More control over animations and transitions

2. **Why Firebase Firestore?**
   - Real-time capabilities for future features
   - Good iOS/Android SDK support
   - Scalable NoSQL structure fits the data model

3. **Why separate placesCount field?**
   - O(1) time complexity for counting
   - Reduces data transfer (don't need to fetch all places)
   - Better for pagination and infinite scroll

4. **Why Google Cloud Run?**
   - Serverless scaling
   - Pay only for what you use
   - Easy integration with Firebase
   - Good cold start performance

### 8. Real-Time SSE Notification System (July 2025)
**Problem**: Users had to manually refresh or exit/re-enter views to see new connection requests, messages, and other activities. Message polling was inefficient and caused excessive logging.

**Solution**: Implemented Server-Sent Events (SSE) for real-time notifications across the app.

#### Backend SSE Implementation:

1. **SSE Service** (`/backend/services/sseService.js`):
```javascript
// Manages SSE connections for each user
class SSEService {
  addClient(userId, res) // Add SSE client
  removeClient(userId, res) // Remove on disconnect
  setupListeners(userId) // Set up Firestore listeners
  notifyUser(userId, eventType, data) // Send event to user
}

// Event types supported:
- connection_request: New connection request received
- connection_accepted: Connection request was accepted
- connection_declined: Connection request was declined
- new_message: New message received
- new_suggestion: New place suggestion received
```

2. **SSE Endpoint** (`/api/sse/stream`):
- Maintains persistent connection with clients
- Sends heartbeat every 30 seconds to keep alive
- Automatically sets up Firestore listeners for the authenticated user
- Handles reconnection gracefully

3. **Integration in Controllers**:
```javascript
// connectionController.js - Send SSE on new connection request
sseService.notifyUser(targetUserId, 'connection_request', {
  connectionId: connection.id,
  from: connection.connectedUser,
  message: message || null
});

// messagingController.js - Send SSE on new message
sseService.notifyUser(recipientId, 'new_message', {
  messageId: message.id,
  conversationId: conversationId,
  senderId: userId,
  senderName: senderName,
  content: content,
  type: type
});
```

#### iOS SSE Implementation:

1. **SSE Service** (`/ios/Services/SSEService.swift`):
```swift
// Singleton service for SSE connections
class SSEService: NSObject {
  static let shared = SSEService()
  
  func connect() // Establish SSE connection
  func disconnect() // Close connection
  func addDelegate(_ delegate: SSEServiceDelegate) // Add listener
  
  // Automatic features:
  - Reconnection with exponential backoff
  - Authentication integration
  - Event parsing and dispatching
  - Heartbeat handling
}

// SSE Event Types
enum SSEEventType: String {
  case connected
  case connectionRequest
  case connectionAccepted
  case connectionDeclined
  case newMessage
  case newSuggestion
}
```

2. **View Controller Integration**:
```swift
// MyNetworkViewController - Real-time connection updates
extension MyNetworkViewController: SSEServiceDelegate {
  func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
    switch event.type {
    case .connectionRequest:
      // Refresh connections list automatically
      NetworkManager.shared.loadConnections()
      showNewConnectionBanner(event.data)
    }
  }
}

// ConversationsListViewController - Real-time message updates
extension ConversationsListViewController: SSEServiceDelegate {
  func sseService(_ service: SSEService, didReceiveEvent event: SSEEvent) {
    switch event.type {
    case .newMessage:
      // Refresh conversations automatically
      messagingManager.loadConversations(forceRefresh: true)
      showNewMessageBanner(event.data)
    }
  }
}
```

3. **App Startup** (AppDelegate.swift):
```swift
// SSE starts automatically on app launch
SSEService.shared.connect()
```

#### Benefits of SSE System:

1. **Real-Time Updates**: Users see changes instantly without manual refresh
2. **No More Polling**: Eliminated inefficient message polling timer
3. **Better Performance**: Reduced server load and battery consumption
4. **Clean Logs**: Removed excessive "Using cached conversations" and "Network connection restored" logging
5. **Unified System**: All real-time updates flow through one infrastructure

#### SSE vs WebSocket Decision:
- Chose SSE over WebSocket because:
  - One-way communication (server to client) is sufficient
  - Simpler implementation and debugging
  - Built-in reconnection in browsers/URLSession
  - Lower server resource usage
  - Works better with Cloud Run's request timeout

#### Usage Notes:
- SSE connection automatically established when user logs in
- Reconnects automatically with exponential backoff on disconnect
- Each user can have multiple connected devices (all receive events)
- Events are not persisted - only for real-time updates
- Push notifications still sent for offline users

### Future Considerations

- Consider implementing GraphQL for more efficient data fetching
- Add Redis caching layer for frequently accessed data
- ~~Implement WebSocket for real-time features~~ ✅ Implemented SSE instead (July 2025)
- Consider moving to Swift Concurrency (async/await)
- Add comprehensive unit and integration tests
- Implement CI/CD pipeline with GitHub Actions
- Consider adding SSE events for:
  - Circle updates (when someone adds a place to a shared circle)
  - Like notifications
  - Comment notifications
  - User online/offline status