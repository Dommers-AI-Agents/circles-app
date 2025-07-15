# Circles App

A social recommendation platform where users create curated collections of their favorite places and share them with their network.

## 🏗️ Architecture Overview

### Design Pattern
- **Enhanced MVC Architecture** with Service/Manager layers
- **74% code reduction** achieved through consolidation (29,300 → 7,562 lines)
- **BaseViewController pattern** for all 49 ViewControllers
- **Factory patterns** for UI components
- **Utility framework** for common functionality

### Tech Stack

#### Backend
- **Runtime**: Node.js 18+ with Express.js
- **Database**: Google Firestore (NoSQL)
- **Authentication**: Firebase Auth + JWT tokens
- **File Storage**: Firebase Storage & Google Cloud Storage
- **Deployment**: Google Cloud Run (containerized)
- **External APIs**: Apple Maps API (primary), Google Places API (photos only)

#### iOS Frontend
- **Language**: Swift 5
- **UI Framework**: UIKit (not SwiftUI)
- **Architecture**: Enhanced MVC with Service/Manager layers
- **Networking**: URLSession with custom APIService
- **Image Loading**: Custom ImageService with caching
- **Push Notifications**: Firebase Cloud Messaging
- **Real-time Updates**: Server-Sent Events (SSE)

## 📁 Project Structure

```
circles-app/
├── backend/
│   ├── controllers/        # API endpoint handlers
│   ├── models/            # Firestore data models
│   ├── routes/            # Express route definitions
│   ├── services/          # Business logic services
│   ├── middleware/        # Auth, error handling, etc.
│   ├── utils/             # Helper functions
│   └── server.js          # Express server entry point
│
├── ios/
│   └── Circles-iOS-UIKit/
│       ├── Controllers/   # ViewControllers (MVC)
│       │   ├── Base/     # BaseViewController
│       │   ├── Authentication/
│       │   ├── Circles/
│       │   ├── Network/
│       │   ├── Places/
│       │   ├── Messages/
│       │   └── Profile/
│       ├── Models/        # Data models
│       ├── Services/      # API & business services
│       ├── Managers/      # App-wide managers
│       ├── Views/         # Custom UI components
│       ├── Extensions/    # Swift extensions
│       └── Utilities/     # Helper classes
│
└── docs/                  # Documentation

```

## 🔑 Key Features

### Core Functionality
- **Circles**: Curated collections of places organized by category
- **Places**: Locations with Google Places data + user notes
- **Connections**: Bidirectional relationships between users
- **Privacy Levels**: Public, My Network, or Private circles
- **Real-time Updates**: SSE for instant notifications
- **Offline Support**: Local caching for better performance

### Enhanced Features
- **Activity Feed**: LinkedIn-style updates on home screen
- **Quick Access**: Home/Work place shortcuts
- **Place Discovery**: Search across your network's places
- **Suggestions**: Send place recommendations to connections
- **Comments & Likes**: Social engagement features

## 🚀 Deployment

### Backend Deployment (Google Cloud Run)

```bash
# Build and deploy
cd backend
gcloud builds submit --tag gcr.io/PROJECT_ID/circles-backend
gcloud run deploy circles-backend \
  --image gcr.io/PROJECT_ID/circles-backend \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

### Environment Variables
- `FIREBASE_PROJECT_ID`
- `FIREBASE_PRIVATE_KEY`
- `FIREBASE_CLIENT_EMAIL`
- `JWT_SECRET`
- `APPLE_MAPS_AUTH_TOKEN`
- `GOOGLE_PLACES_API_KEY`

### Firestore Configuration
- **Collections**: users, circles, places, connections, messages, activities
- **Indexes**: Configured in `firestore.indexes.json`
- **Security Rules**: Defined in `firestore.rules`

## 🏛️ Architecture Details

### Backend Architecture
- **RESTful API** with Express.js
- **Middleware Stack**: 
  - CORS configuration
  - JWT authentication
  - Request validation
  - Error handling
- **Service Layer**: Business logic separated from controllers
- **Real-time Events**: SSE for push notifications

### iOS Architecture
- **BaseViewController Pattern**: All ViewControllers inherit common functionality
- **Service Layer**: 
  - `APIService`: Network requests
  - `AuthService`: Authentication
  - `CircleService`, `PlaceService`, etc.: Domain-specific
- **Manager Layer**:
  - `NetworkManager`: Connection management
  - `MessagingManager`: Real-time messaging
  - `PreloadManager`: App initialization
- **Utility Classes**:
  - `AlertPresenter`: Standardized alerts
  - `ImageService`: Image caching
  - `LocationService`: Location services

### Code Organization Principles
1. **DRY (Don't Repeat Yourself)**: Achieved through BaseViewController and utilities
2. **Separation of Concerns**: Clear boundaries between layers
3. **Factory Patterns**: `UIButton.factory` methods for consistent UI
4. **Builder Pattern**: `User.copy()` for immutable updates
5. **Protocol-Oriented**: Extensive use of Swift protocols

## 🔐 Security

- **Authentication**: Firebase Auth with JWT tokens
- **Authorization**: Role-based access control
- **Data Privacy**: Circle privacy levels enforced at API level
- **Secure Storage**: Keychain for sensitive data on iOS
- **HTTPS**: All API communication encrypted

## 🛠️ Development Setup

### Backend
```bash
cd backend
npm install
npm run dev  # Starts on port 5001
```

### iOS
1. Open `Circles-iOS.xcodeproj` in Xcode
2. Install Swift Package Manager dependencies
3. Configure Firebase with `GoogleService-Info.plist`
4. Build and run on simulator or device

## 📊 Performance Optimizations

- **Image Caching**: In-memory and disk caching
- **Lazy Loading**: Pagination for large data sets
- **Background Refresh**: Periodic updates when app is inactive
- **Efficient Queries**: Firestore composite indexes
- **Code Size**: 74% reduction through consolidation

## 🧪 Testing

- **Backend**: Jest for unit tests, Supertest for API tests
- **iOS**: XCTest for unit and UI tests
- **Integration**: End-to-end testing with real Firestore

## 📱 Platform Support

- **iOS**: 14.0+ (optimized for iOS 17+)
- **Backend**: Node.js 18+ on Google Cloud Run
- **Database**: Firestore with automatic scaling

## 🤝 Contributing

1. Follow the established patterns (BaseViewController, factories, etc.)
2. Maintain the 74% code reduction achievement
3. Add appropriate error handling
4. Update tests for new features
5. Follow Swift and JavaScript style guides

## 📄 License

Private and confidential - All rights reserved