# Steps to Fix Apple Sign-In Issues

Based on the error we're seeing (`Authorization failed: Error Domain=AKAuthenticationError Code=-7026`), you'll need to complete the following steps in Xcode to properly enable Sign In with Apple:

## 1. Update the project configuration

1. Open Xcode and the Circles-iOS project
2. Select the project in the Navigator
3. Select the 'Circles-iOS' target
4. Go to the 'Signing & Capabilities' tab
5. Make sure you're signed in with your Apple Developer account
6. Ensure the correct Team is selected under Signing
7. Click the '+' button to add a capability
8. Add 'Sign In with Apple'

## 2. Configure entitlements

Make sure the entitlements file is properly linked:

1. In Xcode, go to the 'Build Settings' tab for your target
2. Search for "Code Signing Entitlements"
3. Set the path to `Circles-iOS.entitlements` or `Circles-iOS-UIKit/Circles-iOS.entitlements` 
   (whichever one Xcode can find)

## 3. Update bundle identifier

Ensure that your bundle identifier is consistently used across all files:

1. In the project settings, make sure the Bundle Identifier is properly set
2. It should match the one in the Info.plist (`com.favcircles.circles`)
3. This needs to match a registered App ID in your Apple Developer account

## 4. Clean and rebuild

1. Select Product > Clean Build Folder
2. Build and run the project again

## 5. Apple Developer Account Setup

If you're testing on a physical device, make sure your Apple Developer account is set up properly:

1. Log into the [Apple Developer Portal](https://developer.apple.com/)
2. Go to Certificates, Identifiers & Profiles
3. Register your app with the correct bundle identifier
4. Enable Sign In with Apple capability for your App ID
5. Create a provisioning profile that includes this capability

## Additional Troubleshooting

If Sign In with Apple still fails:

1. Check the Keychain Access app to make sure there are no conflicting certificates
2. Try testing on the simulator first, which has fewer signing requirements
3. Check Apple's system status page to make sure their authentication services are operational