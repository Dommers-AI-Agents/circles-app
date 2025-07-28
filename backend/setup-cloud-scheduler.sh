#!/bin/bash

# Script to set up Google Cloud Scheduler jobs for Circles app
# This script creates scheduled jobs that trigger the backend API endpoints

set -e

# Configuration
PROJECT_ID="circles-app-83b67"
REGION="us-central1"
SERVICE_URL="https://circles-backend-196924649787.us-central1.run.app"
SERVICE_ACCOUNT="circles-backend@circles-app-83b67.iam.gserviceaccount.com"
TIME_ZONE="America/New_York"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🕐 Setting up Google Cloud Scheduler jobs for Circles app${NC}"
echo "Project: $PROJECT_ID"
echo "Region: $REGION"
echo "Service URL: $SERVICE_URL"
echo ""

# Ensure gcloud is configured
echo -e "${YELLOW}Checking gcloud configuration...${NC}"
gcloud config set project $PROJECT_ID

# Enable required APIs
echo -e "${YELLOW}Enabling required APIs...${NC}"
gcloud services enable cloudscheduler.googleapis.com --project=$PROJECT_ID
gcloud services enable run.googleapis.com --project=$PROJECT_ID

# Create Cloud Scheduler jobs

# 1. Daily Summary - 12:00 PM EST every day
echo -e "${GREEN}Creating daily summary job...${NC}"
gcloud scheduler jobs delete daily-summary --location=$REGION --quiet 2>/dev/null || true
gcloud scheduler jobs create http daily-summary \
  --location=$REGION \
  --schedule="0 12 * * *" \
  --uri="${SERVICE_URL}/api/tasks/daily-summary" \
  --http-method=POST \
  --oidc-service-account-email=$SERVICE_ACCOUNT \
  --time-zone=$TIME_ZONE \
  --description="Send daily summary notifications to users at noon" \
  --headers="Content-Type=application/json,X-Cloudscheduler=true" \
  --attempt-deadline=180s

# 2. Morning Discovery - 8:30 AM EST weekdays
echo -e "${GREEN}Creating morning discovery job...${NC}"
gcloud scheduler jobs delete morning-discovery --location=$REGION --quiet 2>/dev/null || true
gcloud scheduler jobs create http morning-discovery \
  --location=$REGION \
  --schedule="30 8 * * 1-5" \
  --uri="${SERVICE_URL}/api/tasks/morning-discovery" \
  --http-method=POST \
  --oidc-service-account-email=$SERVICE_ACCOUNT \
  --time-zone=$TIME_ZONE \
  --description="Send morning coffee discovery prompts on weekdays" \
  --headers="Content-Type=application/json,X-Cloudscheduler=true" \
  --attempt-deadline=180s

# 3. Lunch Discovery - 11:45 AM EST weekdays
echo -e "${GREEN}Creating lunch discovery job...${NC}"
gcloud scheduler jobs delete lunch-discovery --location=$REGION --quiet 2>/dev/null || true
gcloud scheduler jobs create http lunch-discovery \
  --location=$REGION \
  --schedule="45 11 * * 1-5" \
  --uri="${SERVICE_URL}/api/tasks/lunch-discovery" \
  --http-method=POST \
  --oidc-service-account-email=$SERVICE_ACCOUNT \
  --time-zone=$TIME_ZONE \
  --description="Send lunch discovery prompts on weekdays" \
  --headers="Content-Type=application/json,X-Cloudscheduler=true" \
  --attempt-deadline=180s

# 4. Weekend Recommendations - 5:00 PM EST Fridays
echo -e "${GREEN}Creating weekend recommendations job...${NC}"
gcloud scheduler jobs delete weekend-recommendations --location=$REGION --quiet 2>/dev/null || true
gcloud scheduler jobs create http weekend-recommendations \
  --location=$REGION \
  --schedule="0 17 * * 5" \
  --uri="${SERVICE_URL}/api/tasks/weekend-recommendations" \
  --http-method=POST \
  --oidc-service-account-email=$SERVICE_ACCOUNT \
  --time-zone=$TIME_ZONE \
  --description="Send weekend place recommendations on Friday evenings" \
  --headers="Content-Type=application/json,X-Cloudscheduler=true" \
  --attempt-deadline=180s

echo -e "${GREEN}✅ All scheduler jobs created successfully!${NC}"
echo ""
echo "View all jobs:"
echo "  gcloud scheduler jobs list --location=$REGION"
echo ""
echo "Test a job manually:"
echo "  gcloud scheduler jobs run daily-summary --location=$REGION"
echo ""
echo "View job details:"
echo "  gcloud scheduler jobs describe daily-summary --location=$REGION"
echo ""
echo -e "${YELLOW}Note: Jobs will run automatically according to their schedules.${NC}"
echo -e "${YELLOW}The service account ${SERVICE_ACCOUNT} must have permission to invoke the Cloud Run service.${NC}"