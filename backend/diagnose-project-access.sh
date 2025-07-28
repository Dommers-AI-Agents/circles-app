#!/bin/bash

echo "🔍 Diagnosing Project Access Issues"
echo "==================================="

echo -e "\n1️⃣ Current authenticated account:"
gcloud auth list --filter=status:ACTIVE --format="value(account)"

echo -e "\n2️⃣ All accessible projects (detailed):"
gcloud projects list --format="table(projectId,projectNumber,name,state)"

echo -e "\n3️⃣ Checking specific project access:"
echo "Testing circles-83b67..."
gcloud projects describe circles-83b67 2>&1 | head -20

echo -e "\n4️⃣ Checking Firebase project:"
echo "Testing circles-app-83b67..."
gcloud projects describe circles-app-83b67 2>&1 | head -20

echo -e "\n5️⃣ Looking for any circles-related projects:"
gcloud projects list --filter="projectId:circles" --format="table(projectId,name,state)"

echo -e "\n💡 Next steps:"
echo "1. If you see 'permission denied' for all projects, you may need to:"
echo "   - Re-authenticate: gcloud auth login"
echo "   - Or use a service account with proper permissions"
echo ""
echo "2. The backend might already be deployed. Try checking the service directly:"
echo "   gcloud run services list --region us-central1"
echo ""
echo "3. If you have the Firebase Admin SDK key, use it for deployment:"
echo "   - Download from Firebase Console > Project Settings > Service Accounts"
echo "   - Save as serviceAccountKey.json in backend directory"
echo "   - Run: gcloud auth activate-service-account --key-file=serviceAccountKey.json"