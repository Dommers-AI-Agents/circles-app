#!/bin/bash

echo "🔥 Deploying Firestore indexes..."
echo "================================"

# The deployed index file is the one at the repo ROOT (firebase.json there
# points at firestore.indexes.json). Run from wherever; deploy from the root.
cd "$(git rev-parse --show-toplevel)" || exit 1

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Please install it with: npm install -g firebase-tools"
    exit 1
fi

# Check if gcloud is configured
PROJECT_ID="circles-app-83b67"
echo "📦 Using project: $PROJECT_ID"

# Deploy indexes
echo "📋 Deploying Firestore indexes..."
firebase deploy --only firestore:indexes --project $PROJECT_ID

if [ $? -eq 0 ]; then
    echo "✅ Firestore indexes deployed successfully!"
else
    echo "❌ Failed to deploy indexes"
    exit 1
fi

echo ""
echo "📝 Note: Indexes may take a few minutes to build in Firestore"
echo "You can monitor progress at: https://console.firebase.google.com/project/$PROJECT_ID/firestore/indexes"