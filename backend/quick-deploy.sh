#!/bin/bash

# Quick deployment script for updates
# Run this after initial deployment to quickly push changes

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

# Deploy
gcloud run deploy $SERVICE_NAME \
    --source . \
    --platform managed \
    --region $REGION \
    --project=$PROJECT_ID

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