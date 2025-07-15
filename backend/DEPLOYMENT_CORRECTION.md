# Deployment Command Corrections

## Important: Always use the correct Google Cloud Project ID

The correct project ID is: **`circles-app-83b67`**

### Common Mistakes to Avoid:
- ❌ `gcloud builds submit --tag gcr.io/circles-backend/circles-api`
- ✅ `gcloud builds submit --tag gcr.io/circles-app-83b67/circles-api`

### Correct Deployment Commands:

```bash
# 1. Always set the correct project first
gcloud config set project circles-app-83b67

# 2. Build and push Docker image
gcloud builds submit --tag gcr.io/circles-app-83b67/circles-api

# 3. Deploy to Cloud Run
gcloud run deploy circles-backend \
  --image gcr.io/circles-app-83b67/circles-api \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated
```

### Key Points:
- **Project ID**: `circles-app-83b67` (NOT `circles-backend`)
- **Service Name**: `circles-backend` (this is just the Cloud Run service name)
- **Container Registry**: Must use `gcr.io/circles-app-83b67/...`
- **Region**: `us-central1`

### Files Updated:
1. ✅ `/backend/DEPLOYMENT_NOTES.md` - Corrected project ID
2. ✅ `/backend/deploy.sh` - Already has correct project ID
3. ✅ `/backend/quick-deploy.sh` - Has logic to auto-correct project ID
4. ❌ `/CLAUDE.md` - Needs manual update in Deployment Guide section

### CLAUDE.md Update Needed:
In the "Deployment Guide" → "Backend Deployment to Google Cloud Run" section, change:
- FROM: `gcloud builds submit --tag gcr.io/circles-backend/circles-api`
- TO: `gcloud builds submit --tag gcr.io/circles-app-83b67/circles-api`

### Environment Variables Reference:
- `FIREBASE_PROJECT_ID=circles-app-83b67`
- `FIREBASE_STORAGE_BUCKET=circles-app-83b67.appspot.com`

Remember: The Google Cloud project ID and Firebase project ID are the same: `circles-app-83b67`