# Add Firebase Packages to Xcode

## Steps to Add Firebase SDK

1. **Open the project in Xcode**:
   ```bash
   open Circles-iOS.xcodeproj
   ```

2. **Add Firebase Package**:
   - Select the project in the navigator (top blue icon)
   - Select the "Circles-iOS" project (not target)
   - Click on "Package Dependencies" tab
   - Click the "+" button
   - Enter: `https://github.com/firebase/firebase-ios-sdk`
   - Click "Add Package"
   - Wait for package resolution

3. **Select Firebase Products**:
   When prompted, select these products:
   - ✅ FirebaseAnalytics
   - ✅ FirebaseAuth
   - ✅ FirebaseCore
   - ✅ FirebaseFirestore (optional, for future use)
   
   Make sure to add them to the "Circles-iOS" target.

4. **Click "Add Package"** to finish

## Alternative: Command Line (if you have xcodeproj installed)

```bash
# Install xcodeproj if needed
gem install xcodeproj

# Run this Ruby script to add Firebase
ruby -e "
require 'xcodeproj'
project = Xcodeproj::Project.open('Circles-iOS.xcodeproj')
# Note: This is a simplified example - full implementation would be more complex
puts 'Please add Firebase packages through Xcode GUI for best results'
"
```

## After Adding Packages

Once packages are added, I'll uncomment all the Firebase code automatically.