# Circles App - iOS Subscription Testing Guide

This guide covers how to test the iOS subscription system for the Circles app.

## Prerequisites

1. **App Store Connect Access**
   - Access to the app's App Store Connect account
   - Ability to create sandbox tester accounts

2. **Test Device**
   - iOS device or simulator
   - Signed out of regular App Store account

3. **Backend Configuration**
   - `APPLE_SHARED_SECRET` environment variable set
   - Backend deployed with subscription endpoints

## Setting Up Sandbox Testing

### 1. Create Sandbox Tester Account

1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **Users and Access** → **Sandbox Testers**
3. Click **+** to create a new tester
4. Fill in the required fields:
   - Email: Use a unique email (e.g., `circles.test1@example.com`)
   - Password: Create a strong password
   - First Name, Last Name
   - Country/Region: Match your app's availability

### 2. Configure Test Device

1. On your iOS device, go to **Settings** → **App Store**
2. Scroll to bottom and tap **Sign Out** (if signed in)
3. In Xcode, build and run the app on your test device
4. When prompted to sign in for purchases, use sandbox tester credentials

## Testing Purchase Flows

### Monthly Subscription ($2.99/month)

1. **Initial Purchase**
   ```
   Product ID: com.favcircles.circles.premium.subscription.monthly
   ```
   - Navigate to any premium feature (e.g., create 4th circle)
   - Tap "Subscribe" on the paywall
   - Confirm purchase with sandbox account
   - Verify subscription status updates in app

2. **Verify Backend Sync**
   - Check backend logs for receipt verification
   - Confirm user document in Firestore shows:
     - `subscriptionStatus: "active"`
     - `subscriptionExpiryDate` set
     - `appleOriginalTransactionId` populated

### Annual Subscription ($29.99/year)

1. **Initial Purchase**
   ```
   Product ID: com.favcircles.circles.premium.subscription.annual
   ```
   - Same flow as monthly, but select annual option
   - Verify correct pricing displayed

## Testing Subscription States

### 1. Active Subscription
- Purchase subscription
- Verify all premium features are accessible:
  - Unlimited circles
  - Unlimited places per circle
  - Export functionality
  - No watermarks on shares

### 2. Expired Subscription
- In sandbox, subscriptions auto-renew every 5 minutes
- Wait for expiration or use App Store Connect to cancel
- Verify app reverts to free tier limits

### 3. Restore Purchases
1. Delete app and reinstall
2. Sign in with same account
3. Navigate to subscription screen
4. Tap "Restore Purchases"
5. Verify subscription status is restored

### 4. Grace Period
- Simulate payment failure in sandbox
- Verify user maintains access during grace period
- Check `subscriptionStatus: "grace_period"` in backend

## Testing Webhook Notifications

### 1. Configure Webhook URL
In App Store Connect:
1. Navigate to your app
2. Go to **App Store Server Notifications**
3. Set Production URL: `https://api.favcircles.com/api/users/subscription/webhook`
4. Set Sandbox URL: Same as production

### 2. Test Notification Types
Monitor backend logs for these notifications:
- `SUBSCRIBED` - Initial purchase
- `DID_RENEW` - Successful renewal
- `DID_FAIL_TO_RENEW` - Payment failure
- `EXPIRED` - Subscription expired
- `GRACE_PERIOD_EXPIRED` - Grace period ended

### 3. Verify Updates
After each notification, check Firestore for updated:
- `subscriptionStatus`
- `lastWebhookReceived`
- `subscriptionExpiryDate`

## Common Test Scenarios

### Scenario 1: New User Journey
1. Launch app as new user
2. Create account
3. Try to create 4th circle → See paywall
4. Purchase monthly subscription
5. Create unlimited circles
6. Let subscription expire
7. Verify reverts to 3-circle limit

### Scenario 2: Upgrade Flow
1. Use app as free user
2. Hit any premium limit
3. View paywall with both options
4. Purchase annual subscription
5. Verify all features unlocked

### Scenario 3: Payment Issues
1. Purchase subscription
2. Update payment method to invalid card
3. Wait for renewal failure
4. Verify grace period status
5. Fix payment method
6. Verify subscription reactivates

## Troubleshooting

### Receipt Verification Fails
- Check `APPLE_SHARED_SECRET` is set correctly
- Verify using correct environment (sandbox vs production)
- Check receipt data is base64 encoded

### Webhook Not Received
- Verify webhook URL is accessible
- Check Cloud Run logs for incoming requests
- Ensure URL is set in App Store Connect

### Subscription Status Not Updating
- Check `appleOriginalTransactionId` is stored
- Verify webhook processing logic
- Check for Firestore write errors

## Sandbox Testing Timeline

In sandbox environment:
- **Monthly subscriptions** renew every 5 minutes
- **Annual subscriptions** renew every hour
- Maximum 6 renewals before auto-cancel

This accelerated timeline helps test:
- Renewal flows
- Expiration handling
- Grace period scenarios

## Production Deployment Checklist

Before going live:

1. ✅ Set `APPLE_SHARED_SECRET` in production environment
2. ✅ Configure production webhook URL in App Store Connect
3. ✅ Test with real Apple ID (not sandbox)
4. ✅ Verify receipt validation works in production mode
5. ✅ Monitor initial production purchases closely
6. ✅ Set up alerts for webhook failures

## Support & Debugging

### Useful Backend Endpoints

1. **Check Subscription Status**
   ```
   GET /api/users/subscription/status
   Authorization: Bearer {token}
   ```

2. **Verify Receipt Manually**
   ```
   POST /api/users/subscription/verify
   Authorization: Bearer {token}
   Body: { "receipt": "{base64_receipt_data}" }
   ```

### Debug Commands

View subscription logs:
```bash
gcloud run logs read --service=circles-backend --limit=100 | grep -i subscription
```

View webhook logs:
```bash
gcloud run logs read --service=circles-backend --limit=100 | grep -i webhook
```

## Contact

For issues with subscription setup or testing:
- Check backend logs in Google Cloud Console
- Review Firestore user documents
- Contact Apple Developer Support for App Store issues