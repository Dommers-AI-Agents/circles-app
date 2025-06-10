# Adding Firebase Dependencies to Circles iOS

Since Xcode project files (.pbxproj) are complex and should be edited through Xcode, please follow these steps to add Firebase SDK:

## Steps to Add Firebase SDK in Xcode:

1. **Open your project in Xcode**
   - Open `Circles-iOS.xcodeproj` in Xcode

2. **Add Firebase Package**
   - Go to File → Add Package Dependencies...
   - Enter the Firebase repository URL: `https://github.com/firebase/firebase-ios-sdk`
   - Click "Add Package"
   - Version rule: Up to Next Major Version: 11.2.0

3. **Select Firebase Products**
   When prompted, select these Firebase products:
   - ✅ FirebaseAnalytics
   - ✅ FirebaseAuth
   - ✅ FirebaseFirestore
   - ✅ FirebaseStorage
   - Click "Add Package"

4. **Verify Installation**
   - In the project navigator, you should see "Package Dependencies" with Firebase listed
   - Build the project to ensure everything compiles

## Alternative: Command Line (if you have xcodeproj tools installed)

```bash
# This requires ruby and xcodeproj gem
gem install xcodeproj

# Then run the Ruby script to add dependencies
ruby add_firebase_to_xcode.rb
```

## Already Configured Files:
- ✅ GoogleService-Info.plist is already in the project
- ✅ CirclesApp.swift already has Firebase import and configuration
- ✅ URL schemes are configured for authentication

Once you've added the Firebase SDK, the build errors should be resolved!