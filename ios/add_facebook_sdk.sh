#!/bin/bash

# Script to add Facebook SDK to the Circles iOS project

echo "Adding Facebook SDK to Circles iOS project..."

# Navigate to the project directory
cd "$(dirname "$0")"

# Update the Package.resolved file to include Facebook SDK
echo "Note: You need to manually add the Facebook SDK in Xcode:"
echo "1. Open Circles-iOS.xcodeproj in Xcode"
echo "2. Go to File > Add Package Dependencies"
echo "3. Enter: https://github.com/facebook/facebook-ios-sdk"
echo "4. Select version 16.0.0 or later"
echo "5. Choose these packages:"
echo "   - FacebookCore"
echo "   - FacebookLogin"
echo ""
echo "After adding the packages, update Info.plist with your Facebook App ID:"
echo "- Replace YOUR_FACEBOOK_APP_ID with your actual App ID"
echo "- Replace fbYOUR_FACEBOOK_APP_ID with fb followed by your App ID"
echo "- Replace YOUR_FACEBOOK_CLIENT_TOKEN with your Client Token"

# Make the script executable
chmod +x "$0"

echo "Script complete!"