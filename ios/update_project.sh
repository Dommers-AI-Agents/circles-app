#!/bin/bash

# Create symbolic link to entitlements file in the project directory
if [ ! -f "Circles-iOS-UIKit/Circles-iOS.entitlements" ]; then
  ln -s ../Circles-iOS.entitlements Circles-iOS-UIKit/Circles-iOS.entitlements
fi

# Update Info.plist to ensure proper bundle ID is used for Apple Sign in
INFOPLIST="Circles-iOS-UIKit/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.favcircles.circles" "$INFOPLIST"

# Print instructions for manual steps
echo "Please take these manual steps in Xcode:"
echo "1. Open Xcode and the Circles-iOS project"
echo "2. Select the project in the Navigator"
echo "3. Select the 'Circles-iOS' target"
echo "4. Go to the 'Signing & Capabilities' tab"
echo "5. Click the '+' button to add a capability"
echo "6. Add 'Sign In with Apple'"
echo "7. Make sure the entitlements file is properly linked"
echo "8. Clean and rebuild the project"