# Network Sharing Feature Deployment Guide

This guide covers the deployment of the network-based circle sharing feature that replaces the "friends" terminology with "myNetwork" and adds bidirectional circle sharing capabilities.

## Changes Summary

### Backend Changes

1. **Model Updates**:
   - `Circle.js`: Added `allowNetworkEdit` field and changed privacy enum from 'friends' to 'myNetwork'
   - `FirestoreModels.js`: Updated to support new fields and privacy values
   - `Place.js`: Changed privacy enum from 'friends' to 'myNetwork'

2. **New API Endpoints**:
   - `GET /api/network/circles-shared-with-me` - Get circles where others enabled "allow others to edit"
   - `GET /api/network/my-network-circles` - Get circles from connections with 'myNetwork' privacy

3. **Controller Updates**:
   - `circleSharingController.js`: Added new endpoints for network-based sharing

### iOS Changes (Already Deployed via App Update)

1. **Model Updates**:
   - Updated Circle and Place models to use 'myNetwork' instead of 'friends'
   - Added support for `allowNetworkEdit` field

2. **UI Updates**:
   - Added "My Network's Circles" filter in My Circles tab
   - Updated Shared Circles to show editable circles from others
   - Added search functionality in My Network tab
   - Changed all UI text from "Friends Only" to "My Network"

## Pre-Deployment Checklist

- [ ] Verify all tests pass locally: `npm test`
- [ ] Ensure MongoDB connection is stable
- [ ] Backup production database
- [ ] Review environment variables in `.env`
- [ ] Confirm Firebase project settings

## Deployment Steps

### 1. Deploy Firestore Indexes (if using Firestore)
```bash
cd backend
./deploy-indexes.sh
```

### 2. Run Database Migration (if needed)
```bash
# Connect to production MongoDB
# Run migration to update existing 'friends' privacy to 'myNetwork'
node scripts/migrate-friends-to-mynetwork.js
```

### 3. Deploy Backend
```bash
cd backend

# For first-time deployment or configuration changes
./deploy.sh

# For quick updates (uses existing configuration)
./quick-deploy.sh
```

### 4. Verify Deployment
```bash
# Check health endpoint
curl https://circles-backend-<hash>-uc.a.run.app/health

# Test new endpoints (replace with actual service URL and auth token)
curl -H "Authorization: Bearer <token>" https://circles-backend-<hash>-uc.a.run.app/api/network/circles-shared-with-me
curl -H "Authorization: Bearer <token>" https://circles-backend-<hash>-uc.a.run.app/api/network/my-network-circles
```

## Post-Deployment Testing

### 1. Test Circle Privacy
- Create a new circle with 'myNetwork' privacy
- Verify it appears in connected users' "My Network's Circles" filter
- Ensure 'friends' privacy is no longer available

### 2. Test Circle Sharing
- Create a circle with "Allow network to edit" enabled
- Verify it appears in connected users' Shared Circles tab
- Test editing shared circles from both users

### 3. Test API Endpoints
```bash
# Test circles shared with me
GET /api/network/circles-shared-with-me
# Should return circles where others enabled allowNetworkEdit

# Test my network's circles
GET /api/network/my-network-circles
# Should return circles from connections with myNetwork privacy
```

### 4. Monitor Logs
```bash
# View Cloud Run logs
gcloud run services logs read circles-backend --limit=50
```

## Rollback Procedure

If issues are detected:

1. **Quick Rollback**:
   ```bash
   # List revisions
   gcloud run revisions list --service=circles-backend
   
   # Route traffic to previous revision
   gcloud run services update-traffic circles-backend --to-revisions=<previous-revision>=100
   ```

2. **Database Rollback** (if migration was performed):
   ```bash
   # Run reverse migration
   node scripts/migrate-mynetwork-to-friends.js
   ```

## Monitoring

### Key Metrics to Watch
- API response times for new endpoints
- Error rates on circle operations
- Database query performance
- Memory usage (should remain stable)

### Alerts to Set Up
- High error rate on `/api/network/*` endpoints
- Increased latency on circle queries
- Failed circle sharing operations

## Troubleshooting

### Common Issues

1. **"Friends" privacy still appearing**:
   - Check if database migration completed successfully
   - Clear any client-side caches
   - Verify backend is using latest code

2. **Shared circles not appearing**:
   - Verify connections are properly established
   - Check `allowNetworkEdit` field is set correctly
   - Ensure user permissions are correct

3. **Performance issues**:
   - Check database indexes are deployed
   - Monitor query execution times
   - Consider increasing Cloud Run instances

### Debug Commands
```bash
# Check service configuration
gcloud run services describe circles-backend

# View recent errors
gcloud logging read "resource.type=cloud_run_revision AND severity>=ERROR" --limit=20

# Check environment variables
gcloud run services describe circles-backend --format="value(spec.template.spec.containers[0].env[].name)"
```

## Success Criteria

- [ ] All existing circle functionality works as before
- [ ] New network sharing endpoints return correct data
- [ ] "My Network" terminology appears throughout the app
- [ ] Connected users can see and edit shared circles
- [ ] No increase in error rates or latency
- [ ] Database queries remain performant

## Notes

- The iOS app update should be released after backend deployment
- Users may need to refresh their app to see new features
- Monitor user feedback for any issues with the terminology change