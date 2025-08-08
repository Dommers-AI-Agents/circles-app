# App Store Connect - Subscription Setup Guide

## Fix for "Loaded 0 subscription products"

This error means the subscription products haven't been created in App Store Connect yet. Here's how to fix it:

## Step 1: Create Subscription Group

1. **Log in to App Store Connect**
   - Go to [App Store Connect](https://appstoreconnect.apple.com)
   - Select your app: **Circles**

2. **Navigate to Subscriptions**
   - In the left sidebar: **Monetization** → **Subscriptions**
   - Click **Create** (+ button)

3. **Create Subscription Group**
   - Reference Name: `Circles Premium`
   - Click **Create**

## Step 2: Add Subscription Products

### Monthly Subscription

1. **Click "Create" in your subscription group**

2. **Product Details:**
   - Reference Name: `Circles Premium Monthly`
   - Product ID: `com.favcircles.circles.premium.subscription.monthly`
   - Duration: 1 Month
   - Click **Create**

3. **Pricing:**
   - Click **Add Pricing**
   - Base Country: United States
   - Price: $2.99
   - Click **Next**
   - Review other countries (auto-calculated)
   - Click **Create**

4. **Subscription Display Name:**
   - Click **Add Localization**
   - Language: English (U.S.)
   - Display Name: `Premium Monthly`
   - Description: `Unlock unlimited circles, places, and premium features`
   - Click **Save**

### Annual Subscription

1. **Click "Create" again in your subscription group**

2. **Product Details:**
   - Reference Name: `Circles Premium Annual`
   - Product ID: `com.favcircles.circles.premium.subscription.annual`
   - Duration: 1 Year
   - Click **Create**

3. **Pricing:**
   - Click **Add Pricing**
   - Base Country: United States
   - Price: $29.99
   - Click **Next**
   - Review other countries
   - Click **Create**

4. **Subscription Display Name:**
   - Click **Add Localization**
   - Language: English (U.S.)
   - Display Name: `Premium Annual`
   - Description: `Best value! Save 16% with annual billing`
   - Click **Save**

## Step 3: Configure Free Trial (Optional)

For Monthly Subscription:
1. Click on the monthly subscription
2. **Introductory Offer** → **Create**
3. Type: Free Trial
4. Duration: 7 Days
5. Countries: All Countries
6. Click **Create**

## Step 4: Configure Server Notifications

1. **Back to main subscription group page**
2. Click **App Store Server Notifications**
3. **Production Server URL:**
   ```
   https://circles-backend-196924649787.us-central1.run.app/api/users/subscription/webhook
   ```
4. **Sandbox Server URL:** (same as production)
   ```
   https://circles-backend-196924649787.us-central1.run.app/api/users/subscription/webhook
   ```
5. **Version:** Version 2
6. Click **Save**

## Step 5: Wait for Processing

⏰ **IMPORTANT**: After creating products, you must wait:
- **Sandbox Testing**: 10-30 minutes
- **Production**: Up to 24 hours

The products won't appear in your app until Apple processes them.

## Step 6: Test in Sandbox

After products are processed:

1. **Create Sandbox Tester**
   - Users and Access → Sandbox Testers
   - Create new tester account

2. **Test in Xcode**
   - Run app from Xcode
   - Products should now load
   - Test purchase with sandbox account

## Troubleshooting

### Still showing "0 products"?

1. **Check Product IDs match exactly:**
   - `com.favcircles.circles.premium.subscription.monthly`
   - `com.favcircles.circles.premium.subscription.annual`

2. **Verify app bundle ID:**
   - Must be: `com.favcircles.circles`

3. **Check Agreements:**
   - App Store Connect → Agreements, Tax, and Banking
   - Ensure "Paid Applications" agreement is active

4. **Wait longer:**
   - Products can take up to 24 hours to propagate

### Debug in iOS App

Add this logging to see what's happening:
```swift
// In SubscriptionService.swift loadProducts()
do {
    print("🔍 Requesting products: \(productIds)")
    let storeProducts = try await Product.products(for: productIds)
    print("📦 Received \(storeProducts.count) products")
    for product in storeProducts {
        print("  - \(product.id): \(product.displayName) - \(product.displayPrice)")
    }
} catch {
    print("❌ StoreKit error: \(error)")
}
```

## Backend Fix Applied ✅

I've already fixed the backend error:
- Added user ID validation to prevent 500 errors
- Deployed the fix
- Backend now properly handles missing user IDs

## Next Steps

1. Complete the App Store Connect setup above
2. Wait for products to process (10-30 min)
3. Test with sandbox account
4. Once working, submit to TestFlight/App Store

The subscription system is fully implemented and ready - you just need to create the products in App Store Connect!