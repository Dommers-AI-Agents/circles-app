#!/bin/bash

# Quick deployment script for code-only updates
# Use this for deploying code changes without updating environment variables
# For full deployment with env var updates, use ./deploy.sh

set -e

SERVICE_NAME="circles-backend"
REGION="us-central1"

echo "🚀 Quick Deploy - Circles Backend"
echo "================================"

# Get current project
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
    echo "❌ No Google Cloud project set"
    echo "Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "📦 Deploying to project: $PROJECT_ID"

# Ensure we're using the correct project
if [ "$PROJECT_ID" != "circles-app-83b67" ]; then
    echo "⚠️  Warning: Current project is $PROJECT_ID, but circles-app-83b67 is the consolidated project"
    echo "Switching to circles-app-83b67..."
    gcloud config set project circles-app-83b67
    PROJECT_ID="circles-app-83b67"
fi

# Deploy
gcloud run deploy $SERVICE_NAME \
    --source . \
    --platform managed \
    --region $REGION \
    --project=$PROJECT_ID \
    --allow-unauthenticated \
    --port=8080

# Get the service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --project=$PROJECT_ID \
    --format 'value(status.url)')

echo ""
echo "✅ Deployment complete!"
echo "Service URL: $SERVICE_URL"
echo "API URL: $SERVICE_URL/api"

# Test the deployment
echo ""
echo "Testing deployment..."
curl -s "$SERVICE_URL/" | jq . 2>/dev/null || curl -s "$SERVICE_URL/"