#!/bin/bash

# Script to manually register FCM token
# Usage: ./register-fcm-token.sh [auth-token] [fcm-token]

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: ./register-fcm-token.sh [auth-token] [fcm-token]"
    echo "Example: ./register-fcm-token.sh eyJhbGci... cFCM_token_here..."
    exit 1
fi

AUTH_TOKEN=$1
FCM_TOKEN=$2
API_URL="${API_URL:-https://circles-backend-kcyohp6zra-uc.a.run.app}"

echo "📱 Registering FCM token..."
echo "API URL: $API_URL"

curl -X POST "$API_URL/api/users/device-token" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"token\": \"$FCM_TOKEN\",
    \"platform\": \"ios\"
  }"

echo ""
echo ""
echo "✅ Token registration complete!"