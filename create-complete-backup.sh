#!/bin/bash

# create-complete-backup.sh
# Comprehensive backup script for Circles app before place normalization changes

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="$HOME/Desktop/circles-backups"
PROJECT_ROOT="/Users/wesleysgroi/circles-app"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo -e "${BLUE}🚀 Starting comprehensive backup process...${NC}"
echo -e "${BLUE}Timestamp: ${TIMESTAMP}${NC}"

# Create backup directory
mkdir -p "${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}/database"
mkdir -p "${BACKUP_DIR}/code"
mkdir -p "${BACKUP_DIR}/git"

# Change to project root
cd "${PROJECT_ROOT}"

echo -e "\n${YELLOW}📋 Current Git Status:${NC}"
git status --short

# 1. Git Repository Backup
echo -e "\n${BLUE}🗃️  Creating Git repository backup...${NC}"

# Check if we're in a clean state
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${YELLOW}⚠️  Warning: Working directory has uncommitted changes${NC}"
    echo -e "${YELLOW}📝 Stashing changes before backup...${NC}"
    git stash push -m "Pre-backup stash - ${TIMESTAMP}"
fi

# Create backup branch
BACKUP_BRANCH="backup/pre-place-normalization-${TIMESTAMP}"
echo -e "${GREEN}🌿 Creating backup branch: ${BACKUP_BRANCH}${NC}"
git checkout -b "${BACKUP_BRANCH}"
git push origin "${BACKUP_BRANCH}"

# Return to main
git checkout main
git pull origin main

# Create feature branch for development
FEATURE_BRANCH="feature/place-normalization"
echo -e "${GREEN}🌿 Creating feature branch: ${FEATURE_BRANCH}${NC}"
git checkout -b "${FEATURE_BRANCH}"

# Export git history and branches
echo -e "${BLUE}📦 Exporting git metadata...${NC}"
git log --oneline -20 > "${BACKUP_DIR}/git/recent-commits-${TIMESTAMP}.txt"
git branch -a > "${BACKUP_DIR}/git/all-branches-${TIMESTAMP}.txt"
git remote -v > "${BACKUP_DIR}/git/remotes-${TIMESTAMP}.txt"

echo -e "${GREEN}✅ Git backup completed${NC}"

# 2. Code Archive Backup
echo -e "\n${BLUE}📦 Creating complete code archive...${NC}"

# Create tar archive excluding large/unnecessary files
tar -czf "${BACKUP_DIR}/code/circles-app-${TIMESTAMP}.tar.gz" \
  --exclude=node_modules \
  --exclude=.git \
  --exclude=ios/Pods \
  --exclude=ios/build \
  --exclude=ios/DerivedData \
  --exclude="*.log" \
  --exclude=backend/logs \
  --exclude=.DS_Store \
  "${PROJECT_ROOT}"

echo -e "${GREEN}✅ Code archive created: $(ls -lh "${BACKUP_DIR}/code/circles-app-${TIMESTAMP}.tar.gz" | awk '{print $5}')${NC}"

# 3. Individual Critical Files Backup
echo -e "\n${BLUE}📄 Backing up critical individual files...${NC}"

CRITICAL_FILES=(
  "backend/models/FirestoreModels.js"
  "backend/controllers/placeController.js"
  "backend/controllers/firebasePlaceController.js"
  "backend/controllers/circleController.js"
  "ios/Circles-iOS-UIKit/Models/Place.swift"
  "ios/Circles-iOS-UIKit/Models/Circle.swift"
  "ios/Circles-iOS-UIKit/Services/PlaceService.swift"
  "backend/package.json"
  "ios/Circles-iOS-UIKit.xcodeproj/project.pbxproj"
)

mkdir -p "${BACKUP_DIR}/code/critical-files"

for file in "${CRITICAL_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        # Create directory structure in backup
        backup_path="${BACKUP_DIR}/code/critical-files/${file}"
        mkdir -p "$(dirname "$backup_path")"
        cp "$file" "$backup_path"
        echo -e "${GREEN}✅ Backed up: ${file}${NC}"
    else
        echo -e "${RED}❌ File not found: ${file}${NC}"
    fi
