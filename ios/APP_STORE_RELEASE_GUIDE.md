# Circles App - App Store Release Guide

## Pre-Release Checklist ✓

- [x] Build number incremented to 2
- [x] NSAllowsArbitraryLoads security fixed
- [x] SKIncludesAppleSignInWithPurchase added
- [x] All privacy descriptions present
- [x] Subscription implementation complete
- [x] Backend webhook configured

## Part 1: TestFlight Testing (Recommended First)

### Step 1: Archive and Upload

1. **Open Xcode**
   ```bash
   cd /Users/wesleysgroi/circles-app/ios
   open Circles-iOS.xcworkspace
   ```

2. **Select Generic iOS Device**
   - In Xcode toolbar, change scheme from simulator to "Any iOS Device (arm64)"

3. **Archive the App**
   - Menu: Product → Archive
   - Wait for build to complete (5-10 minutes)

4. **Upload to App Store Connect**
   - Organizer window opens automatically
   - Select your archive → "Distribute App"
   - Choose "App Store Connect" → "Upload"
   - Let Xcode handle signing automatically
   - Upload (takes 2-5 minutes)

### Step 2: Configure TestFlight

1. **Log in to App Store Connect**
   - Go to [App Store Connect](https://appstoreconnect.apple.com)
   - Select your app

2. **TestFlight Tab**
   - Build will appear after 10-30 minutes (Apple processing)
   - Once processed, click on the build

3. **Add Test Information**
   - What to Test: "Test subscription purchases and premium features"
   - Test groups: Create "Internal Testing" group

4. **Add Internal Testers**
   - Add yourself and team members
   - They'll receive TestFlight invitation emails

### Step 3: Test Subscriptions in TestFlight

1. **Install TestFlight App**
   - Download from App Store on test device
   - Accept invitation email

2. **Test Purchase Flow**
   ```
   Real Testing (with TestFlight):
   - Uses REAL Apple ID (not sandbox)
   - Charges go to a REAL credit card
   - Apple refunds TestFlight purchases within 14 days
   - Most realistic testing experience
   ```

3. **Test These Scenarios**
   - Fresh install → Purchase monthly subscription
   - Purchase annual subscription
   - Let subscription expire (wait 1 month)
   - Restore purchases after reinstall
   - Cancel subscription in Settings

## Part 2: Sandbox Testing (Alternative)

### Create Sandbox Tester
1. App Store Connect → Users and Access → Sandbox Testers
2. Create new tester with fake email
3. Sign out of App Store on device
4. Run app from Xcode
5. Sign in with sandbox account when purchasing

### Sandbox Timeline
- Monthly: Renews every 5 minutes (6 times max)
- Annual: Renews every hour
- Perfect for quick testing

## Part 3: App Store Release

### Step 1: Prepare for Submission

1. **App Store Connect → App Store Tab**

2. **Version Information**
   - Version: 1.0
   - What's New: "Initial release"

3. **App Information**
   ```
   Description:
   Circles is your personal recommendation engine. Create curated collections 
   of your favorite places and share them with your network.
   
   Keywords: recommendations, places, restaurants, social, circles, collections
   
   Support URL: https://favcircles.com/support
   Marketing URL: https://favcircles.com
   ```

4. **Screenshots** (Required sizes)
   - 6.7" (iPhone 15 Pro Max): 1290 × 2796
   - 6.5" (iPhone 14 Plus): 1284 × 2778  
   - 5.5" (iPhone 8 Plus): 1242 × 2208

5. **App Preview** (Optional)
   - 15-30 second video
   - Show key features

### Step 2: Configure Pricing

1. **Pricing and Availability**
   - Price: Free
   - Available in all territories

2. **In-App Purchases**
   - Should auto-populate from your products
   - If not, add manually:
     - Monthly: $2.99
     - Annual: $29.99

### Step 3: Configure Subscriptions

1. **App Store Connect → Subscriptions**
   - Create Subscription Group: "Circles Premium"
   - Add products with localized descriptions

2. **Server Notifications**
   - URL: `https://circles-backend-196924649787.us-central1.run.app/api/users/subscription/webhook`
   - Version: Version 2
   - Enable all notification types

### Step 4: Submit for Review

1. **Review Information**
   ```
   Demo Account:
   Email: demo@favcircles.com
   Password: [create demo account]
   
   Notes: Premium features require subscription. 
   Test with sandbox account for purchases.
   ```

2. **Export Compliance**
   - Uses encryption: Yes (HTTPS only)
   - Exempt from export: Yes

3. **Submit for Review**
   - Click "Add for Review"
   - Submit to Apple Review

## Timeline

- **TestFlight Processing**: 10-30 minutes
- **App Review**: 24-48 hours typically
- **Expedited Review**: 1-6 hours (if needed)

## Post-Release

### Monitor Subscriptions

1. **App Analytics**
   - Sales and Trends
   - Subscription metrics

2. **Backend Monitoring**
   ```bash
   # View subscription logs
   gcloud run logs read --service=circles-backend --limit=50 | grep -i subscription
   
   # View webhook activity  
   gcloud run logs read --service=circles-backend --limit=50 | grep -i webhook
   ```

3. **Customer Support**
   - Monitor reviews
   - Handle subscription issues
   - Process refund requests

## Common Issues

### "Missing Compliance" Error
- Already handled with ITSAppUsesNonExemptEncryption

### Subscription Not Showing
- Ensure products approved in App Store Connect
- Wait 24 hours after creation

### Webhook Not Receiving
- Verify URL in App Store Connect
- Check Cloud Run logs
- Ensure APPLE_SHARED_SECRET is set

## Emergency Contacts

- **App Review Issues**: Use Resolution Center in App Store Connect
- **Expedited Review**: Available for critical issues
- **Developer Support**: https://developer.apple.com/support/

## Ready to Submit!

Your app is now ready for TestFlight testing and App Store submission. Start with TestFlight to ensure everything works perfectly before the public release.