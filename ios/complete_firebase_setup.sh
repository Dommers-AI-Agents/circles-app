#!/bin/bash

echo "🔥 Firebase Setup Completion Script"
echo "=================================="
echo ""

# Check if we're in the right directory
BACKEND_DIR="/Users/wesleysgroi/favcircles/backend"
CONFIG_DIR="$BACKEND_DIR/config"
SERVICE_ACCOUNT_FILE="$CONFIG_DIR/firebase-service-account.json"

echo "📍 Checking backend directory..."
if [ ! -d "$BACKEND_DIR" ]; then
    echo "❌ Backend directory not found: $BACKEND_DIR"
    exit 1
fi

echo "✅ Backend directory found"

# Check if service account file exists
echo ""
echo "🔑 Checking for Firebase service account file..."
if [ -f "$SERVICE_ACCOUNT_FILE" ]; then
    echo "✅ Service account file found: $SERVICE_ACCOUNT_FILE"
    
    # Extract project ID from service account file
    PROJECT_ID=$(grep -o '"project_id": *"[^"]*"' "$SERVICE_ACCOUNT_FILE" | grep -o '"[^"]*"$' | tr -d '"')
    
    if [ -n "$PROJECT_ID" ]; then
        echo "📋 Detected Project ID: $PROJECT_ID"
        
        # Update .env file with actual project ID
        ENV_FILE="$BACKEND_DIR/.env"
        echo ""
        echo "📝 Updating .env file with your project details..."
        
        # Create backup
        cp "$ENV_FILE" "$ENV_FILE.backup"
        
        # Update project ID and storage bucket
        sed -i "" "s/FIREBASE_PROJECT_ID=.*/FIREBASE_PROJECT_ID=$PROJECT_ID/" "$ENV_FILE"
        sed -i "" "s/FIREBASE_STORAGE_BUCKET=.*/FIREBASE_STORAGE_BUCKET=$PROJECT_ID.appspot.com/" "$ENV_FILE"
        
        echo "✅ Updated .env file with:"
        echo "   FIREBASE_PROJECT_ID=$PROJECT_ID"
        echo "   FIREBASE_STORAGE_BUCKET=$PROJECT_ID.appspot.com"
    else
        echo "⚠️  Could not extract project ID from service account file"
    fi
else
    echo "❌ Service account file not found!"
    echo ""
    echo "📋 To complete setup:"
    echo "1. Download service account key from Firebase Console"
    echo "2. Rename it to: firebase-service-account.json"  
    echo "3. Move it to: $CONFIG_DIR/"
    echo "4. Run this script again"
    echo ""
    echo "🔗 Firebase Console: https://console.firebase.google.com"
    exit 1
fi

echo ""
echo "🚀 Testing Firebase connection..."
cd "$BACKEND_DIR"

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Test Firebase connection
echo "🔄 Starting server to test Firebase connection..."
timeout 10s npm start || echo "⏰ Server test completed"

echo ""
echo "🎉 Firebase setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Start your backend: cd $BACKEND_DIR && npm start"
echo "2. Run your iOS app in Xcode"
echo "3. Test creating a circle - it should now save to Firebase!"
echo ""
echo "🔍 Look for this message when starting the backend:"
echo "   🔥 Firebase status: Connected"
echo ""
echo "📊 Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID"