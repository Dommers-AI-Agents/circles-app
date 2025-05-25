# Google Sign-In Implementation Guide

To implement Google Sign-In in this project, follow these steps:

## 1. Add the Google Sign-In SDK

### Option 1: Swift Package Manager (Recommended)

1. In Xcode, go to File > Add Package Dependencies
2. Enter the URL: `https://github.com/google/GoogleSignIn-iOS`
3. Choose the latest version and click "Add Package"
4. Select both "GoogleSignIn" and "GoogleSignInSwift" products and click "Add Package"

### Option 2: CocoaPods

If you prefer CocoaPods, add the following to your Podfile:

```ruby
pod 'GoogleSignIn'
```

Then run:
```bash
pod install
```

## 2. Configure Google Sign-In

1. Create a new project in the Google Cloud Console (https://console.cloud.google.com/)
2. Enable the Google Sign-In API
3. Create OAuth 2.0 credentials:
   - Web application type for the backend
   - iOS application type for the iOS client
4. Add your Bundle ID to the iOS credentials
5. Download the `GoogleService-Info.plist` file and add it to your project
6. Add the custom URL scheme to your Info.plist file:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>YOUR_REVERSED_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

Replace `YOUR_REVERSED_CLIENT_ID` with the value of the `REVERSED_CLIENT_ID` key from your `GoogleService-Info.plist`.

## 3. Update AppDelegate

Once you've added the SDK, update the AppDelegate to handle Google Sign-In callbacks:

```swift
import GoogleSignIn

func application(
  _ app: UIApplication,
  open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
) -> Bool {
  var handled = GIDSignIn.sharedInstance.handle(url)
  if !handled {
    // Handle other custom URL types if needed
  }
  return handled
}
```

## 4. Update SocialAuthService

Replace the mock implementation with actual Google Sign-In:

```swift
import GoogleSignIn

func signInWithGoogle(from viewController: UIViewController, completion: @escaping (Result<User, Error>) -> Void) {
    self.completionHandler = completion
    
    // Get GoogleSignIn configuration
    guard let clientID = FirebaseApp.app()?.options.clientID else {
        let error = NSError(domain: "com.circles.auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "No client ID found for Google Sign-In"])
        completion(.failure(error))
        return
    }
    
    // Create configuration object
    let config = GIDConfiguration(clientID: clientID)
    
    // Perform sign-in
    GIDSignIn.sharedInstance.signIn(
        with: config,
        presenting: viewController
    ) { [weak self] user, error in
        // Check for errors
        if let error = error {
            completion(.failure(error))
            return
        }
        
        // Get ID token
        guard let user = user,
              let idToken = user.authentication.idToken else {
            let error = NSError(domain: "com.circles.auth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token from Google Sign-In"])
            completion(.failure(error))
            return
        }
        
        // Send token to backend via the AuthService
        AuthService.shared.loginWithSocialProvider(provider: "google", token: idToken) { result in
            completion(result)
        }
    }
}
```

## 5. Testing

To test Google Sign-In:

1. Make sure you're using a real device or a simulator with a Google account signed in
2. Run the app and try signing in with Google
3. The first time, you should see a Google OAuth consent screen
4. After approval, the SDK will handle the authentication flow

## Additional Information

- For production, make sure to set up a proper OAuth consent screen in the Google Cloud Console
- You may want to consider requesting additional scopes (email, profile, etc.) based on your app's needs
- Always follow Google's branding guidelines for the Sign-In button