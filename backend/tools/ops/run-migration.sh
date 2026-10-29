#!/bin/bash

# Script to run the legacy places migration
# This will create Global Places for all legacy places and add globalPlaceId references

set -e

echo "🚀 Legacy Places Migration Script"
echo "================================="

# Check if we're in the backend directory
if [ ! -f "package.json" ]; then
    echo "❌ Error: This script must be run from the backend directory"
    exit 1
fi

# Default to dry run for safety
DRY_RUN=${DRY_RUN:-true}

if [ "$DRY_RUN" = "true" ]; then
    echo "🔍 Running in DRY RUN mode (no changes will be made)"
    echo "   To run live migration, set DRY_RUN=false"
else
    echo "⚠️  WARNING: Running in LIVE MIGRATION mode"
    echo "   This will make actual changes to the database"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    if [ "$confirmation" != "yes" ]; then
        echo "❌ Migration cancelled"
        exit 1
    fi
fi

echo ""
echo "📋 Migration will:"
echo "   1. Find all legacy places without globalPlaceId"
echo "   2. Create corresponding Global Place entries"
echo "   3. Add globalPlaceId references to legacy places"
echo "   4. Merge duplicate places based on Google Place ID"
echo ""

# Set Google Application Credentials if not already set
if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
    export GOOGLE_APPLICATION_CREDENTIALS="./config/firebase-service-account.json"
    echo "🔑 Using Firebase service account: $GOOGLE_APPLICATION_CREDENTIALS"
fi

# Run the migration
echo "🚀 Starting migration..."
echo ""

DRY_RUN=$DRY_RUN node scripts/migrate-legacy-places.js

echo ""
echo "✅ Migration script completed!"

if [ "$DRY_RUN" = "true" ]; then
    echo ""
    echo "💡 To run the actual migration:"
    echo "   DRY_RUN=false ./run-migration.sh"
fi