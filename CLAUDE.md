# CLAUDE.md - AI Assistant Knowledge Base for Circles App

This comprehensive guide contains essential context, architecture details, and implementation patterns for AI assistants working on the Circles app. Last updated: January 2025.

## 🚨 **CRITICAL: CODE REUSE PRIORITY**

**THE CIRCLES APP HAS BEEN FULLY REFACTORED FOR MAXIMUM CODE REUSE. ALL NEW CODE MUST FOLLOW THESE PATTERNS:**

### **MANDATORY CODE REUSE UTILITIES** 
1. **ALWAYS inherit from `BaseViewController`** - Never use `UIViewController` directly
2. **ALWAYS use `UIButton` factory methods** - Never create buttons manually
3. **ALWAYS use `AlertPresenter`** - Never use `UIAlertController` directly  
4. **ALWAYS use `User.copy()`** - Never create User objects with all properties
5. **FOLLOW established patterns** - Check existing refactored controllers for examples

### **SHARED UTILITIES (adopt these in all new code)**
- **Utilities available**: BaseViewController, AlertPresenter, UIButton+Factory, User+Copy
- **Reality check (2026-07)**: these utilities exist and are the standard for new
  work, but adoption across the ~124k-line iOS codebase is partial — there are
  still ~46 files using `UIAlertController` directly and ~186 manual
  `UIButton(type:)` sites being migrated. Use the utilities in anything you touch;
  don't assume every existing controller already does.

