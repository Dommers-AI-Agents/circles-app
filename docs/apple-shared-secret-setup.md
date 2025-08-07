# Setting Up Apple Shared Secret for Receipt Validation

This guide explains how to generate and configure the Apple shared secret for subscription receipt validation in the Circles app.

## What is the Apple Shared Secret?

The Apple shared secret is a unique code used to validate subscription receipts with Apple's servers. It provides an additional layer of security when verifying in-app purchases and subscriptions.

## Step 1: Generate the Shared Secret in App Store Connect

1. **Log in to App Store Connect**
   - Go to [App Store Connect](https://appstoreconnect.apple.com)
   - Sign in with your Apple Developer account

2. **Navigate to Your App**
   - Click on "My Apps"
   - Select "Circles" (or your app name)

3. **Go to In-App Purchases**
   - In the left sidebar, click on "Monetization"
   - Select "In-App Purchases"

4. **Generate Shared Secret**
   - Click on "App-Specific Shared Secret" (you might find this in the "Manage" section)
   - If no secret exists, click "Generate"
   - If a secret already exists, you can click "Regenerate" (but this will invalidate the old one)

5. **Copy the Shared Secret**
   - Click on the generated secret to reveal it
   - Copy the 32-character hexadecimal string
   - Store it securely - you won't be able to see it again!

## Step 2: Configure the Backend

### Local Development

1. **Update your `.env` file**:
   ```bash
   APPLE_SHARED_SECRET=your-32-character-shared-secret-here
   ```

2. **Verify the environment variable is loaded**:
   ```bash
   # In your backend directory
   cd backend
   node -e "console.log(process.env.APPLE_SHARED_SECRET ? 'Secret is set' : 'Secret is NOT set')"
   ```

### Production (Google Cloud Run)

1. **Update the environment variables in Cloud Run**:
   ```bash
   gcloud run services update circles-backend \
     --update-env-vars APPLE_SHARED_SECRET=your-32-character-shared-secret-here \
     --region=us-central1
   ```

2. **Alternative: Use Google Secret Manager** (recommended for production):
   ```bash
   # Create the secret
   echo -n "your-32-character-shared-secret-here" | gcloud secrets create apple-shared-secret --data-file=-
   
   # Grant Cloud Run access to the secret
   gcloud secrets add-iam-policy-binding apple-shared-secret \
     --member="serviceAccount:YOUR-SERVICE-ACCOUNT@YOUR-PROJECT.iam.gserviceaccount.com" \
     --role="roles/secretmanager.secretAccessor"
   
   # Update Cloud Run to use the secret
   gcloud run services update circles-backend \
     --update-secrets=APPLE_SHARED_SECRET=apple-shared-secret:latest \
     --region=us-central1
   ```

## Step 3: Test Receipt Validation

### Test with Sandbox Environment

1. **Create a test receipt** (in your iOS app with sandbox account)
2. **Send a test request to your backend**:
   ```bash
   curl -X POST https://your-backend-url/api/users/subscription/verify \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
     -d '{
       "receipt": "BASE64_ENCODED_RECEIPT_DATA"
     }'
   ```

3. **Check the logs** for any validation errors

### Common Status Codes

When validating receipts, Apple returns these status codes:
- `0`: Valid receipt
- `21000`: App Store could not read the JSON
- `21002`: Receipt data is malformed
- `21003`: Receipt could not be authenticated
- `21004`: Shared secret does not match
- `21005`: Receipt server is unavailable
- `21006`: Receipt is valid but subscription expired
- `21007`: Receipt is from sandbox (when sent to production)
- `21008`: Receipt is from production (when sent to sandbox)

## Security Best Practices

1. **Never expose the shared secret** in client-side code
2. **Always validate receipts server-side**
3. **Use HTTPS** for all receipt validation requests
4. **Rotate the shared secret** periodically
5. **Monitor for suspicious validation patterns**

## Troubleshooting

### "Invalid receipt" errors
- Verify the shared secret is correctly set in environment variables
- Check if you're using the right environment (sandbox vs production)
- Ensure the receipt data is properly base64 encoded

### "Shared secret does not match" (status 21004)
- Double-check the shared secret in App Store Connect
- Verify no extra spaces or characters in the environment variable
- Ensure the secret hasn't been regenerated since you last set it

### Testing in Development
- Use StoreKit Configuration file for local testing
- Create sandbox test accounts in App Store Connect
- The backend automatically uses sandbox URLs in development mode

## Implementation Details

The Circles app backend uses the shared secret in:
- **File**: `/backend/controllers/subscriptionController.js`
- **Function**: `verifySubscription`
- **Usage**: Sent as the `password` field to Apple's receipt validation API

```javascript
const verificationResponse = await axios.post(APPLE_VERIFY_RECEIPT_URL, {
    'receipt-data': receipt,
    'password': APPLE_SHARED_SECRET,
    'exclude-old-transactions': true
});
```

## Next Steps

After setting up the shared secret:
1. Configure your subscription products in App Store Connect
2. Create sandbox test accounts
3. Test the complete subscription flow
4. Monitor receipt validation logs for any issues