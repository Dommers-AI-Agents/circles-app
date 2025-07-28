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
ENV_VARS="$ENV_VARS,JWT_EXPIRE=${JWT_EXPIRE:-30d}"
ENV_VARS="$ENV_VARS,FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID:-circles-app-83b67}"
ENV_VARS="$ENV_VARS,FIREBASE_STORAGE_BUCKET=${FIREBASE_STORAGE_BUCKET:-circles-app-83b67.firebasestorage.app}"

# Email configuration from .env
if [ ! -z "$EMAIL_SERVICE" ]; then
    ENV_VARS="$ENV_VARS,EMAIL_SERVICE=$EMAIL_SERVICE"
fi
if [ ! -z "$SMTP_HOST" ]; then
    ENV_VARS="$ENV_VARS,SMTP_HOST=$SMTP_HOST"
fi
if [ ! -z "$SMTP_PORT" ]; then
    ENV_VARS="$ENV_VARS,SMTP_PORT=$SMTP_PORT"
fi
if [ ! -z "$SMTP_SECURE" ]; then
    ENV_VARS="$ENV_VARS,SMTP_SECURE=$SMTP_SECURE"
fi
if [ ! -z "$SMTP_USER" ]; then
    ENV_VARS="$ENV_VARS,SMTP_USER=$SMTP_USER"
fi
if [ ! -z "$SMTP_PASS" ]; then
    ENV_VARS="$ENV_VARS,SMTP_PASS=$SMTP_PASS"
fi
if [ ! -z "$EMAIL_FROM_ADDRESS" ]; then
    ENV_VARS="$ENV_VARS,EMAIL_FROM_ADDRESS=$EMAIL_FROM_ADDRESS"
fi
if [ ! -z "$EMAIL_FROM_NAME" ]; then
    ENV_VARS="$ENV_VARS,EMAIL_FROM_NAME=$EMAIL_FROM_NAME"
fi
if [ ! -z "$APP_URL" ]; then
    ENV_VARS="$ENV_VARS,APP_URL=$APP_URL"
fi

# Preserve existing env vars
ENV_VARS="$ENV_VARS,EMAIL_USER=noreply@circles-app.com"
ENV_VARS="$ENV_VARS,GMAIL_USER=circles.app.notifications@gmail.com"
ENV_VARS="$ENV_VARS,GMAIL_APP_PASSWORD=sgro xwco nekm okwm"

if [ ! -z "$GOOGLE_MAPS_API_KEY" ]; then
    ENV_VARS="$ENV_VARS,GOOGLE_MAPS_API_KEY=$GOOGLE_MAPS_API_KEY"
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
    
    # Test email endpoint
    echo -e "\n${YELLOW}Testing email endpoints...${NC}"
    EMAIL_TEST=$(curl -s "$SERVICE_URL/api/email/test-config" || echo "Failed")
    
    if [[ $EMAIL_TEST == *"Route not found"* ]]; then
        echo -e "${YELLOW}⚠️  Email test routes not deployed yet${NC}"
        echo "But email configuration has been updated for existing email functionality"
    else
        echo -e "${GREEN}✅ Email test routes are available${NC}"
    fi
else
    echo -e "${RED}❌ API health check failed${NC}"
fi

echo -e "\n${GREEN}🎉 Deployment complete!${NC}"
echo ""
echo "📧 Email is configured to send from: wesley@favcircles.com"
echo "🔍 To view logs: gcloud run logs tail $SERVICE_NAME --project=$PROJECT_ID"