# Activity Cleanup Deployment Instructions

## Changes Made

1. **Added cleanup endpoint**: `/api/connections/admin/cleanup-activities`
   - POST endpoint to manually trigger activity cleanup
   - Accepts `daysToKeep` parameter (defaults to 1 day)

2. **Added automatic cleanup to server startup**:
   - Runs 10 seconds after server starts
   - Cleans up activities older than 24 hours

3. **Added scheduled daily cleanup**:
   - Runs every 24 hours
   - Keeps only activities from the last 24 hours

## Files Modified

- `backend/routes/connectionRoutes.js` - Added cleanup endpoint
- `backend/server.js` - Added scheduled cleanup
- `backend/scripts/cleanup-activities.js` - Manual cleanup script (optional)

## Deployment Steps

1. **Commit changes**:
```bash
git add backend/routes/connectionRoutes.js backend/server.js backend/scripts/cleanup-activities.js
git commit -m "Fix activity indicators with 24-hour cleanup"
```

2. **Deploy to Google Cloud Run**:
```bash
cd backend
gcloud run deploy circles-backend \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --cpu 1 \
  --min-instances 1 \
  --max-instances 100
```

## What This Fixes

The issue was that old activities were never cleaned up from the `recentActivity` arrays in connection documents. This caused:

- All connections to show red activity dots even if they hadn't been active recently
- The 24-hour window check was finding old activities that should have been removed

With this fix:
- Activities older than 24 hours are automatically removed
- Only truly recent activity (within last 24 hours) will show red dots
- The cleanup runs automatically on server startup and daily thereafter

## Testing

After deployment:
1. The server will run an initial cleanup 10 seconds after starting
2. Check the logs to confirm cleanup ran: `gcloud run logs read --service circles-backend --region us-central1`
3. Log out and back in to the app - only connections with activity in the last 24 hours should show red dots