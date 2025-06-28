#!/bin/bash

# Circles Backend Deployment Script for Google Cloud Run
# This script deploys your Express.js backend to Google Cloud Run

set -e  # Exit on error

echo "🚀 Circles Backend Deployment Script"
echo "===================================="

# Configuration
PROJECT_ID=""
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

# Get or set project ID
if [ -z "$PROJECT_ID" ]; then
    echo -e "\n${YELLOW}Select or create a Google Cloud Project:${NC}"
    echo "Current project: $(gcloud config get-value project 2>/dev/null || echo 'None set')"
    read -p "Enter project ID (or press Enter to use current): " input_project
    
    if [ -z "$input_project" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            echo -e "${RED}No project set. Please enter a project ID.${NC}"
            exit 1
        fi
    else
        PROJECT_ID=$input_project
        gcloud config set project $PROJECT_ID
    fi
fi

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
fi

# Collect environment variables
echo -e "\n${YELLOW}Setting up environment variables...${NC}"
echo "Please provide the following values (press Enter to skip):"

read -p "JWT_SECRET (required): " INPUT_JWT_SECRET
JWT_SECRET=${INPUT_JWT_SECRET:-$JWT_SECRET}

read -p "JWT_EXPIRE (default: 30d): " INPUT_JWT_EXPIRE
JWT_EXPIRE=${INPUT_JWT_EXPIRE:-${JWT_EXPIRE:-"30d"}}

# Firebase Configuration
echo -e "\n${YELLOW}Firebase Configuration:${NC}"
read -p "FIREBASE_PROJECT_ID (default: $PROJECT_ID): " INPUT_FIREBASE_PROJECT_ID
FIREBASE_PROJECT_ID=${INPUT_FIREBASE_PROJECT_ID:-${FIREBASE_PROJECT_ID:-$PROJECT_ID}}

# Check for existing Firebase Storage buckets
echo "Checking for existing Firebase Storage buckets..."
EXISTING_BUCKET=$(gcloud storage buckets list --project=$FIREBASE_PROJECT_ID --format="value(name)" 2>/dev/null | grep -E "(${FIREBASE_PROJECT_ID}\.(appspot\.com|firebasestorage\.app))" | head -1)

if [ -n "$EXISTING_BUCKET" ]; then
    echo -e "${GREEN}Found existing bucket: $EXISTING_BUCKET${NC}"
    DEFAULT_BUCKET=$EXISTING_BUCKET
else
    DEFAULT_BUCKET="${FIREBASE_PROJECT_ID}.firebasestorage.app"
fi

read -p "FIREBASE_STORAGE_BUCKET (default: $DEFAULT_BUCKET): " INPUT_FIREBASE_STORAGE_BUCKET
FIREBASE_STORAGE_BUCKET=${INPUT_FIREBASE_STORAGE_BUCKET:-${FIREBASE_STORAGE_BUCKET:-"$DEFAULT_BUCKET"}}

# Optional LinkedIn Configuration
echo -e "\n${YELLOW}LinkedIn OAuth (optional):${NC}"
read -p "LINKEDIN_CLIENT_ID: " INPUT_LINKEDIN_CLIENT_ID
LINKEDIN_CLIENT_ID=${INPUT_LINKEDIN_CLIENT_ID:-$LINKEDIN_CLIENT_ID}

read -p "LINKEDIN_CLIENT_SECRET: " INPUT_LINKEDIN_CLIENT_SECRET
LINKEDIN_CLIENT_SECRET=${INPUT_LINKEDIN_CLIENT_SECRET:-$LINKEDIN_CLIENT_SECRET}

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
ENV_VARS="$ENV_VARS,FIREBASE_STORAGE_BUCKET=$FIREBASE_STORAGE_BUCKET"
ENV_VARS="$ENV_VARS,GCS_BUCKET_NAME=$FIREBASE_STORAGE_BUCKET"

if [ ! -z "$LINKEDIN_CLIENT_ID" ]; then
    ENV_VARS="$ENV_VARS,LINKEDIN_CLIENT_ID=$LINKEDIN_CLIENT_ID"
fi

if [ ! -z "$LINKEDIN_CLIENT_SECRET" ]; then
    ENV_VARS="$ENV_VARS,LINKEDIN_CLIENT_SECRET=$LINKEDIN_CLIENT_SECRET"
fi

# Deploy to Cloud Run
echo -e "\n${YELLOW}Deploying to Cloud Run...${NC}"
echo "Service name: $SERVICE_NAME"
echo "Region: $REGION"
echo "Project: $PROJECT_ID"

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
    --concurrency=80

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

# Create iOS configuration update file
echo -e "\n${YELLOW}Creating iOS configuration update...${NC}"

cat > ios-config-update.txt << EOF
Update your iOS app's APIService.swift file:

Replace this line in the production case:
    return "https://api.circles-app.com/api"

With:
    return "$SERVICE_URL/api"

Full production URL: $SERVICE_URL/api
EOF

echo -e "${GREEN}✅ iOS configuration saved to ios-config-update.txt${NC}"

# Test the deployment
echo -e "\n${YELLOW}Testing deployment...${NC}"
HEALTH_CHECK=$(curl -s "$SERVICE_URL/" || echo "Failed")

if [[ $HEALTH_CHECK == *"Circles API"* ]]; then
    echo -e "${GREEN}✅ API is responding correctly${NC}"
    echo "$HEALTH_CHECK" | jq . 2>/dev/null || echo "$HEALTH_CHECK"
else
    echo -e "${RED}❌ API health check failed${NC}"
    echo "Response: $HEALTH_CHECK"
fi

echo -e "\n${GREEN}🎉 Deployment complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Update your iOS app with the new API URL"
echo "2. Test your app with TestFlight"
echo "3. Monitor logs: gcloud run logs tail $SERVICE_NAME --project=$PROJECT_ID"
echo ""
echo "Useful commands:"
echo "- View logs: gcloud run logs read $SERVICE_NAME --project=$PROJECT_ID"
echo "- Update env vars: gcloud run services update $SERVICE_NAME --update-env-vars KEY=VALUE --region=$REGION --project=$PROJECT_ID"
echo "- Describe service: gcloud run services describe $SERVICE_NAME --region=$REGION --project=$PROJECT_ID"