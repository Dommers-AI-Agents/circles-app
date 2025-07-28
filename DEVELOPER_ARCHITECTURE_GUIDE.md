# Circles App - Developer Architecture Guide

## Table of Contents

1. [Overview](#overview)
2. [Backend Architecture](#backend-architecture)
   - [Controllers](#controllers)
   - [Services](#services)
   - [Models](#models)
   - [Routes](#routes)
   - [Middleware](#middleware)
3. [iOS Frontend Architecture](#ios-frontend-architecture)
   - [ViewControllers](#viewcontrollers)
   - [Services](#ios-services)
   - [Models](#ios-models)
   - [Managers](#managers)
   - [Utilities](#utilities)
4. [MVC Pattern Implementation](#mvc-pattern-implementation)
5. [API Reference](#api-reference)
6. [Database Schema](#database-schema)
7. [Code Reuse Framework](#code-reuse-framework)
8. [Architecture Patterns](#architecture-patterns)

---

## Overview

The Circles app is a social recommendation platform built with Node.js/Express backend and native iOS frontend. It follows Model-View-Controller (MVC) architecture with a service layer pattern for business logic separation.

### Key Technologies
- **Backend**: Node.js, Express.js, Firebase Firestore, Firebase Auth
- **iOS**: Swift, UIKit, Firebase SDK
- **Architecture**: MVC + Service Layer + Repository Pattern
- **Real-time**: Server-Sent Events (SSE)
- **Code Reduction**: 74% reduction achieved through utility framework

---

# Backend Architecture

## Controllers

### Authentication Controllers
| Controller | File | Key Methods | Responsibility |
|------------|------|-------------|----------------|
| **FirebaseAuthController** | `firebaseAuthController.js` | `login()`, `register()`, `logout()`, `refreshToken()` | Firebase authentication management |
| **AuthController** | `authController.js` | `authenticate()`, `validateToken()` | Legacy auth controller |
| **LinkedinAuthController** | `linkedinAuthController.js` | `initiateAuth()`, `handleCallback()` | LinkedIn OAuth integration |

### Core Entity Controllers
| Controller | File | Key Methods | Responsibility |
|------------|------|-------------|----------------|
| **FirebaseCircleController** | `firebaseCircleController.js` | `getMyCircles()`, `createCircle()`, `updateCircle()`, `deleteCircle()`, `shareCircle()`, `likeCircle()`, `getCircleComments()`, `addCircleComment()` | Circle CRUD and interactions |
| **FirebasePlaceController** | `firebasePlaceController.js` | `getPlacesByCircleId()`, `createPlace()`, `updatePlace()`, `deletePlace()`, `likePlace()`, `getPlaceComments()`, `addPlaceComment()` | Place CRUD and interactions |
| **FirebaseUserController** | `firebaseUserController.js` | `getProfile()`, `updateProfile()`, `searchUsers()`, `followUser()`, `unfollowUser()` | User profile management |

### Social Features Controllers
| Controller | File | Key Methods | Responsibility |
|------------|------|-------------|----------------|
| **ConnectionController** | `connectionController.js` | `sendRequest()`, `acceptRequest()`, `getConnections()`, `removeConnection()` | User connections management |
| **MessagingController** | `messagingController.js` | `getConversations()`, `sendMessage()`, `markAsRead()` | Chat and messaging |
| **SuggestionController** | `suggestionController.js` | `createSuggestion()`, `getSuggestions()`, `likeSuggestion()` | Place suggestions between users |

### Utility Controllers
| Controller | File | Key Methods | Responsibility |
|------------|------|-------------|----------------|
| **ActivityController** | `activityController.js` | `getActivities()`, `createActivity()`, `trackUserActivity()` | User activity tracking |
| **NotificationController** | `notificationController.js` | `sendNotification()`, `getNotifications()`, `markAsRead()` | Push notifications |
| **UserCategoriesController** | `userCategoriesController.js` | `getCategories()`, `createCategory()`, `updateCategory()` | Custom place categories |
| **CircleSharingController** | `circleSharingController.js` | `shareCircle()`, `revokeShare()`, `validateShareToken()` | Advanced circle sharing |

## Services

### Core Business Logic Services
| Service | File | Key Functions | Purpose |
|---------|------|---------------|---------|
| **ActivityService** | `activityService.js` | `trackCircleCreated()`, `trackPlaceAdded()`, `trackCircleLiked()`, `trackCircleCommented()`, `getConnectionsWithStats()` | Activity tracking and feed |
| **NotificationService** | `notificationService.js` | `sendPushNotification()`, `sendPlaceLikeNotification()`, `sendCommentNotification()` | Push notification delivery |
| **SSEService** | `sseService.js` | `sendEvent()`, `addClient()`, `removeClient()`, `broadcast()` | Real-time event streaming |

### External Integrations
| Service | File | Key Functions | Purpose |
|---------|------|---------------|---------|
| **GoogleMaps** | `googleMaps.js` | `geocodeAddress()`, `getPlaceDetails()`, `searchNearbyPlaces()` | Google Maps API integration |
| **EmailService** | `emailService.js` | `sendWelcomeEmail()`, `sendPasswordReset()`, `sendNotificationEmail()` | Email delivery |
| **Storage** | `storage.js` | `uploadImage()`, `deleteImage()`, `generateSignedUrl()` | File storage management |

### Utility Services
| Service | File | Key Functions | Purpose |
|---------|------|---------------|---------|
| **IdService** | `idService.js` | `normalizeUserId()`, `validateId()` | ID normalization |
| **OnboardingService** | `onboardingService.js` | `createWelcomeData()`, `populateInitialPlaces()` | New user onboarding |
| **PlaceDiscoveryService** | `placeDiscoveryService.js` | `discoverPopularPlaces()`, `enrichPlaceData()` | Place discovery and enrichment |

## Models

### Core Data Models
Located in `models/FirestoreModels.js`:

| Model Function | Purpose | Key Fields |
|----------------|---------|------------|
| **createUser()** | User document structure | `email`, `displayName`, `profilePicture`, `followers`, `following`, `connections` |
| **createCircle()** | Circle document structure | `name`, `description`, `owner`, `places`, `privacy`, `likes`, `likesCount`, `commentsCount` |
| **createPlace()** | Place document structure | `name`, `address`, `location`, `category`, `circleId`, `likes`, `likesCount` |
| **createCircleComment()** | Circle comment structure | `circleId`, `userId`, `text`, `likes`, `likesCount` |
| **createConnection()** | Connection document structure | `userId`, `connectedUserId`, `status`, `recentActivity` |
| **createMessage()** | Message document structure | `conversationId`, `senderId`, `content`, `type`, `readBy` |

### Validation Functions
| Function | Purpose |
|----------|---------|
| **validateCircle()** | Circle data validation |
| **validatePlace()** | Place data validation |
| **validateCircleComment()** | Comment validation |
| **validateUser()** | User profile validation |

## Routes

### API Endpoint Structure

| Route File | Base Path | Authentication | Purpose |
|------------|-----------|----------------|---------|
| **firebaseAuthRoutes.js** | `/api/auth` | Public/Protected | Authentication endpoints |
| **firebaseCircleRoutes.js** | `/api/circles` | Protected | Circle CRUD and interactions |
| **firebasePlaceRoutes.js** | `/api/places` | Protected | Place CRUD and interactions |
| **firebaseUserRoutes.js** | `/api/users` | Protected | User profile management |
| **connectionRoutes.js** | `/api/connections` | Protected | User connections |
| **messagingRoutes.js** | `/api/messages` | Protected | Chat and messaging |
| **userCategoriesRoutes.js** | `/api/categories` | Protected | Custom categories |
| **sseRoutes.js** | `/api/sse` | Protected | Real-time events |

## Middleware

| Middleware | File | Purpose |
|------------|------|---------|
| **firebaseAuth.js** | Authentication verification using Firebase tokens |
| **errorHandler.js** | Global error handling and logging |
| **auth.js** | Legacy authentication middleware |

---

# iOS Frontend Architecture

## ViewControllers

### Base Controller Architecture
All ViewControllers inherit from **BaseViewController** which provides:
- Loading states management
- Pull-to-refresh functionality
- Empty state handling
- Error presentation
- Data loading lifecycle

### Authentication Controllers
| Controller | File | Key Methods | Purpose |
|------------|------|-------------|---------|
| **LoginViewController** | `LoginViewController.swift` | `handleGoogleSignIn()`, `handleAppleSignIn()`, `navigateToEmailLogin()` | Main login screen |
| **EmailLoginViewController** | `EmailLoginViewController.swift` | `loginWithEmail()`, `validateCredentials()` | Email/password login |
| **RegisterViewController** | `RegisterViewController.swift` | `registerUser()`, `validateRegistration()` | User registration |

### Core Feature Controllers

#### Circle Management
| Controller | File | Key Methods | Purpose |
|------------|------|-------------|---------|
| **CirclesHomeViewController** | `CirclesHomeViewController.swift` | `loadData()`, `refreshCircles()`, `performSearch()`, `showMapView()` | Main circles feed with search |
| **CreateCircleViewController** | `CreateCircleViewController.swift` | `createCircle()`, `selectCategory()`, `setPrivacy()` | Circle creation workflow |
| **CircleDetailViewController** | `CircleDetailViewController.swift` | `loadCircleData()`, `addPlace()`, `shareCircle()`, `likeCircle()` | Circle detail view with places |
| **EditCircleViewController** | `EditCircleViewController.swift` | `updateCircle()`, `deleteCircle()`, `manageEditors()` | Circle editing |
| **CircleLikesViewController** | `CircleLikesViewController.swift` | `loadData()`, `showUserProfile()` | Users who liked circle |
| **CircleCommentsViewController** | `CircleCommentsViewController.swift` | `loadData()`, `addComment()`, `deleteComment()` | Circle comments interface |

#### Place Management
| Controller | File | Key Methods | Purpose |
|------------|------|-------------|---------|
| **AddPlaceViewController** | `AddPlaceViewController.swift` | `addPlace()`, `searchPlaces()`, `selectFromMap()`, `enableManualEntry()` | Add places to circles |
| **PlaceDetailViewController** | `PlaceDetailViewController.swift` | `loadPlaceData()`, `likePlace()`, `addComment()`, `getDirections()` | Place detail view |
| **EditPlaceViewController** | `EditPlaceViewController.swift` | `updatePlace()`, `deletePlace()`, `editNotes()` | Place editing |
| **PlaceCommentsViewController** | `PlaceCommentsViewController.swift` | `loadData()`, `addComment()`, `deleteComment()` | Place comments |
| **PlaceLikesViewController** | `PlaceLikesViewController.swift` | `loadData()`, `showUserProfile()` | Users who liked place |

#### Network & Social
| Controller | File | Key Methods | Purpose |
|------------|------|-------------|---------|
| **MyNetworkViewController** | `MyNetworkViewController.swift` | `loadConnections()`, `sendConnectionRequest()`, `viewSuggestions()` | Main network hub |
| **ConnectionsListViewController** | `ConnectionsListViewController.swift` | `loadData()`, `searchConnections()`, `removeConnection()` | Connections list |
| **AllUsersListViewController** | `AllUsersListViewController.swift` | `loadData()`, `searchUsers()`, `sendConnectionRequest()` | Discover users |
| **ConnectionDetailViewController** | `ConnectionDetailViewController.swift` | `loadUserData()`, `viewSharedCircles()`, `sendMessage()` | Connection profile |
| **SharedCirclesListViewController** | `SharedCirclesListViewController.swift` | `loadData()`, `viewCircleDetail()` | Connection's shared circles |
| **SuggestionsViewController** | `SuggestionsViewController.swift` | `loadData()`, `createSuggestion()`, `viewSuggestionDetail()` | Place suggestions |

#### Messaging
| Controller | File | Key Methods | Purpose |
|------------|------|-------------|---------|
| **ConversationsListViewController** | `ConversationsListViewController.swift` | `loadData()`, `openConversation()`, `deleteConversation()` | Messages list |
| **ChatViewController** | `ChatViewController.swift` | `loadMessages()`, `sendMessage()`, `markAsRead()` | Chat interface |
| **SelectConnectionViewController** | `SelectConnectionViewController.swift` | `loadData()`, `selectConnection()` | Choose message recipient |

#### Profile Management
| Controller | File | Key Methods | Purpose |
|------------|------|-------------|---------|
| **ProfileViewController** | `ProfileViewController.swift` | `loadData()`, `editProfile()`, `viewFollowers()`, `shareProfile()` | User profile |
| **EditProfileViewController** | `EditProfileViewController.swift` | `updateProfile()`, `uploadProfilePicture()`, `validateChanges()` | Profile editing |
| **SettingsViewController** | `SettingsViewController.swift` | `updateNotificationSettings()`, `changePassword()`, `logout()` | App settings |
| **FollowersListViewController** | `FollowersListViewController.swift` | `loadData()`, `followUser()`, `unfollowUser()` | Followers/following lists |

## iOS Services

### Core API Services
| Service | File | Key Methods | Purpose |
|---------|------|-------------|---------|
| **APIService** | `APIService.swift` | `request()`, `upload()`, `handleAuthentication()` | Base HTTP client |
| **AuthService** | `AuthService.swift` | `signIn()`, `signOut()`, `refreshToken()`, `getCurrentUser()` | Authentication management |
| **CircleService** | `CircleService.swift` | `getMyCircles()`, `createCircle()`, `likeCircle()`, `getCircleComments()`, `addCircleComment()` | Circle API calls |
| **PlaceService** | `PlaceService.swift` | `getPlaces()`, `createPlace()`, `likePlace()`, `getPlaceComments()`, `addPlaceComment()` | Place API calls |
| **UserService** | `UserService.swift` | `getProfile()`, `updateProfile()`, `searchUsers()`, `followUser()` | User API calls |

### External Integration Services
| Service | File | Key Methods | Purpose |
|---------|------|-------------|---------|
| **GooglePlacesService** | `GooglePlacesService.swift` | `searchPlaces()`, `getPlaceDetails()`, `getPlacePhotos()` | Google Places API |
| **AppleMapsService** | `AppleMapsService.swift` | `searchLocalPlaces()`, `getCoordinates()`, `extractPOIData()` | Apple Maps integration |
| **LocationService** | `LocationService.swift` | `getCurrentLocation()`, `requestPermission()`, `startLocationUpdates()` | Location management |
| **ImageService** | `ImageService.swift` | `loadImage()`, `uploadImage()`, `cacheImage()` | Image loading and caching |

### Real-time & Notification Services
| Service | File | Key Methods | Purpose |
|---------|------|-------------|---------|
| **SSEService** | `SSEService.swift` | `connect()`, `disconnect()`, `handleEvent()` | Real-time events |
| **NotificationService** | `NotificationService.swift` | `requestPermission()`, `handleNotification()`, `updateBadgeCount()` | Push notifications |
| **MessagingService** | `MessagingService.swift` | `getConversations()`, `sendMessage()`, `markAsRead()` | Chat functionality |

### Utility Services
| Service | File | Key Methods | Purpose |
|---------|------|-------------|---------|
| **KeychainService** | `KeychainService.swift` | `save()`, `load()`, `delete()` | Secure storage |
| **CategoryService** | `CategoryService.swift` | `getCategories()`, `createCategory()`, `updateCategory()` | Custom categories |
| **UpdateService** | `UpdateService.swift` | `checkForUpdates()`, `downloadUpdate()` | App updates |

## iOS Models

### Core Data Models
| Model | File | Key Properties | Purpose |
|-------|------|----------------|---------|
| **User** | `User.swift` | `id`, `displayName`, `email`, `profilePicture`, `followers`, `following` | User representation |
| **Circle** | `Circle.swift` | `id`, `name`, `description`, `owner`, `places`, `privacy`, `likes`, `likesCount`, `commentsCount` | Circle data |
| **Place** | `Place.swift` | `id`, `name`, `address`, `location`, `category`, `circleId`, `likes`, `likesCount` | Place data |
| **CircleComment** | `CircleComment.swift` | `id`, `circleId`, `userId`, `text`, `likes`, `user`, `createdAt` | Circle comments |
| **Connection** | `Connection.swift` | `id`, `userId`, `connectedUserId`, `status`, `recentActivity` | User connections |
| **Message** | `Message.swift` | `id`, `conversationId`, `senderId`, `content`, `type`, `readBy` | Chat messages |

### Supporting Models
| Model | File | Purpose |
|-------|------|---------|
| **Activity** | `Activity.swift` | User activity tracking |
| **Suggestion** | `Suggestion.swift` | Place suggestions |
| **Conversation** | `Conversation.swift` | Chat conversations |
| **CircleShare** | `CircleShare.swift` | Circle sharing data |
| **GooglePlaceDetails** | `GooglePlaceDetails.swift` | Google Places API responses |

## Managers

### High-Level Coordination
| Manager | File | Key Methods | Purpose |
|---------|------|-------------|---------|
| **MessagingManager** | `MessagingManager.swift` | `setupNotifications()`, `handleIncomingMessage()`, `updateBadge()` | Messaging coordination |
| **NetworkManager** | `NetworkManager.swift` | `monitorConnectivity()`, `handleOfflineMode()` | Network state management |
| **OnboardingManager** | `OnboardingManager.swift` | `startOnboarding()`, `completeStep()`, `skipOnboarding()` | User onboarding flow |
| **PreloadManager** | `PreloadManager.swift` | `preloadData()`, `cacheEssentialData()` | Data preloading |

## Utilities

### Code Reuse Framework (74% Reduction Achieved)
| Utility | File | Key Functions | Purpose |
|---------|------|---------------|---------|
| **BaseViewController** | `BaseViewController.swift` | `loadData()`, `showLoadingState()`, `showEmptyState()`, `handleRefresh()` | Base VC with common functionality |
| **AlertPresenter** | `AlertPresenter.swift` | `showError()`, `showSuccess()`, `showConfirmation()`, `showLoading()` | Unified alert system |
| **UIButton+Factory** | `UIButton+Factory.swift` | `primaryButton()`, `secondaryButton()`, `dangerButton()`, `iconButton()` | Button factory methods |
| **User+Copy** | `User+Copy.swift` | `copy()`, `withConnectionStatus()`, `withFollowingStatus()` | User object copying |

### Extension Framework
| Extension | File | Purpose |
|-----------|------|---------|
| **UIViewController+Alerts** | `UIViewController+Alerts.swift` | Alert presentation methods |
| **UIViewController+KeyboardHandling** | `UIViewController+KeyboardHandling.swift` | Keyboard management |
| **UIColor+Extensions** | `UIColor+Extensions.swift` | Color utilities |
| **UIView+Extensions** | `UIView+Extensions.swift` | View helper methods |

### Core Utilities
| Utility | File | Purpose |
|---------|------|---------|
| **Constants** | `Constants.swift` | App-wide constants |
| **Logger** | `Logger.swift` | Logging system |
| **IDNormalizer** | `IDNormalizer.swift` | ID normalization |
| **NetworkMonitor** | `NetworkMonitor.swift` | Network state monitoring |

---

# MVC Pattern Implementation

## Model Layer
**Responsibility**: Data representation and business logic
- **Backend**: Firestore document models with validation
- **iOS**: Swift structs with computed properties and helper methods
- **Shared**: Consistent data structures across platforms

## View Layer
**Responsibility**: User interface presentation
- **iOS**: UIViewController subclasses with UIKit components
- **Pattern**: All VCs inherit from BaseViewController for consistency
- **Utilities**: Factory methods and extensions for UI components

## Controller Layer
**Responsibility**: Business logic coordination
- **Backend**: Express.js controllers handling HTTP requests
- **iOS**: ViewControllers coordinating between Models and Views
- **Service Layer**: Additional abstraction for complex business logic

## Service Layer Pattern
**Purpose**: Separate business logic from controllers
- **Backend**: Service classes for complex operations (activity tracking, notifications)
- **iOS**: Service classes for API communication and external integrations
- **Benefits**: Reusable, testable, and maintainable business logic

---

# API Reference

## Authentication Endpoints
```
POST   /api/auth/login
POST   /api/auth/register
POST   /api/auth/logout
POST   /api/auth/refresh
```

## Circle Endpoints
```
GET    /api/circles                     # Get user's circles
POST   /api/circles                     # Create circle
GET    /api/circles/:id                 # Get circle details
PUT    /api/circles/:id                 # Update circle
DELETE /api/circles/:id                 # Delete circle
POST   /api/circles/:id/like            # Like/unlike circle
GET    /api/circles/:id/likes           # Get circle likes
GET    /api/circles/:id/comments        # Get circle comments
POST   /api/circles/:id/comments        # Add circle comment
DELETE /api/circles/:circleId/comments/:commentId  # Delete comment
```

## Place Endpoints
```
GET    /api/places/circle/:circleId     # Get places in circle
POST   /api/places                      # Create place
GET    /api/places/:id                  # Get place details
PUT    /api/places/:id                  # Update place
DELETE /api/places/:id                  # Delete place
POST   /api/places/:id/like             # Like/unlike place
GET    /api/places/:id/likes            # Get place likes
GET    /api/places/:id/comments         # Get place comments
POST   /api/places/:id/comments         # Add place comment
```

## User & Social Endpoints
```
GET    /api/users/profile               # Get user profile
PUT    /api/users/profile               # Update profile
GET    /api/users/search                # Search users
POST   /api/connections/request         # Send connection request
POST   /api/connections/accept          # Accept request
GET    /api/connections                 # Get connections
GET    /api/messages/conversations      # Get conversations
POST   /api/messages                    # Send message
```

## Real-time Endpoints
```
GET    /api/sse                         # Server-Sent Events stream
```

---

# Database Schema

## Firestore Collections

### Users Collection
```javascript
{
  uid: "string",
  email: "string",
  displayName: "string",
  profilePicture: "string",
  followers: ["userId1", "userId2"],
  following: ["userId1", "userId2"],
  followersCount: 0,
  followingCount: 0,
  connectionsCount: 0,
  pinnedPlaces: ["placeId1", "placeId2"],
  notificationPreferences: { /* settings */ },
  createdAt: "ISO string",
  updatedAt: "ISO string"
}
```

### Circles Collection
```javascript
{
  _id: "string",
  name: "string",
  description: "string",
  owner: "userId",
  places: ["placeId1", "placeId2"],
  placesCount: 0,
  privacy: "public|myNetwork|private",
  category: "travel|food|other",
  likes: ["userId1", "userId2"],
  likesCount: 0,
  commentsCount: 0,
  createdAt: "ISO string",
  updatedAt: "ISO string"
}
```

### Places Collection
```javascript
{
  _id: "string",
  name: "string",
  address: "string",
  location: {
    type: "Point",
    coordinates: [longitude, latitude]
  },
  category: "restaurant|cafe|other",
  circleId: "string",
  addedBy: "userId",
  likes: ["userId1", "userId2"],
  likesCount: 0,
  commentsCount: 0,
  privacy: "followCircle|public|myNetwork|private",
  createdAt: "ISO string",
  updatedAt: "ISO string"
}
```

### CircleComments Collection
```javascript
{
  _id: "string",
  circleId: "string",
  userId: "string",
  text: "string",
  likes: ["userId1", "userId2"],
  likesCount: 0,
  createdAt: "ISO string"
}
```

### Connections Collection
```javascript
{
  userId: "string",
  connectedUserId: "string",
  status: "pending|accepted|blocked",
  recentActivity: [
    {
      type: "circle|place",
      entityId: "string",
      entityName: "string",
      createdAt: "ISO string",
      viewedAt: "ISO string"
    }
  ],
  hasNewActivity: false,
  createdAt: "ISO string",
  updatedAt: "ISO string"
}
```

## Firestore Indexes
Key indexes for performance:
- `circles`: `owner + privacy + updatedAt`
- `places`: `circleId + createdAt`
- `connections`: `userId + status`, `connectedUserId + status`
- `circleComments`: `circleId + createdAt`
- `placeComments`: `placeId + createdAt`
- `activities`: `actorId + timestamp`

---

# Code Reuse Framework

## Architecture Achievement: 74% Code Reduction

### Before Refactoring
- **Total Lines**: ~29,300
- **ViewControllers**: 49 controllers with duplicate code
- **Common Issues**: Repeated boilerplate, inconsistent patterns

### After Refactoring
- **Total Lines**: ~7,562 (74% reduction)
- **Utilities Added**: 4 files (1,162 lines)
- **Net Reduction**: 21,738 lines eliminated

### Mandatory Patterns

#### 1. BaseViewController Pattern
```swift
// ❌ Never do this
class MyViewController: UIViewController {
    var hasLoadedData = false
    let loadingIndicator = UIActivityIndicatorView()
    // 50+ lines of boilerplate...
}

// ✅ Always do this
class MyViewController: BaseViewController {
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No data" }
    
    override func loadData(completion: (() -> Void)?) {
        // Your data loading logic
        completion?()
    }
}
```

#### 2. UIButton Factory Pattern
```swift
// ❌ Never create buttons manually
let button = UIButton(type: .system)
button.setTitle("Save", for: .normal)
// 10+ lines of styling...

// ✅ Always use factory methods
let saveButton = UIButton.primaryButton(title: "Save")
let cancelButton = UIButton.secondaryButton(title: "Cancel")
let deleteButton = UIButton.dangerButton(title: "Delete")
```

#### 3. AlertPresenter Pattern
```swift
// ❌ Never use UIAlertController directly
let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
present(alert, animated: true)

// ✅ Always use AlertPresenter
showError(error)
AlertPresenter.showSuccess("Operation completed")
```

#### 4. User.copy() Pattern
```swift
// ❌ Never create User objects with all properties
self.user = User(id: user.id, email: user.email, /* 20+ properties */)

// ✅ Always use copy methods
self.user = user.copy(connectionDirection: "outgoing")
```

### Utility Framework Reference

#### BaseViewController Configuration
```swift
override var showsLoadingIndicator: Bool { true }
override var enablesPullToRefresh: Bool { false }
override var emptyStateMessage: String? { nil }
override var loadsDataOnViewDidLoad: Bool { true }
```

#### AlertPresenter Methods
```swift
showError(error)
showSuccess("Message")
showConfirmation(title: "Delete?", message: "Sure?") { /* action */ }
let loading = AlertPresenter.showLoading(from: self)
```

#### Button Factory Methods
```swift
UIButton.primaryButton(title: "Save")
UIButton.secondaryButton(title: "Cancel")
UIButton.dangerButton(title: "Delete")
UIButton.iconButton(systemName: "star.fill")
UIButton.googleSignInButton()
```

---

# Architecture Patterns

## Dependency Flow
```
ViewControllers → Services → APIService → Backend Controllers → Services → Database
```

## Error Handling Strategy
1. **Backend**: Centralized error handling middleware
2. **iOS**: Unified error presentation through AlertPresenter
3. **Network**: Automatic retry with exponential backoff

## Real-time Updates
1. **Server-Sent Events**: Unidirectional real-time communication
2. **Activity Tracking**: User actions tracked and broadcasted
3. **Efficient Updates**: Only relevant users receive notifications

## Performance Optimizations
1. **Image Caching**: Automatic image caching with memory management
2. **Data Pagination**: Efficient loading of large datasets
3. **Background Processing**: Heavy operations moved to background queues
4. **Connection Pooling**: Efficient HTTP connection management

## Security Measures
1. **Firebase Authentication**: JWT token-based authentication
2. **Input Validation**: Server-side validation for all inputs
3. **SQL Injection Prevention**: Firestore NoSQL prevents injection attacks
4. **Secure Storage**: Keychain storage for sensitive data

---

# Development Guidelines

## Adding New Features

### Backend Development
1. Create controller in `/controllers/`
2. Add business logic to `/services/`
3. Define routes in `/routes/`
4. Update models in `/models/FirestoreModels.js`
5. Add tests

### iOS Development
1. Inherit from `BaseViewController`
2. Use factory methods for UI components
3. Create service methods for API calls
4. Follow established patterns
5. Update models with new fields

### Database Changes
1. Update model creation functions
2. Add necessary Firestore indexes
3. Create migration scripts if needed
4. Update validation rules

## Debugging Guide

### Common Issues
1. **Authentication Errors**: Check Firebase token validity
2. **Data Loading Issues**: Verify service method implementations
3. **UI Problems**: Ensure BaseViewController pattern usage
4. **Network Issues**: Check API endpoint definitions

### Debugging Tools
1. **Backend Logs**: Console logging in all controllers
2. **iOS Logger**: Centralized logging system
3. **Network Monitoring**: Real-time network state tracking
4. **Performance Metrics**: Built-in performance monitoring

---

This documentation provides a comprehensive reference for understanding and working with the Circles app codebase. The hierarchical organization makes it easy to locate specific classes and functions for debugging and feature development.