## Table of Contents
1. [Project Overview](#project-overview)
2. [Architecture](#architecture)
3. [Code Reuse Architecture](#code-reuse-architecture)
4. [Mandatory Development Patterns](#mandatory-development-patterns)
5. [Tech Stack](#tech-stack)
6. [Project Structure](#project-structure)
7. [Backend Details](#backend-details)
8. [iOS Frontend Details](#ios-frontend-details)
9. [Database Schema](#database-schema)
10. [Authentication Flow](#authentication-flow)
11. [API Endpoints](#api-endpoints)
12. [Known Issues & Solutions](#known-issues--solutions)
13. [Recent Feature Implementations](#recent-feature-implementations)
14. [Deployment Guide](#deployment-guide)
15. [Development Workflow](#development-workflow)
16. [Code Style Guidelines](#code-style-guidelines)
17. [Testing Strategy](#testing-strategy)
18. [Troubleshooting Guide](#troubleshooting-guide)

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
- **iOS App**: Native Swift/UIKit with mandatory BaseViewController pattern
- **Deployment**: Google Cloud Run (containerized)

### Place Data Model — Normalized (July 2026)

**Places are normalized around one canonical venue record.** Do not read or write venue/social data directly on legacy `places` docs.

- **`globalPlaces` collection** = the canonical venue record: venue fields (`name`, `address`, `location`, `category`; `googleData.{rating, userRatingsTotal, priceLevel, openingHours, website, phone}`) and global social data (`likes[]`, `likesCount`, `commentsCount`). One doc per real-world venue, deduped by `deduplicationKey`/`googlePlaceId`.
- **`places` collection** = thin per-user save records referencing the venue via `globalPlaceId`, holding per-user data (`addedBy`, `circleId`, `privacy`, `privateNotes`, `publicNotes`, `tags`, `customCategoryId`, `photos`) plus a denormalized query cache (`name`, `address`, `location`, `geohash`, `category`) used by geo/search list queries.
- **`placeComments`** are keyed by `globalPlaceId` (with `placeId` kept for legacy readers).
- Every save path must stamp `globalPlaceId` via `ensureGlobalPlaceLink` (`backend/services/globalPlaceResolver.js`).
- Read endpoints merge venue + social data over the save doc via `getGlobalSocial`/`fetchGlobalSocialMap`/`overlayVenueFields` in `firebasePlaceController.js`; the API `Place` shape seen by iOS is unchanged.
- Venue edits (name, address, rating refresh) go through `propagateVenueUpdates`: canonical record updated once, cache fields synced to the venue's other copies. A venue correction by one saver is visible to all savers — intended.
- Likes toggle in ONE transaction on the globalPlaces doc (`likePlace`). Never fan out social writes across copies.
- Migration scripts (idempotent, support `DRY_RUN=true`): `scripts/backfill-global-place-links.js`, `scripts/migrate-social-to-global.js`, `scripts/strip-place-venue-fields.js` (run last, after soak).
- `placeTransitionService.js` and its `USE_GLOBAL_PLACES_*` env flags, plus `userPlaceRelations`, are legacy/dormant (the media subsystem still uses `userPlaceRelations`); do not build on them.

## Code Reuse Architecture

**⚠️ CRITICAL: The Circles app has undergone comprehensive refactoring to eliminate code redundancy. All new development MUST follow these established patterns.**

### **Utility Framework Overview**

The app provides a set of shared utilities that new code should use:

1. **BaseViewController** (`Controllers/Base/BaseViewController.swift`)
2. **AlertPresenter** (`Utilities/AlertPresenter.swift`)
3. **UIButton+Factory** (`Extensions/UIButton+Factory.swift`)
4. **User+Copy** (`Extensions/User+Copy.swift`)

### **Current State (2026-07, honest)**
- **iOS codebase**: ~124k lines of Swift across ~271 files.
- The four utilities above are the **standard for new work**, but adoption is
  **partial** — earlier "74% reduction / all 49 controllers refactored / 7,562
  lines" claims in this doc were aspirational and inaccurate; they've been removed.
- Some very large controllers are being broken up (Wave 4): the home, add-place,
  and profile controllers were each split from ~5–9k-line single files into a
  smaller core plus focused sibling files (`+Map`, `+Search`, `+TableView`, etc.).
- Known cleanup still in progress: ~46 files use `UIAlertController` directly
  (should use `AlertPresenter`) and ~186 `UIButton(type:)` sites (should use the
  factory). Don't assume an existing controller already follows the patterns.

## Mandatory Development Patterns

### **1. BaseViewController Inheritance**

**❌ NEVER DO THIS:**
```swift
class MyViewController: UIViewController {
    var hasLoadedData = false
    let loadingIndicator = UIActivityIndicatorView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }
    
    // 50+ lines of boilerplate...
}
```

**✅ ALWAYS DO THIS:**
```swift
class MyViewController: BaseViewController {
    override var enablesPullToRefresh: Bool { true }
    override var emptyStateMessage: String? { "No data available" }
    
    override func loadData(completion: (() -> Void)? = nil) {
        // Your data loading logic
        completion?()
    }
}
```

### **2. UIButton Factory Methods**

**❌ NEVER DO THIS:**
```swift
private let saveButton: UIButton = {
    let button = UIButton(type: .system)
    button.setTitle("Save", for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.backgroundColor = Constants.Colors.primary
    button.layer.cornerRadius = 6
    button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.heightAnchor.constraint(equalToConstant: 50).isActive = true
    return button
}()
```

**✅ ALWAYS DO THIS:**
```swift
private lazy var saveButton = UIButton.primaryButton(title: "Save")
```

### **3. AlertPresenter Usage**

**❌ NEVER DO THIS:**
```swift
let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
alert.addAction(UIAlertAction(title: "OK", style: .default))
present(alert, animated: true)
```

**✅ ALWAYS DO THIS:**
```swift
showError(error)
// or
AlertPresenter.showError(error, from: self)
```

### **4. User.copy() Method**

**❌ NEVER DO THIS:**
```swift
self.user = User(
    id: user.id,
    email: user.email,
    displayName: user.displayName,
    // ... 20+ more properties ...
    connectionDirection: "outgoing"
)
```

**✅ ALWAYS DO THIS:**
```swift
self.user = user.copy(connectionDirection: "outgoing")
```

### **5. Common Patterns Examples**

Check these refactored files as examples:
- `AllUsersListViewController_Refactored.swift` - Network data loading
- `ConversationsListViewController_Refactored.swift` - Real-time updates
- `ProfileViewController.swift` - User management
- `LoginViewController.swift` - Authentication flow

### **Utility Reference Guide**

#### **BaseViewController Configuration**
```swift
// Available configuration options:
override var showsLoadingIndicator: Bool { true }
override var enablesPullToRefresh: Bool { false }
override var emptyStateMessage: String? { nil }
override var loadsDataOnViewDidLoad: Bool { true }
override var reloadsDataOnAppear: Bool { false }
```

#### **UIButton Factory Methods**
```swift
// Primary buttons
UIButton.primaryButton(title: "Save")
UIButton.secondaryButton(title: "Cancel")
UIButton.dangerButton(title: "Delete")

// Small action buttons
UIButton.smallActionButton(title: "Follow", style: .primary)

// Icon buttons
UIButton.iconButton(systemName: "star.fill")

// Social login
UIButton.googleSignInButton()
UIButton.facebookSignInButton()
UIButton.appleSignInButton()
```

#### **AlertPresenter Methods**
```swift
// Error handling
showError(error)
showError("Custom message")

// Success messages
showSuccess("Operation completed")

// Confirmations
showConfirmation(title: "Delete?", message: "Are you sure?") {
    // Confirm action
}

// Loading states
let loading = AlertPresenter.showLoading(from: self)
// Later: loading.dismiss(animated: true)
```

#### **User.copy() Examples**
```swift
// Single property updates
user.copy(isFollowing: true)
user.copy(connectionStatus: "pending")

// Multiple properties
user.copy(
    connectionStatus: "connected",
    connectionDirection: "incoming"
)

// Convenience methods
user.withConnectionStatus("accepted")
user.withFollowingStatus(true)
user.withFollowerCounts(followers: 100, following: 50)
```

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
- **Architecture**: BaseViewController pattern with Service/Manager layers
- **Code Reuse**: Shared utility patterns (BaseViewController, AlertPresenter, factories) — standard for new code, adoption partial
- **Networking**: URLSession with custom APIService
- **Image Loading**: Custom ImageService with caching
- **Authentication**: Firebase SDK + custom AuthService
- **Push Notifications**: Firebase Cloud Messaging

### **Info.plist Configuration (Important)**

**Hybrid Info.plist management (verified against project.pbxproj 2026-08-27):**
- Main app: `GENERATE_INFOPLIST_FILE = YES` **merged with** a manual
  `INFOPLIST_FILE = Circles-iOS-UIKit/Info.plist` — the manual file carries
  URL schemes, Facebook/Google keys, and privacy strings; generation fills in
  the INFOPLIST_KEY_* build settings. (The earlier "GENERATE_INFOPLIST_FILE =
  NO" claim in this doc was outdated.)
- App Clip: fully generated (no Info.plist file, all INFOPLIST_KEY_*).
- Widget/Share extensions (added 2026-08): generated, merged with minimal
  manual plists carrying only the `NSExtension` dict.

#### **Why Manual Management?**
When we added `UIBackgroundModes` for push notifications, it created conflicts with Xcode's auto-generation during distribution builds. Manual management was chosen as the solution.

#### **Required Info.plist Keys**
These keys MUST be present for successful distribution:
```xml
<key>CFBundleIdentifier</key>
<string>com.favcircles.circles</string>
<key>CFBundleExecutable</key>
<string>$(EXECUTABLE_NAME)</string>
<key>CFBundleName</key>
<string>$(PRODUCT_NAME)</string>
<key>CFBundlePackageType</key>
<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
<key>CFBundleShortVersionString</key>
<string>1.0</string>
<key>CFBundleVersion</key>
<string>1</string>
```

#### **Custom Configurations in Info.plist**
- **Background Modes**: `remote-notification`, `fetch`, `processing`
- **Facebook SDK**: App ID, Client Token, Display Name
- **Google Sign-In**: Reversed client ID URL scheme
- **URL Schemes**: Deep linking support
- **Privacy Descriptions**: Camera, Photos, Location, Contacts

#### **Important Notes**
- **Version Updates**: Must manually update `CFBundleShortVersionString` and `CFBundleVersion`
- **New Capabilities**: Require manual Info.plist edits
- **Distribution Errors**: Usually caused by missing required keys

#### **Future Consideration**
Switching back to auto-generated Info.plist would be more robust:
1. Set `GENERATE_INFOPLIST_FILE = YES`
2. Add capabilities through Xcode UI
3. Delete manual Info.plist
4. Use build settings for custom values

## Backend Configuration & Deployment

### **🚀 Cloud Run Deployment Configuration (Updated July 2025)**

#### **Port Configuration**
- **IMPORTANT**: Cloud Run dynamically assigns the PORT environment variable
- **Default**: PORT=8080 (not 3001 as in local development)
- **Server Configuration**: `app.listen(PORT, '0.0.0.0')` - binds to all interfaces
- **Dockerfile**: No EXPOSE directive needed - Cloud Run handles port exposure

#### **Deployment Script**
```bash
# Use deploy.sh for deployment
./deploy.sh

# Key deployment parameters:
--port=8080              # Explicitly set port for Cloud Run
--allow-unauthenticated  # Public API access
--memory=512Mi           # Memory allocation
--max-instances=100      # Auto-scaling limit
--concurrency=80         # Requests per instance
```

#### **Environment Variables**
Critical environment variables for Cloud Run:
- `NODE_ENV=production`
- `PORT` - Set automatically by Cloud Run
- `JWT_SECRET` - Required for authentication
- `JWT_EXPIRE=30d` - Token expiration
- `FIREBASE_PROJECT_ID` - Firebase project identifier
- `FIREBASE_STORAGE_BUCKET` - Storage bucket name

### **📧 Email Configuration (Updated July 2025)**

#### **Email Service Setup**
The app uses custom SMTP configuration for email delivery:

```javascript
// Email service configuration
EMAIL_SERVICE=custom
SMTP_HOST=mail.favcircles.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=wesley@favcircles.com
SMTP_PASS=[encrypted]
EMAIL_FROM_ADDRESS=wesley@favcircles.com
EMAIL_FROM_NAME=Circles
```

#### **Nodemailer Configuration**
- **Important Fix**: Use `nodemailer.createTransport()` (not `createTransporter`)
- **TLS Configuration**: `rejectUnauthorized: false` for self-signed certificates

#### **Email Test Endpoints**
Available test routes at `/api/email/*`:
- `GET /test-config` - Check email configuration
- `POST /test-send` - Send test email
- `POST /test-connection-request` - Test connection request email
- `POST /test-connection-accepted` - Test connection accepted email

#### **Testing Email**
```bash
# Use the provided test script
./test-email-simple.sh
```

## Recent Deployment Fixes (July 2025)

### **Port Configuration Issue**
- **Problem**: Server failed to start on Cloud Run with "PORT=3001" error
- **Root Cause**: Hardcoded port values and incorrect server binding
- **Solution**: 
  1. Updated server to use dynamic PORT: `const PORT = process.env.PORT || 8080`
  2. Bind to all interfaces: `app.listen(PORT, '0.0.0.0')`
  3. Added `--port=8080` to deployment script
  4. Removed hardcoded EXPOSE from Dockerfile

### **Nodemailer Import Error**
- **Problem**: `TypeError: nodemailer.createTransporter is not a function`
- **Root Cause**: Incorrect function name
- **Solution**: Changed all instances to `nodemailer.createTransport()`

### **Deployment Script**
The `deploy.sh` script includes:
- Automatic environment variable loading from .env
- Cloud Run deployment with proper configuration
- Post-deployment health check verification

## Known Issues & Solutions

### **Firestore Index Requirements**
- **Issue**: Suggestions query requires composite index
- **Error**: `FAILED_PRECONDITION: The query requires an index`
- **Solution**: 
  1. Click the URL in the error message to create index in Firebase Console
  2. Index configuration: `userId (ASC)`, `createdAt (DESC)`
  3. Wait 5-10 minutes for index to build

### **Authentication Token Expiration**
- **Issue**: iOS app loses authentication after token expires
- **Symptoms**: Repeated "No auth token available" errors
- **Solution**: Log out and log back in to refresh token

### **Image Storage URL Issues**
- **Issue**: `storage.circles-app.com` hostname not found
- **Cause**: Legacy storage URLs in database
- **Solution**: Update to use Firebase Storage URLs

## Moments Feature Implementation

### **Overview**
Moments (formerly called "Reels") is a multimedia content sharing feature that allows users to share short videos, photos, or social media links associated with specific places. This feature enhances place discovery by allowing users to share their experiences visually.

### **Key Components**

#### **1. Content Types**
- **Video Recording**: 15-second maximum, auto-compressed videos recorded in-app
- **Photo Capture**: Single photos taken directly or selected from library
- **Social Media Links**: TikTok, Instagram, YouTube videos embedded from URLs

#### **2. User Flow**
1. **Creating a Moment**:
   - Access via floating "+" button on home page Moments tab
   - Access via video button in user profile
   - Both entry points use `ContentUploadViewController` with "Share a Moment" UI
   - Select content type (record, photo, link, library)
   - Choose or search for associated place
   - Upload with automatic compression and optimization

2. **Viewing Moments**:
   - Home page "Moments" tab shows network-wide moments feed
   - Profile "Moments" tab shows user's created moments
   - Tap moment to view in `VideoDetailsViewController`
   - Support for likes, comments, and sharing

#### **3. Technical Implementation**

**iOS Controllers**:
- `ContentUploadViewController`: Main moment creation interface
- `VideoRecordingViewController`: In-app video recording (15 sec limit)
- `VideoLinkInputViewController`: Social media URL input
- `PlaceSearchViewController`: Place selection during creation
- `VideoDetailsViewController`: Full-screen moment viewing

**Backend Endpoints**:
- `POST /api/videos/upload/initiate`: Start upload process
- `POST /api/videos/:videoId/upload/complete`: Finalize upload
- `GET /api/videos/user/:userId`: Get user's moments
- `GET /api/videos/reels/feed`: Get moments feed
- `POST /api/videos/embed`: Add embedded social media video

**Data Models**:
- `PlaceVideo`: Core video/moment data structure
- `PlaceMoment`: Frontend wrapper with UI-specific properties
- Stored in Firestore `placeVideos` collection

#### **4. Compression & Optimization**
- Videos: 720p, 500kbps bitrate, 15 sec max
- Photos: 1080px max dimension, 0.7 JPEG quality
- Automatic thumbnail generation
- Progressive loading with preview images

#### **5. Privacy & Permissions**
- Moments inherit place privacy settings
- Camera and photo library permissions required
- Location permissions for place association

### **Recent Updates (January 2025)**
- Renamed "Reels" to "Moments" throughout the app
- Unified content creation flow between home and profile
- Improved compression for faster uploads
- Added support for photo moments alongside videos

## AI Interaction Memory

### Recent AI Assistant Interactions
- Fixed Cloud Run deployment port configuration issue (July 2025)
- Resolved nodemailer function naming error (July 2025)
- Successfully implemented Server-Sent Events (SSE) notification system in July 2025
- Added LinkedIn-style activity feed to home screen in January 2025
- Integrated real-time connection and messaging updates
- Improved performance by eliminating message polling
- Implemented unified real-time event infrastructure

### AI Assistant Guidelines Updates
- Reinforced importance of checking existing functionality before implementing new features
- Added more detailed debugging and deployment guidelines
- Enhanced documentation for backend and iOS development practices
- Created comprehensive architecture decision records
- Emphasized performance and scalability considerations

### Upcoming Focus Areas
- Explore GraphQL for more efficient data fetching
- Consider adding Redis caching layer
- Investigate Swift Concurrency (async/await) adoption
- Develop comprehensive unit and integration test suite
- Plan CI/CD pipeline implementation with GitHub Actions

## Notes for AI Assistants

### **🚨 CRITICAL REFACTORING REQUIREMENTS**

1. **ALWAYS check existing patterns** before implementing new features
2. **NEVER use UIViewController directly** - always inherit from BaseViewController
3. **NEVER create UIAlertController manually** - always use AlertPresenter
4. **NEVER create UIButton manually** - always use factory methods
5. **NEVER create User objects with all properties** - always use User.copy()
6. **ALWAYS follow the established patterns** in refactored controllers

### **Code Quality Standards Post-Refactoring**

- **Consistency**: BaseViewController is the pattern for new controllers (not yet universal)
- **Maintainability**: Utilities handle common functionality
- **Readability**: Factory methods make intent clear
- **Testability**: Standardized interfaces for testing
- **Performance**: shared utilities reduce per-controller boilerplate

### **Before Adding New Features**

1. Check if BaseViewController provides the functionality
2. Use UIButton factory methods for any buttons
3. Use AlertPresenter for any user feedback
4. Use User.copy() for any user object updates
5. Follow patterns in existing refactored controllers

### **Refactoring Status (2026-07)**

- ✅ **4 shared utilities** created (BaseViewController, AlertPresenter, UIButton
  factory, User.copy) — use them in all new code.
- 🚧 **Adoption is partial** — ~46 files still use `UIAlertController` directly and
  ~186 `UIButton(type:)` sites remain; migration is ongoing.
- 🚧 **God-object breakup in progress** — home/add-place/profile controllers split
  into a core + focused sibling files; `firebasePlaceController.js` still to do.
- ⚠️ The earlier "74% reduction / 7,562 lines / all 49 refactored" claims were
  inaccurate and have been corrected throughout this doc.