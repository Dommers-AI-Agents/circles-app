#!/bin/bash

# This script updates the Cloud Run service with necessary environment variables
# It reads from .env file and updates the deployment

echo "Updating Cloud Run environment variables..."

# Read .env file and set environment variables
if [ -f .env ]; then
    # Extract required variables
    JWT_SECRET=$(grep "^JWT_SECRET=" .env | cut -d '=' -f2-)
    JWT_EXPIRE=$(grep "^JWT_EXPIRE=" .env | cut -d '=' -f2- || echo "30d")
    FIREBASE_PROJECT_ID=$(grep "^FIREBASE_PROJECT_ID=" .env | cut -d '=' -f2-)
    GOOGLE_MAPS_API_KEY=$(grep "^GOOGLE_MAPS_API_KEY=" .env | cut -d '=' -f2-)
    GOOGLE_PLACES_API_KEY=$(grep "^GOOGLE_PLACES_API_KEY=" .env | cut -d '=' -f2-)
    GCS_BUCKET_NAME=$(grep "^GCS_BUCKET_NAME=" .env | cut -d '=' -f2-)
    FRONTEND_URL=$(grep "^FRONTEND_URL=" .env | cut -d '=' -f2- || echo "https://circles-app-83b67.web.app")
    APP_SCHEME=$(grep "^APP_SCHEME=" .env | cut -d '=' -f2- || echo "circles://")
    
    # Update Cloud Run service with environment variables
    gcloud run services update circles-backend \
        --region us-central1 \
        --update-env-vars JWT_SECRET="$JWT_SECRET",JWT_EXPIRE="$JWT_EXPIRE",FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID",GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY",GOOGLE_PLACES_API_KEY="$GOOGLE_PLACES_API_KEY",GCS_BUCKET_NAME="$GCS_BUCKET_NAME",FRONTEND_URL="$FRONTEND_URL",APP_SCHEME="$APP_SCHEME",NODE_ENV=production
    
    echo "Environment variables updated successfully!"
else
    echo "Error: .env file not found"
    exit 1
fi