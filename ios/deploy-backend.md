# Backend Deployment Guide for Circles App

## Option 1: Google Cloud Run (Recommended)

### Prerequisites
1. Install Google Cloud SDK: https://cloud.google.com/sdk/docs/install
2. Enable Cloud Run API in your Google Cloud Console

### Steps to Deploy

1. **Create a Dockerfile** in your backend directory:
```dockerfile
# Use the official Node.js image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application files
COPY . .

# Expose port
EXPOSE 3001

# Start the application
CMD ["node", "server.js"]
```

2. **Create a .gcloudignore file**:
```
node_modules
.git
.gitignore
*.md
.env.local
```

3. **Update your backend to use environment variables**:
```javascript
const PORT = process.env.PORT || 3001;
```

4. **Deploy to Cloud Run**:
```bash
# Initialize gcloud (if not done already)
gcloud init

# Build and deploy
gcloud run deploy circles-backend \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars NODE_ENV=production
```

5. **Set environment variables in Cloud Run**:
- Go to Cloud Run console
- Click on your service
- Click "Edit & Deploy New Revision"
- Under "Variables & Secrets", add:
  - JWT_SECRET
  - JWT_EXPIRE
  - LINKEDIN_CLIENT_ID
  - LINKEDIN_CLIENT_SECRET
  - Any Firebase config if needed

## Option 2: Railway (Simple Alternative)

Railway is a simple platform that can deploy your backend directly from GitHub.

1. **Sign up at railway.app**
2. **Connect your GitHub repository**
3. **Add environment variables in Railway dashboard**
4. **Railway will auto-deploy on push**

## Option 3: Render (Free Tier Available)

1. **Sign up at render.com**
2. **Create a new Web Service**
3. **Connect your GitHub repo**
4. **Set environment variables**
5. **Deploy**

## Option 4: Firebase Cloud Functions (More Complex)

This requires refactoring your Express app to work with Cloud Functions:

```javascript
const functions = require('firebase-functions');
const app = require('./app'); // Your Express app

exports.api = functions.https.onRequest(app);
```

## Update iOS App Configuration

Once deployed, update your iOS app:

1. **Update APIService.swift**:
```swift
private var baseURL: String {
    #if DEBUG
    return "http://192.168.0.120:3001/api"
    #else
    // Your production URL from Cloud Run
    return "https://circles-backend-xxxxx-uc.a.run.app/api"
    #endif
}
```

2. **Add to Info.plist** (if not using HTTPS):
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>your-backend-domain.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

## Important Security Notes

1. **Never commit sensitive keys** - Use environment variables
2. **Enable CORS** for your iOS app's bundle ID
3. **Use HTTPS in production**
4. **Implement rate limiting**
5. **Add authentication middleware**

## Recommended: Cloud Run Deployment Script

Create a `deploy.sh` in your backend:
```bash
#!/bin/bash
gcloud run deploy circles-backend \
  --source . \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars NODE_ENV=production,\
JWT_SECRET=$JWT_SECRET,\
JWT_EXPIRE=$JWT_EXPIRE,\
LINKEDIN_CLIENT_ID=$LINKEDIN_CLIENT_ID,\
LINKEDIN_CLIENT_SECRET=$LINKEDIN_CLIENT_SECRET
```

Make it executable: `chmod +x deploy.sh`