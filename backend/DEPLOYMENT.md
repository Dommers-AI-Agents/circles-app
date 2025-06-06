# Circles Backend Deployment Guide

This guide explains how to deploy the Circles backend to Google Cloud Run for use with TestFlight and production.

## Prerequisites

1. **Google Cloud Account**: Sign up at https://cloud.google.com
2. **Google Cloud SDK**: Install with Homebrew:
   ```bash
   brew install --cask google-cloud-sdk
   ```
3. **A Google Cloud Project**: Create one in the console or via CLI

## Initial Setup

1. **Login to Google Cloud**:
   ```bash
   gcloud auth login
   ```

2. **Create or select a project**:
   ```bash
   # List existing projects
   gcloud projects list
   
   # Create new project (optional)
   gcloud projects create circles-app-UNIQUE_ID
   
   # Set active project
   gcloud config set project YOUR_PROJECT_ID
   ```

3. **Enable billing** for your project (required for Cloud Run)

## First Deployment

Run the deployment script:

```bash
cd /Users/wesleysgroi/circles-app/backend
./deploy.sh
```

The script will:
- Check prerequisites
- Enable required Google Cloud APIs
- Create necessary files (Dockerfile, .gcloudignore)
- Collect environment variables
- Deploy to Cloud Run
- Test the deployment
- Provide the URL for your iOS app

## Environment Variables

Required variables:
- `JWT_SECRET`: Secret key for JWT tokens (required)
- `JWT_EXPIRE`: Token expiration time (default: 30d)

Optional variables:
- `LINKEDIN_CLIENT_ID`: For LinkedIn OAuth
- `LINKEDIN_CLIENT_SECRET`: For LinkedIn OAuth

## Update iOS App

After deployment, update your iOS app:

1. Open `Circles-iOS-UIKit/Services/APIService.swift`
2. Find the production URL in the `APIEnvironment` enum
3. Replace with your Cloud Run URL:
   ```swift
   case .production:
       return "https://circles-backend-xxxxx-uc.a.run.app/api"
   ```

## Quick Updates

For subsequent deployments after code changes:

```bash
./quick-deploy.sh
```

## Managing Environment Variables

Update environment variables without redeploying:

```bash
./update-env-vars.sh
```

Options:
1. Add/Update single variable
2. Update all from .env file
3. Remove a variable
4. View all current variables

## Monitoring & Debugging

### View Logs
```bash
# Tail logs in real-time
gcloud run logs tail circles-backend

# Read recent logs
gcloud run logs read circles-backend --limit=50
```

### View Service Details
```bash
gcloud run services describe circles-backend --region=us-central1
```

### Test the API
```bash
# Health check
curl https://YOUR-SERVICE-URL.run.app/

# Test with authentication
curl -H "Authorization: Bearer YOUR_TOKEN" https://YOUR-SERVICE-URL.run.app/api/users/me
```

## Cost Optimization

Cloud Run charges based on:
- CPU and memory usage while handling requests
- Number of requests
- Outbound data transfer

Tips to minimize costs:
1. Cloud Run scales to zero when not in use
2. Set appropriate memory limits (512Mi is usually enough)
3. Use caching where possible
4. Monitor usage in Google Cloud Console

## Troubleshooting

### Deployment Fails
- Check if billing is enabled
- Verify all required APIs are enabled
- Check Docker build logs

### API Not Responding
- Check logs: `gcloud run logs read circles-backend`
- Verify environment variables are set
- Check Firebase configuration

### Authentication Issues
- Verify JWT_SECRET is set correctly
- Check token expiration settings
- Ensure Firebase credentials are valid

## Production Checklist

Before going to production:
- [ ] Set strong JWT_SECRET
- [ ] Configure custom domain (optional)
- [ ] Set up monitoring alerts
- [ ] Enable Cloud Run authentication (if needed)
- [ ] Configure CORS for your app's bundle ID only
- [ ] Set up automated backups for Firestore
- [ ] Review and set appropriate resource limits
- [ ] Enable Cloud Logging for better debugging

## Rollback

If you need to rollback to a previous version:

```bash
# List all revisions
gcloud run revisions list --service=circles-backend --region=us-central1

# Rollback to specific revision
gcloud run services update-traffic circles-backend \
  --to-revisions=REVISION_NAME=100 \
  --region=us-central1
```

## Support

For issues specific to:
- **Cloud Run**: https://cloud.google.com/run/docs
- **Firebase**: https://firebase.google.com/docs
- **This deployment**: Check the logs first, then the troubleshooting section