done

# 4. Database Backup
echo -e "\n${BLUE}🗄️  Starting database backup...${NC}"

# Check if Node.js and dependencies are available
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js not found. Please install Node.js to run database backup${NC}"
    exit 1
fi

# Change to backend directory and run database backup
cd "${PROJECT_ROOT}/backend"

# Install dependencies if needed
if [[ ! -d "node_modules" ]]; then
    echo -e "${YELLOW}📦 Installing Node.js dependencies...${NC}"
    npm install
fi

# Run database backup script
echo -e "${BLUE}🔄 Running database backup script...${NC}"
if [[ -f "scripts/backup-critical-data.js" ]]; then
    node scripts/backup-critical-data.js
    
    # Copy database backups to main backup directory
    if [[ -d "backups" ]]; then
        cp -r backups/* "${BACKUP_DIR}/database/"
        echo -e "${GREEN}✅ Database backups copied to main backup directory${NC}"
    fi
else
    echo -e "${RED}❌ Database backup script not found${NC}"
fi

# 5. Firebase Storage Backup (if gsutil is available)
echo -e "\n${BLUE}☁️  Checking Firebase Storage backup...${NC}"

if command -v gsutil &> /dev/null; then
    echo -e "${BLUE}🔄 Backing up Firebase Storage...${NC}"
    
    # Create storage backup directory
    mkdir -p "${BACKUP_DIR}/storage"
    
    # Export storage rules
    gsutil cp gs://circles-app-83b67.appspot.com/.storage.rules "${BACKUP_DIR}/storage/storage-rules-${TIMESTAMP}.txt" 2>/dev/null || echo -e "${YELLOW}⚠️  Could not backup storage rules${NC}"
    
    # List storage contents for reference
    gsutil ls -r gs://circles-app-83b67.appspot.com/ > "${BACKUP_DIR}/storage/storage-inventory-${TIMESTAMP}.txt" 2>/dev/null || echo -e "${YELLOW}⚠️  Could not list storage contents${NC}"
    
    echo -e "${GREEN}✅ Firebase Storage inventory created${NC}"
    echo -e "${YELLOW}ℹ️  Note: Complete media backup requires manual gsutil commands due to size${NC}"
else
    echo -e "${YELLOW}⚠️  gsutil not found - skipping Firebase Storage backup${NC}"
    echo -e "${YELLOW}ℹ️  Install Google Cloud SDK for storage backups${NC}"
fi

# 6. Create Backup Summary
echo -e "\n${BLUE}📋 Creating backup summary...${NC}"

cat > "${BACKUP_DIR}/backup-summary-${TIMESTAMP}.txt" << EOF
Circles App Complete Backup Summary
Generated: $(date)
Timestamp: ${TIMESTAMP}

=== Git Backup ===
Backup Branch: ${BACKUP_BRANCH}
Feature Branch: ${FEATURE_BRANCH}
Current Commit: $(git rev-parse HEAD)
Status: $(git status --porcelain | wc -l) modified files

=== Code Backup ===
Archive: circles-app-${TIMESTAMP}.tar.gz
Size: $(ls -lh "${BACKUP_DIR}/code/circles-app-${TIMESTAMP}.tar.gz" | awk '{print $5}')
Critical Files: ${#CRITICAL_FILES[@]} files backed up

=== Database Backup ===
Location: ${BACKUP_DIR}/database/
Collections: places, circles, users, placeVideos
Backup Script: $(test -f "${PROJECT_ROOT}/backend/scripts/backup-critical-data.js" && echo "✅ Available" || echo "❌ Missing")

=== Firebase Storage ===
gsutil: $(command -v gsutil &> /dev/null && echo "✅ Available" || echo "❌ Not installed")
Rules Backup: $(test -f "${BACKUP_DIR}/storage/storage-rules-${TIMESTAMP}.txt" && echo "✅ Created" || echo "❌ Failed")

=== Backup Locations ===
Main Directory: ${BACKUP_DIR}
Code Archive: ${BACKUP_DIR}/code/
Database: ${BACKUP_DIR}/database/
Git Info: ${BACKUP_DIR}/git/
Storage: ${BACKUP_DIR}/storage/

=== Rollback Commands ===
Git Rollback: git checkout ${BACKUP_BRANCH}
Code Restore: tar -xzf ${BACKUP_DIR}/code/circles-app-${TIMESTAMP}.tar.gz
Database Rollback: cd backend && node scripts/rollback-database.js list

=== Next Steps ===
1. Verify all backups are complete
2. Test rollback procedures in development
3. Proceed with place normalization implementation
4. Keep this backup until changes are stable
EOF

echo -e "${GREEN}✅ Backup summary created${NC}"

# 7. Verify Backup Integrity
echo -e "\n${BLUE}🔍 Verifying backup integrity...${NC}"

# Check file sizes and existence
backup_checks=0
backup_passed=0

# Check code archive
if [[ -f "${BACKUP_DIR}/code/circles-app-${TIMESTAMP}.tar.gz" ]]; then
    size=$(ls -la "${BACKUP_DIR}/code/circles-app-${TIMESTAMP}.tar.gz" | awk '{print $5}')
    if [[ $size -gt 1000000 ]]; then  # > 1MB
        echo -e "${GREEN}✅ Code archive: OK (${size} bytes)${NC}"
        ((backup_passed++))
    else
        echo -e "${RED}❌ Code archive: Too small (${size} bytes)${NC}"
    fi
    ((backup_checks++))
fi

# Check database backups
if [[ -d "${BACKUP_DIR}/database" ]] && [[ $(ls -1 "${BACKUP_DIR}/database"/*.json 2>/dev/null | wc -l) -gt 0 ]]; then
    echo -e "${GREEN}✅ Database backups: OK ($(ls -1 "${BACKUP_DIR}/database"/*.json | wc -l) files)${NC}"
    ((backup_passed++))
else
    echo -e "${RED}❌ Database backups: Missing or empty${NC}"
fi
((backup_checks++))

# Check git backup
if git show-ref --verify --quiet "refs/heads/${BACKUP_BRANCH}"; then
    echo -e "${GREEN}✅ Git backup branch: OK${NC}"
    ((backup_passed++))
else
    echo -e "${RED}❌ Git backup branch: Failed${NC}"
fi
((backup_checks++))

# 8. Final Report
echo -e "\n${BLUE}📊 Backup Completion Report${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "Timestamp: ${TIMESTAMP}"
echo -e "Backup Directory: ${BACKUP_DIR}"
echo -e "Checks Passed: ${backup_passed}/${backup_checks}"

if [[ $backup_passed -eq $backup_checks ]]; then
    echo -e "\n${GREEN}🎉 All backups completed successfully!${NC}"
    echo -e "${GREEN}✅ Ready to proceed with place normalization${NC}"
    
    # Create success marker file
    echo "SUCCESS: All backups completed at $(date)" > "${BACKUP_DIR}/.backup-complete"
    
else
    echo -e "\n${RED}❌ Some backups failed - please review and fix before proceeding${NC}"
    exit 1
fi

echo -e "\n${BLUE}📋 Important Files:${NC}"
echo -e "Summary: ${BACKUP_DIR}/backup-summary-${TIMESTAMP}.txt"
echo -e "Code Archive: ${BACKUP_DIR}/code/circles-app-${TIMESTAMP}.tar.gz"
echo -e "Database: ${BACKUP_DIR}/database/"

echo -e "\n${YELLOW}🚨 Remember:${NC}"
echo -e "- Keep these backups until changes are stable"
echo -e "- Test rollback procedures before proceeding"
echo -e "- Monitor system after implementation"

echo -e "\n${GREEN}✅ Backup process completed!${NC}"