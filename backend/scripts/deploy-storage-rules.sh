#!/bin/bash

# Script to deploy Firebase Storage rules

echo "🚀 Deploying Firebase Storage rules..."
echo ""

# Change to the project root directory
cd /Users/wesleysgroi/circles-app

# Check if firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI is not installed."
    echo "📝 Install it with: npm install -g firebase-tools"
    exit 1
fi

# Check if storage.rules exists
if [ ! -f "storage.rules" ]; then
    echo "❌ storage.rules file not found in project root."
    exit 1
fi

# Check if firebase.json exists
if [ ! -f "firebase.json" ]; then
    echo "❌ firebase.json file not found in project root."
    exit 1
fi

# Show current project
echo "📋 Current Firebase project configuration:"
firebase projects:list

echo ""
echo "🔍 Deploying to project: circles-app-83b67"
echo ""

# Deploy storage rules
firebase deploy --only storage --project circles-app-83b67

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Storage rules deployed successfully!"
    echo ""
    echo "📝 Next steps:"
    echo "1. Run the migration script to identify old image URLs:"
    echo "   cd /Users/wesleysgroi/circles-app/backend"
    echo "   node scripts/migrate-storage-urls.js"
    echo ""
    echo "2. Consider setting up CORS if needed:"
    echo "   gsutil cors set cors.json gs://circles-app-83b67.firebasestorage.app"
else
    echo ""
    echo "❌ Failed to deploy storage rules."
    echo "📝 Make sure you're authenticated with Firebase:"
    echo "   firebase login"
fi