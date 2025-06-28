#!/bin/bash

# Circles Backend Deployment Script for Google Cloud Run
# This script deploys your Express.js backend to Google Cloud Run

set -e  # Exit on error

echo "🚀 Circles Backend Deployment Script"
echo "===================================="

# Configuration
PROJECT_ID="circles-app-83b67"
SERVICE_NAME="circles-backend"
REGION="us-central1"
PORT="3001"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "\n${YELLOW}Checking prerequisites...${NC}"

if ! command_exists gcloud; then
    echo -e "${RED}❌ Google Cloud SDK not installed${NC}"
    echo "Please install it first:"
    echo "  brew install --cask google-cloud-sdk"
    exit 1
fi

echo -e "${GREEN}✅ Google Cloud SDK found${NC}"

# Check if user is logged in to gcloud
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo -e "${YELLOW}You need to login to Google Cloud${NC}"
    gcloud auth login
fi

# Set the project
gcloud config set project $PROJECT_ID

echo -e "${GREEN}✅ Using project: $PROJECT_ID${NC}"

# Enable required APIs
echo -e "\n${YELLOW}Enabling required Google Cloud APIs...${NC}"
gcloud services enable cloudrun.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    --project=$PROJECT_ID

# Check for required files
echo -e "\n${YELLOW}Checking required files...${NC}"

if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}❌ Dockerfile not found${NC}"
    echo "Creating Dockerfile..."
    cat > Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application files
COPY . .

# Expose port (Cloud Run will set PORT env variable)
EXPOSE 3001

# Start the application
CMD ["node", "server.js"]
EOF
    echo -e "${GREEN}✅ Dockerfile created${NC}"
fi

if [ ! -f ".gcloudignore" ]; then
    echo "Creating .gcloudignore..."
    cat > .gcloudignore << 'EOF'
node_modules
.git
.gitignore
*.md
.env
.env.local
npm-debug.log
.DS_Store
EOF
    echo -e "${GREEN}✅ .gcloudignore created${NC}"
fi

# Load environment variables from .env if exists
if [ -f ".env" ]; then
    echo -e "\n${YELLOW}Loading environment variables from .env...${NC}"
    export $(cat .env | grep -v '^#' | xargs)
else
    echo -e "${RED}❌ .env file not found${NC}"
    echo "Please create a .env file with required variables"
    exit 1
fi

# Use environment variables from .env
echo -e "\n${YELLOW}Using environment variables from .env file...${NC}"
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRE=${JWT_EXPIRE:-"30d"}
FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID:-$PROJECT_ID}

# Automatically detect Firebase Storage bucket
echo "Detecting Firebase Storage bucket..."
FIREBASE_STORAGE_BUCKET=$(gcloud storage buckets list --project=$FIREBASE_PROJECT_ID --format="value(name)" 2>/dev/null | grep -E "(${FIREBASE_PROJECT_ID}\.(appspot\.com|firebasestorage\.app))" | head -1)

if [ -n "$FIREBASE_STORAGE_BUCKET" ]; then
    echo -e "${GREEN}✅ Found Firebase Storage bucket: $FIREBASE_STORAGE_BUCKET${NC}"
else
    echo -e "${YELLOW}⚠️  No Firebase Storage bucket found${NC}"
    echo "Image uploads will not work until you:"
    echo "1. Create a bucket in Firebase Console > Storage"
    echo "2. Run ./update-firebase-env.sh after deployment"
    FIREBASE_STORAGE_BUCKET=""
fi

# Use LinkedIn configuration from .env if available
LINKEDIN_CLIENT_ID=${LINKEDIN_CLIENT_ID}
LINKEDIN_CLIENT_SECRET=${LINKEDIN_CLIENT_SECRET}

# Validate required variables
if [ -z "$JWT_SECRET" ]; then
    echo -e "${RED}❌ JWT_SECRET is required${NC}"
    exit 1
fi

# Build environment variables string
ENV_VARS="NODE_ENV=production"
ENV_VARS="$ENV_VARS,JWT_SECRET=$JWT_SECRET"
ENV_VARS="$ENV_VARS,JWT_EXPIRE=$JWT_EXPIRE"
ENV_VARS="$ENV_VARS,FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"

if [ -n "$FIREBASE_STORAGE_BUCKET" ]; then
    ENV_VARS="$ENV_VARS,FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET"
    ENV_VARS="$ENV_VARS,GCS_BUCKET_NAME=$FIREBASE_STORAGE_BUCKET"
fi

if [ ! -z "$LINKEDIN_CLIENT_ID" ]; then
    ENV_VARS="$ENV_VARS,LINKEDIN_CLIENT_ID=$LINKEDIN_CLIENT_ID"
fi

if [ ! -z "$LINKEDIN_CLIENT_SECRET" ]; then
    ENV_VARS="$ENV_VARS,LINKEDIN_CLIENT_SECRET=$LINKEDIN_CLIENT_SECRET"
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
    --port=$PORT \
    --memory=512Mi \
    --max-instances=100 \
    --concurrency=80 \
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
    echo "Response: $HEALTH_CHECK"
fi

echo -e "\n${GREEN}🎉 Deployment complete!${NC}"
echo -e "Service URL: ${GREEN}$SERVICE_URL${NC}"
echo ""
echo "To view logs: gcloud run logs tail $SERVICE_NAME --project=$PROJECT_ID"