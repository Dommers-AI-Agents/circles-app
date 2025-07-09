# Deployment Notes - Red Dot Activity Fix

## Date: January 2025

### Changes Made:

1. **connectionController.js**
   - Modified `getConnections` endpoint to always calculate `hasRecentPlace` dynamically from `recentActivity` array
   - Never uses persisted `hasRecentPlace` value from database
   - Added logging to track when persisted values are being overridden

2. **activityService.js**
   - Removed `hasRecentPlace: true` from `trackPlaceAdded` batch update
   - Modified `clearActivityNotification` to not update `hasRecentPlace` field
   - Field is now calculated dynamically, not persisted

3. **Migration Script**
   - Created `/backend/scripts/cleanupHasRecentPlace.js`
   - Removes all persisted `hasRecentPlace` fields from connections
   - Run this AFTER deploying the backend changes

### Deployment Steps:

1. Deploy backend to Google Cloud Run:
   ```bash
   cd backend
   gcloud builds submit --tag gcr.io/circles-backend/circles-api
   gcloud run deploy circles-backend \
     --image gcr.io/circles-backend/circles-api \
     --platform managed \
     --region us-central1 \
     --allow-unauthenticated
   ```

2. Run migration script:
   ```bash
   cd backend
   export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account-key.json"
   node scripts/cleanupHasRecentPlace.js
   ```

3. Monitor logs for any issues:
   ```bash
   gcloud run services logs read circles-backend --limit=50 --region us-central1
   ```

### What This Fixes:
- All connections showing red dots on initial app load
- Red dots becoming solid after viewing one connection
- Stale activity indicators from persisted data

### Frontend Changes:
- HorizontalUserListView now refreshes all connections after viewing one
- This ensures UI stays in sync with backend state