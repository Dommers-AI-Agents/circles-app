# Add Connection Feature - Process Flow

## Overview
The Circles app uses a deep link-based connection system that allows users to share connection invites through any messaging platform.

## Process Flow Diagram

```mermaid
flowchart TD
    Start([User wants to add connection])
    Start --> AddButton[User taps 'Add Connection' button<br/>in MyNetworkViewController]
    
    AddButton --> Generate[NetworkManager.shareConnectionInvite<br/>generates deep link]
    Generate --> ShareSheet[iOS Share Sheet appears with:<br/>'Connect with me on Circles!'<br/>+ Deep link URL]
    
    ShareSheet --> Share[User shares via any app<br/>SMS, WhatsApp, Email, etc.]
    
    Share --> Receive[Recipient receives link:<br/>circles://connect/{userId}]
    
    Receive --> ClickLink[Recipient clicks link]
    
    ClickLink --> CheckApp{App installed?}
    CheckApp -->|No| AppStore[Redirect to App Store]
    CheckApp -->|Yes| OpenApp[App opens with deep link]
    
    OpenApp --> SceneDelegate[SceneDelegate handles URL]
    SceneDelegate --> CheckAuth{User logged in?}
    
    CheckAuth -->|No| StorePending[Store pending connection<br/>in UserDefaults]
    StorePending --> LoginPrompt[Show login screen]
    LoginPrompt --> Login[User logs in]
    Login --> ProcessPending[Process pending connection]
    
    CheckAuth -->|Yes| HandleInvite[NetworkManager.handleConnectionInvite]
    ProcessPending --> HandleInvite
    
    HandleInvite --> Validate{Validate connection}
    Validate -->|Invalid| ShowError[Show error banner:<br/>- Can't connect to self<br/>- Already connected<br/>- Invalid invite]
    
    Validate -->|Valid| SendRequest[Send connection request<br/>with autoAccept: true]
    
    SendRequest --> Backend[Backend API:<br/>POST /connections/invite]
    
    Backend --> CreateConnection[Create connection with<br/>status: 'accepted']
    
    CreateConnection --> Success[Show success banner:<br/>'Connected with {userName}!']
    
    Success --> UpdateUI[Update NetworkManager state<br/>Refresh connections list]
    
    UpdateUI --> End([Connection established])
```

## Key Components

### 1. **Initiation** (MyNetworkViewController)
- Location: `ios/Circles-iOS-UIKit/Controllers/Network/MyNetworkViewController.swift:131`
- User taps the "Add Connection" button (person.badge.plus icon)

### 2. **Link Generation** (NetworkManager)
- Location: `ios/Circles-iOS-UIKit/Managers/NetworkManager.swift:607`
- Generates deep link format: `circles://connect/{userId}`
- Creates shareable message with the link

### 3. **Deep Link Handling** (SceneDelegate)
- Location: `ios/Circles-iOS-UIKit/App/SceneDelegate.swift:66`
- Intercepts the deep link when recipient clicks
- Routes to appropriate handler based on URL scheme

### 4. **Connection Processing** (NetworkManager)
- Location: `ios/Circles-iOS-UIKit/Managers/NetworkManager.swift:675`
- Validates the connection request
- Sends API request with `autoAccept: true` flag

### 5. **Backend Processing**
- Location: `backend/routes/connectionRoutes.js`
- Creates connection record with 'accepted' status
- Bypasses normal pending state for invite links

## Connection States

1. **Pending** - Normal connection request (not used with invite links)
2. **Accepted** - Connection established (automatic with invite links)
3. **Blocked** - User has blocked the connection

## Error Handling

The system handles several error cases:
- **Self-connection**: Can't connect to your own account
- **Duplicate connection**: Already connected to this user
- **Invalid invite**: Malformed or expired invite link
- **Not logged in**: Stores pending connection for later processing

## Security Features

1. **User ID Validation**: Ensures valid user IDs in deep links
2. **Authentication Required**: Must be logged in to create connections
3. **Duplicate Prevention**: Backend prevents duplicate connections
4. **Auto-Accept Flag**: Only valid for invite-based connections