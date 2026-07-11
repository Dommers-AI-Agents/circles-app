#!/bin/bash

echo "🚀 Circles Backend Deployment Script"
echo "======================================"

# Configuration
PROJECT_ID="circles-app-83b67"
SERVICE_NAME="circles-backend"
REGION="us-central1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Set the project
gcloud config set project $PROJECT_ID

echo -e "${GREEN}✅ Using project: $PROJECT_ID${NC}"

# Note: This script assumes Google Cloud APIs are already enabled
# If you need to enable APIs, run: gcloud services enable cloudrun.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com

# Load environment variables from .env
if [ -f ".env" ]; then
    echo -e "\n${YELLOW}Loading environment variables from .env...${NC}"
    export $(cat .env | grep -v '^#' | xargs)
else
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi

# Build environment variables string
ENV_VARS="NODE_ENV=production"
ENV_VARS="$ENV_VARS,JWT_SECRET=$JWT_SECRET"
ENV_VARS="$ENV_VARS,JWT_EXPIRE=${JWT_EXPIRE:-365d}"
ENV_VARS="$ENV_VARS,FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID:-circles-app-83b67}"
ENV_VARS="$ENV_VARS,FIREBASE_STORAGE_BUCKET=${FIREBASE_STORAGE_BUCKET:-circles-app-83b67.firebasestorage.app}"

if [ ! -z "$GOOGLE_MAPS_API_KEY" ]; then
    ENV_VARS="$ENV_VARS,GOOGLE_MAPS_API_KEY=$GOOGLE_MAPS_API_KEY"
fi

# Add Firebase API Key
ENV_VARS="$ENV_VARS,FIREBASE_API_KEY=AIzaSyDMWyL8jI_MZSuASgxc_aSpyqJpxUSARYI"

# Sticker rewards admin API secret
if [ ! -z "$ADMIN_SECRET" ]; then
    ENV_VARS="$ENV_VARS,ADMIN_SECRET=$ADMIN_SECRET"
fi

# SMTP email configuration (QR emails, venue reports, welcome emails)
if [ ! -z "$SMTP_HOST" ]; then
    ENV_VARS="$ENV_VARS,EMAIL_SERVICE=${EMAIL_SERVICE:-custom}"
    ENV_VARS="$ENV_VARS,SMTP_HOST=$SMTP_HOST"
    ENV_VARS="$ENV_VARS,SMTP_PORT=${SMTP_PORT:-465}"
    ENV_VARS="$ENV_VARS,SMTP_SECURE=${SMTP_SECURE:-true}"
    ENV_VARS="$ENV_VARS,SMTP_USER=$SMTP_USER"
    ENV_VARS="$ENV_VARS,SMTP_PASS=$SMTP_PASS"
    ENV_VARS="$ENV_VARS,EMAIL_FROM_ADDRESS=$EMAIL_FROM_ADDRESS"
    ENV_VARS="$ENV_VARS,EMAIL_FROM_NAME=$EMAIL_FROM_NAME"
fi

# Add Apple Shared Secret for subscription receipt validation
if [ ! -z "$APPLE_SHARED_SECRET" ]; then
    ENV_VARS="$ENV_VARS,APPLE_SHARED_SECRET=$APPLE_SHARED_SECRET"
fi

# Swarm (Foursquare) place import OAuth credentials
if [ ! -z "$FOURSQUARE_CLIENT_ID" ]; then
    ENV_VARS="$ENV_VARS,FOURSQUARE_CLIENT_ID=$FOURSQUARE_CLIENT_ID"
    ENV_VARS="$ENV_VARS,FOURSQUARE_CLIENT_SECRET=$FOURSQUARE_CLIENT_SECRET"
    ENV_VARS="$ENV_VARS,FOURSQUARE_REDIRECT_URI=$FOURSQUARE_REDIRECT_URI"
fi

# Deploy to Cloud Run
echo -e "\n${YELLOW}Deploying to Cloud Run...${NC}"

gcloud run deploy $SERVICE_NAME \
    --source . \
    --platform managed \
    --region $REGION \
    --allow-unauthenticated \
    --set-env-vars="$ENV_VARS" \
    --project=$PROJECT_ID \
    --memory=512Mi \
    --max-instances=100 \
    --concurrency=80 \
    --port=8080 \
    --quiet

# Get the service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --project=$PROJECT_ID \
    --format 'value(status.url)')

if [ -z "$SERVICE_URL" ]; then
    echo -e "${RED}❌ Failed to get service URL${NC}"
    exit 1
fi

echo -e "\n${GREEN}✅ Deployment successful!${NC}"
echo -e "Service URL: ${GREEN}$SERVICE_URL${NC}"
echo -e "API Base URL: ${GREEN}$SERVICE_URL/api${NC}"

# Test the deployment
echo -e "\n${YELLOW}Testing deployment...${NC}"
HEALTH_CHECK=$(curl -s "$SERVICE_URL/" || echo "Failed")

if [[ $HEALTH_CHECK == *"Circles API"* ]]; then
    echo -e "${GREEN}✅ API is responding correctly${NC}"
else
    echo -e "${RED}❌ API health check failed${NC}"
fi

echo -e "\n${GREEN}🎉 Deployment complete!${NC}"
echo ""
echo "🔍 To view logs: gcloud run logs tail $SERVICE_NAME --project=$PROJECT_ID"