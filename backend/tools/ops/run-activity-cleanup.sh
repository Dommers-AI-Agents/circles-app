#!/bin/bash

# Script to manually trigger activity cleanup on the deployed backend

echo "🧹 Triggering activity cleanup on deployed backend..."

# Get the service URL
SERVICE_URL="https://circles-backend-196924649787.us-central1.run.app"

# Call the cleanup endpoint
echo "Calling cleanup endpoint..."
curl -X POST "$SERVICE_URL/api/connections/admin/cleanup-activities" \
  -H "Content-Type: application/json" \
  -d '{"daysToKeep": 1}' \
  --silent \
  --show-error | jq . || echo "Response: $(curl -X POST "$SERVICE_URL/api/connections/admin/cleanup-activities" -H "Content-Type: application/json" -d '{"daysToKeep": 1}' --silent)"

echo ""
echo "✅ Cleanup request sent. Old activities should now be removed."
echo "Please refresh the app to see the updated activity dots."