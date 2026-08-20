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

# Public base URL for share links (custom domain mapped to this service)
if [ ! -z "$SHARE_LINK_BASE_URL" ]; then
    ENV_VARS="$ENV_VARS,SHARE_LINK_BASE_URL=$SHARE_LINK_BASE_URL"
fi

# Sticker rewards admin API secret. adminRoutes fails closed without this —
# there is deliberately no default.
if [ ! -z "$ADMIN_SECRET" ]; then
    ENV_VARS="$ENV_VARS,ADMIN_SECRET=$ADMIN_SECRET"
else
    echo -e "${RED}❌ ADMIN_SECRET is not set — /api/admin/* will reject every request${NC}"
    exit 1
fi

# Scheduled task auth (/api/tasks/*). Cloud Scheduler authenticates with a
# Google-signed OIDC token; SCHEDULER_SECRET is break-glass for manual runs.
# Without at least one of these configured every task endpoint denies, so the
# deploy stops rather than silently breaking the nightly jobs.
if [ -z "$SCHEDULER_SECRET" ] && [ -z "$SCHEDULER_SERVICE_ACCOUNT" ]; then
    echo -e "${RED}❌ Neither SCHEDULER_SECRET nor SCHEDULER_SERVICE_ACCOUNT is set — /api/tasks/* would reject Cloud Scheduler${NC}"
    exit 1
fi
if [ ! -z "$SCHEDULER_SECRET" ]; then
    ENV_VARS="$ENV_VARS,SCHEDULER_SECRET=$SCHEDULER_SECRET"
fi
if [ ! -z "$SCHEDULER_OIDC_AUDIENCE" ]; then
    ENV_VARS="$ENV_VARS,SCHEDULER_OIDC_AUDIENCE=$SCHEDULER_OIDC_AUDIENCE"
fi
if [ ! -z "$SCHEDULER_SERVICE_ACCOUNT" ]; then
    ENV_VARS="$ENV_VARS,SCHEDULER_SERVICE_ACCOUNT=$SCHEDULER_SERVICE_ACCOUNT"
fi

# FavCoin on-chain claims (Phase 4, settled via the broker at
# node.cactus-network.net:12444). All optional: without them claiming stays
# disabled (cactusWalletService.isEnabled() is false) and the piggy bank
# behaves exactly as before. Certs/CA travel as base64 (comma-safe); the
# bearer token is required by the broker on every request.
for var in PIGGY_CLAIMS_ENABLED CACTUS_BROKER_URL CACTUS_BROKER_TOKEN CACTUS_BROKER_CA_B64 CACTUS_ASSET_ID CACTUS_RPC_CERT_B64 CACTUS_RPC_KEY_B64 CACTUS_EXPLORER_BASE_URL; do
    value="${!var}"
    if [ ! -z "$value" ]; then
        ENV_VARS="$ENV_VARS,$var=$value"
    fi
done

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

# Circle advisor (LLM). ANTHROPIC_API_KEY is also read by the category
# backfill's optional LLM tier. Without both the key and the flag the advisor
# endpoint reports enabled:false and never calls the model.
if [ ! -z "$ANTHROPIC_API_KEY" ]; then
    ENV_VARS="$ENV_VARS,ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
fi
if [ ! -z "$CIRCLE_ADVISOR_ENABLED" ]; then
    ENV_VARS="$ENV_VARS,CIRCLE_ADVISOR_ENABLED=$CIRCLE_ADVISOR_ENABLED"
fi
if [ ! -z "$CIRCLE_ADVISOR_DAILY_RUNS_PER_USER" ]; then
    ENV_VARS="$ENV_VARS,CIRCLE_ADVISOR_DAILY_RUNS_PER_USER=$CIRCLE_ADVISOR_DAILY_RUNS_PER_USER"
fi
if [ ! -z "$CIRCLE_ADVISOR_DAILY_RUNS_GLOBAL" ]; then
    ENV_VARS="$ENV_VARS,CIRCLE_ADVISOR_DAILY_RUNS_GLOBAL=$CIRCLE_ADVISOR_DAILY_RUNS_GLOBAL"
fi

# Category tier 3 (LLM classifier for the residual 'other' tail). Read by the
# nightly sweep at POST /api/tasks/sweep-categories — never by a request path.
# Without the flag AND ANTHROPIC_API_KEY the sweep reports enabled:false and
# never calls the model.
if [ ! -z "$CATEGORY_LLM_ENABLED" ]; then
    ENV_VARS="$ENV_VARS,CATEGORY_LLM_ENABLED=$CATEGORY_LLM_ENABLED"
fi
if [ ! -z "$MAX_LLM_PLACES" ]; then
    ENV_VARS="$ENV_VARS,MAX_LLM_PLACES=$MAX_LLM_PLACES"
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
    --min-instances=1 \
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