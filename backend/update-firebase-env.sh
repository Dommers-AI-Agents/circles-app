#!/bin/bash

# Script to update Firebase environment variables on Cloud Run
# This script helps configure Firebase Storage and other Firebase services

set -e

SERVICE_NAME="circles-backend"
REGION="us-central1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔥 Firebase Configuration Update for Cloud Run${NC}"
echo "=============================================="

# Get current project
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}❌ No Google Cloud project set${NC}"
    echo "Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo -e "${GREEN}Service: $SERVICE_NAME${NC}"
echo -e "${GREEN}Project: $PROJECT_ID${NC}"
echo -e "${GREEN}Region: $REGION${NC}"
echo ""

# Function to update a single environment variable
update_env_var() {
    local var_name=$1
    local var_value=$2
    
    echo -e "${YELLOW}Updating $var_name...${NC}"
    gcloud run services update $SERVICE_NAME \
        --update-env-vars "$var_name=$var_value" \
        --region=$REGION \
        --project=$PROJECT_ID \
        --quiet
}

# Check if service exists
if ! gcloud run services describe $SERVICE_NAME --region=$REGION --project=$PROJECT_ID &>/dev/null; then
    echo -e "${RED}❌ Service $SERVICE_NAME not found in region $REGION${NC}"
    echo "Please deploy the service first using deploy.sh"
    exit 1
fi

echo -e "${YELLOW}This script will help you configure Firebase for your Cloud Run service.${NC}"
echo ""

# Firebase Project Configuration
echo -e "${BLUE}1. Firebase Project Configuration${NC}"
echo "Enter your Firebase project ID (usually same as Google Cloud project ID)"
read -p "FIREBASE_PROJECT_ID [$PROJECT_ID]: " FIREBASE_PROJECT_ID
FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID:-$PROJECT_ID}

# Firebase Storage Configuration
echo -e "\n${BLUE}2. Firebase Storage Configuration${NC}"
echo "Detecting Firebase Storage bucket..."

# Try to list buckets and find the Firebase one
EXISTING_BUCKET=$(gcloud storage buckets list --project=$FIREBASE_PROJECT_ID --format="value(name)" | grep -E "(${FIREBASE_PROJECT_ID}\.(appspot\.com|firebasestorage\.app))" | head -1)

if [ -n "$EXISTING_BUCKET" ]; then
    echo -e "${GREEN}✅ Found existing Firebase Storage bucket: $EXISTING_BUCKET${NC}"
    FIREBASE_STORAGE_BUCKET="$EXISTING_BUCKET"
    echo -e "${YELLOW}Using: $FIREBASE_STORAGE_BUCKET${NC}"
else
    echo -e "${RED}❌ No Firebase Storage bucket found for project: $FIREBASE_PROJECT_ID${NC}"
    echo "Please create a bucket in Firebase Console > Storage"
    echo "Then run this script again."
    exit 1
fi

# Service Account Configuration
echo -e "\n${BLUE}3. Service Account Configuration${NC}"
echo "For production on Cloud Run, you can use Application Default Credentials"
echo "Do you want to provide a service account JSON key? (not required for Cloud Run)"
read -p "Use service account JSON? (y/N): " USE_SERVICE_ACCOUNT

ENV_VARS_TO_UPDATE=""

# Add Firebase project ID
ENV_VARS_TO_UPDATE="FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"

# Add Firebase storage bucket
ENV_VARS_TO_UPDATE="$ENV_VARS_TO_UPDATE,FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET"

# Add GCS_BUCKET_NAME for backward compatibility
ENV_VARS_TO_UPDATE="$ENV_VARS_TO_UPDATE,GCS_BUCKET_NAME=$FIREBASE_STORAGE_BUCKET"

if [[ "$USE_SERVICE_ACCOUNT" =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}Please provide the service account JSON contents${NC}"
    echo "You can get this from Firebase Console > Project Settings > Service Accounts"
    echo "Paste the JSON content and press Ctrl+D when done:"
    
    # Read multiline JSON input
    SERVICE_ACCOUNT_JSON=$(cat)
    
    if [ -n "$SERVICE_ACCOUNT_JSON" ]; then
        # Escape the JSON for use as an environment variable
        ESCAPED_JSON=$(echo "$SERVICE_ACCOUNT_JSON" | jq -c .)
        ENV_VARS_TO_UPDATE="$ENV_VARS_TO_UPDATE,FIREBASE_SERVICE_ACCOUNT_KEY=$ESCAPED_JSON"
    fi
fi

# Update all environment variables at once
echo -e "\n${YELLOW}Updating environment variables...${NC}"
gcloud run services update $SERVICE_NAME \
    --update-env-vars "$ENV_VARS_TO_UPDATE" \
    --region=$REGION \
    --project=$PROJECT_ID

echo -e "\n${GREEN}✅ Firebase environment variables updated!${NC}"

# Verify the configuration
echo -e "\n${YELLOW}Verifying configuration...${NC}"
echo "Current Firebase-related environment variables:"
gcloud run services describe $SERVICE_NAME \
    --region $REGION \
    --project=$PROJECT_ID \
    --format="table(spec.template.spec.containers[0].env[?name~'FIREBASE|GCS'].name,spec.template.spec.containers[0].env[?name~'FIREBASE|GCS'].value:label=VALUE:wrap=60)"

# Test the deployment
echo -e "\n${YELLOW}Testing image upload endpoint...${NC}"
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --project=$PROJECT_ID \
    --format 'value(status.url)')

if [ -n "$SERVICE_URL" ]; then
    echo -e "Service URL: ${GREEN}$SERVICE_URL${NC}"
    echo -e "\nTo test image upload, you need to:"
    echo "1. Get a valid JWT token from your app"
    echo "2. Use curl or your iOS app to test the upload"
    echo ""
    echo "Example curl command:"
    echo 'curl -X POST '$SERVICE_URL'/api/upload/image \'
    echo '  -H "Authorization: Bearer YOUR_JWT_TOKEN" \'
    echo '  -H "Content-Type: application/json" \'
    echo '  -d '"'"'{"image": "base64_image_data", "filename": "test.jpg"}'"'"
fi

echo -e "\n${BLUE}Next Steps:${NC}"
echo "1. Deploy Firebase Storage rules: cd backend && npm run deploy:storage-rules"
echo "2. Test image upload from your iOS app"
echo "3. Monitor logs: gcloud run logs tail $SERVICE_NAME --project=$PROJECT_ID"

echo -e "\n${GREEN}🎉 Firebase configuration complete!${NC}"