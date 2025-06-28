# Firebase Storage Upload Fix

## Issue
The backend was returning a 500 error "Failed to upload image" because Firebase Storage was not properly configured in the Cloud Run deployment.

## Root Cause
The Firebase Storage bucket name was not being passed as an environment variable to the Cloud Run service. The backend needs these environment variables:
- `FIREBASE_PROJECT_ID`
- `FIREBASE_STORAGE_BUCKET` or `GCS_BUCKET_NAME`

## Solution

### Option 1: Quick Fix (Recommended)
Run the new Firebase environment update script:

```bash
cd backend
./update-firebase-env.sh
```

This script will:
1. Ask for your Firebase project ID
2. Ask for your Firebase Storage bucket name (usually `your-project.appspot.com`)
3. Update the Cloud Run service with the proper environment variables
4. Test the configuration

### Option 2: Full Redeployment
If you want to redeploy the entire backend with Firebase configuration:

```bash
cd backend
./deploy.sh
```

The updated deployment script now includes prompts for Firebase configuration.

### Option 3: Manual Update
Update the environment variables manually:

```bash
gcloud run services update circles-backend \
  --update-env-vars "FIREBASE_PROJECT_ID=your-project-id,FIREBASE_STORAGE_BUCKET=your-project.appspot.com" \
  --region us-central1
```

## What Changed

1. **Enhanced Error Handling** (`storage.js`)
   - Added checks for missing Firebase Storage configuration
   - Added support for both `FIREBASE_STORAGE_BUCKET` and `GCS_BUCKET_NAME` environment variables
   - Added detailed error logging to help diagnose issues

2. **New Update Script** (`update-firebase-env.sh`)
   - Created a dedicated script for updating Firebase environment variables
   - Makes it easy to fix configuration without full redeployment

3. **Updated Deploy Script** (`deploy.sh`)
   - Now prompts for Firebase configuration during deployment
   - Automatically sets both `FIREBASE_STORAGE_BUCKET` and `GCS_BUCKET_NAME`

## Verifying the Fix

After updating the environment variables:

1. Check the logs:
   ```bash
   gcloud run logs tail circles-backend
   ```

2. Test an image upload from your iOS app

3. Look for these log messages:
   - "Using storage bucket: your-project.appspot.com"
   - "File uploaded successfully: https://firebasestorage.googleapis.com/..."

## Additional Notes

- Cloud Run services running on Google Cloud can use Application Default Credentials, so you don't need to provide a service account JSON in most cases
- The backend now supports multiple ways to configure the storage bucket for flexibility
- Make sure your Firebase Storage rules allow authenticated writes to the `/circles/` directory