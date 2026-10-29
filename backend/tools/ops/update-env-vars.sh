#!/bin/bash

# Script to update environment variables on Cloud Run

set -e

SERVICE_NAME="circles-backend"
REGION="us-central1"

echo "🔧 Update Environment Variables - Circles Backend"
echo "==============================================="

# Get current project
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
    echo "❌ No Google Cloud project set"
    echo "Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo "Service: $SERVICE_NAME"
echo "Project: $PROJECT_ID"
echo ""

# Show current environment variables
echo "Current environment variables:"
gcloud run services describe $SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --project=$PROJECT_ID \
    --format="yaml(spec.template.spec.containers[0].env[].name)"

echo ""
echo "What would you like to do?"
echo "1. Add/Update a single variable"
echo "2. Update all variables from .env file"
echo "3. Remove a variable"
echo "4. View all current variables"

read -p "Choose an option (1-4): " choice

case $choice in
    1)
        read -p "Variable name: " VAR_NAME
        read -p "Variable value: " VAR_VALUE
        
        echo "Updating $VAR_NAME..."
        gcloud run services update $SERVICE_NAME \
            --update-env-vars "$VAR_NAME=$VAR_VALUE" \
            --region=$REGION \
            --project=$PROJECT_ID
        ;;
    
    2)
        if [ ! -f ".env" ]; then
            echo "❌ .env file not found"
            exit 1
        fi
        
        echo "Loading variables from .env..."
        ENV_VARS=""
        # Reserved Cloud Run environment variables to skip
        RESERVED_VARS="PORT|K_SERVICE|K_REVISION|K_CONFIGURATION"
        
        while IFS='=' read -r key value; do
            # Skip comments, empty lines, and reserved variables
            if [[ ! "$key" =~ ^[[:space:]]*# ]] && [[ -n "$key" ]] && [[ ! "$key" =~ ^($RESERVED_VARS)$ ]]; then
                # Remove quotes from value if present
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"
                if [ -n "$ENV_VARS" ]; then
                    ENV_VARS="$ENV_VARS,$key=$value"
                else
                    ENV_VARS="$key=$value"
                fi
                echo "  Adding: $key"
            elif [[ "$key" =~ ^($RESERVED_VARS)$ ]]; then
                echo "  Skipping reserved variable: $key"
            fi
        done < .env
        
        echo "Updating all variables..."
        gcloud run services update $SERVICE_NAME \
            --set-env-vars "$ENV_VARS" \
            --region=$REGION \
            --project=$PROJECT_ID
        ;;
    
    3)
        read -p "Variable name to remove: " VAR_NAME
        
        echo "Removing $VAR_NAME..."
        gcloud run services update $SERVICE_NAME \
            --remove-env-vars "$VAR_NAME" \
            --region=$REGION \
            --project=$PROJECT_ID
        ;;
    
    4)
        echo "All environment variables:"
        gcloud run services describe $SERVICE_NAME \
            --platform managed \
            --region $REGION \
            --project=$PROJECT_ID \
            --format="table(spec.template.spec.containers[0].env[].name,spec.template.spec.containers[0].env[].value)"
        ;;
    
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo "✅ Done!"