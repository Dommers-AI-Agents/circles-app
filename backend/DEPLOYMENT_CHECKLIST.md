# Circles Backend Deployment Checklist

This checklist ensures all network sharing features are properly deployed to production.

## Pre-Deployment Verification

### 1. Code Review
- [ ] All network sharing endpoints tested locally
- [ ] Authentication properly implemented on all routes
- [ ] Error handling comprehensive
- [ ] No hardcoded values or secrets in code

### 2. Environment Variables
- [ ] Copy `.env.example` to `.env` and fill all required values
- [ ] Verify Firebase credentials are correct
- [ ] Ensure JWT_SECRET is strong and unique
- [ ] Check Google Cloud Storage bucket configuration
- [ ] Verify all API keys are production keys

### 3. Database Preparation
- [ ] Review Firestore indexes in `firestore.indexes.json`
- [ ] Check Firebase security rules in `firestore.rules`
- [ ] Verify all collections are properly structured
- [ ] Test database queries with production-like data

### 4. Local Testing
```bash
# Start backend locally
npm start

# Test key endpoints
curl http://localhost:3001/api/health
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3001/api/network/connections
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:3001/api/network/circles/shared
```

## Deployment Process

### 1. Deploy Firestore Configuration
```bash
# Deploy indexes
./deploy-indexes.sh

# Deploy security rules (if needed)
firebase deploy --only firestore:rules --project circles-app-83b67
```

### 2. Initial Deployment
```bash
# Run full deployment script
./deploy.sh

# This will:
# - Create/update Dockerfile
# - Configure environment variables
# - Deploy to Google Cloud Run
# - Provide the service URL
```

### 3. Quick Updates
```bash
# For subsequent deployments
./quick-deploy.sh
```

### 4. Environment Variable Updates
```bash
# Update environment variables without full redeploy
./update-env-vars.sh
```

## Post-Deployment Verification

### 1. Service Health
```bash
# Check service status
gcloud run services describe circles-backend --region=us-central1

# Test the API endpoint
curl https://YOUR-SERVICE-URL.run.app/api/health
```

### 2. Network Features Testing
- [ ] Create new connection between users
- [ ] Accept/reject connection requests
- [ ] Share a circle with connection
- [ ] View shared circles
- [ ] Update share permissions
- [ ] Remove circle share

### 3. Monitor Logs
```bash
# Real-time logs
gcloud run logs tail circles-backend

# Check for errors
gcloud run logs read circles-backend --limit=100 | grep -E "ERROR|error"

# Check specific time range
gcloud run logs read circles-backend --since="2 hours ago"
```

## iOS App Update

After successful deployment:

1. Update `APIService.swift` with new URL:
```swift
case .production:
    return "https://YOUR-SERVICE-URL.run.app/api"
```

2. Test in TestFlight:
- [ ] Connection requests work
- [ ] Circle sharing functional
- [ ] Shared circles display correctly
- [ ] Permissions update properly

## Rollback Procedure

If issues arise:

```bash
# List all revisions
gcloud run revisions list --service=circles-backend --region=us-central1

# Rollback to previous revision
gcloud run services update-traffic circles-backend \
  --to-revisions=PREVIOUS_REVISION_NAME=100 \
  --region=us-central1
```

## Production Monitoring

### 1. Set Up Alerts
- [ ] Configure Cloud Monitoring alerts
- [ ] Set up error rate thresholds
- [ ] Monitor response time metrics
- [ ] Track API usage patterns

### 2. Regular Checks
- [ ] Weekly log review
- [ ] Monitor Firebase usage/costs
- [ ] Check Cloud Run metrics
- [ ] Review error patterns

### 3. Performance Optimization
- [ ] Monitor cold start times
- [ ] Check memory usage
- [ ] Review concurrent request handling
- [ ] Optimize database queries

## Security Checklist

- [ ] All endpoints require authentication
- [ ] Firestore rules restrict access appropriately
- [ ] CORS configured for production domain only
- [ ] Secrets stored in environment variables
- [ ] Regular security updates applied
- [ ] API rate limiting configured (if needed)

## Backup and Recovery

- [ ] Firestore automatic backups enabled
- [ ] Export critical data regularly
- [ ] Document recovery procedures
- [ ] Test restore process quarterly

## Contact Information

- **Cloud Run Dashboard**: https://console.cloud.google.com/run
- **Firebase Console**: https://console.firebase.google.com/project/circles-app-83b67
- **Logs Viewer**: https://console.cloud.google.com/logs

## Notes

- Cloud Run automatically scales to zero when not in use (cost-effective)
- First request after idle may have higher latency (cold start)
- Monitor Firebase quotas to avoid service interruption
- Keep deployment scripts updated with any infrastructure changes