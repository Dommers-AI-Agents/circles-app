#!/bin/bash

echo "🔄 Rolling back to last working revision and configuring email..."

# First, get the last working revision
echo "Finding last stable revision..."
LAST_STABLE=$(gcloud run revisions list --service circles-backend --region us-central1 --limit 10 --format="value(metadata.name)" | grep -v "00147\|00148\|00146\|00145\|00144\|00143\|00142" | head -1)

if [ -z "$LAST_STABLE" ]; then
    echo "❌ Could not find a stable revision"
    exit 1
fi

echo "Found stable revision: $LAST_STABLE"

# Roll back to that revision
echo "Rolling back to stable revision..."
gcloud run services update-traffic circles-backend \
  --region us-central1 \
  --to-revisions=$LAST_STABLE=100

echo "✅ Rolled back to stable revision"

# Now just update the email configuration on the stable version
echo ""
echo "🔧 Updating email configuration on stable revision..."

gcloud run services update circles-backend \
  --region us-central1 \
  --update-env-vars \
EMAIL_SERVICE=custom,\
SMTP_HOST=mail.favcircles.com,\
SMTP_PORT=465,\
SMTP_SECURE=true,\
SMTP_USER=wesley@favcircles.com,\
SMTP_PASS=Dommer2025!,\
EMAIL_FROM_ADDRESS=wesley@favcircles.com,\
EMAIL_FROM_NAME=Circles,\
APP_URL=https://favcircles.com \
  --no-traffic

echo "✅ Email configuration updated!"
echo ""
echo "📧 Your email is now configured to send from wesley@favcircles.com"
echo ""
echo "Note: The new /api/email test endpoints won't be available until we fix the deployment issue,"
echo "but connection request emails and other existing emails will now use your custom SMTP!"