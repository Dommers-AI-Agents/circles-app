# Circles App Backup System

## Overview
Comprehensive backup and rollback system created before implementing the place normalization architecture. This system ensures we can safely revert any changes if issues arise.

## Backup Components

### 1. Database Backup
- **Script**: `backend/scripts/backup-critical-data.js`
- **Collections**: places, circles, users, placeVideos, user-place relationships
- **Format**: JSON files with timestamp
- **Location**: `backend/backups/`

### 2. Code Backup
- **Git Branches**: Automatic backup branches with timestamps
- **Code Archive**: Complete tar.gz archive excluding build files
- **Critical Files**: Individual backups of key files

### 3. Complete Backup Script
- **Script**: `create-complete-backup.sh`
- **Creates**: Git branches, code archives, database exports
- **Location**: `~/Desktop/circles-backups/`

## Usage

### Creating Backups

#### Complete Backup (Recommended)
```bash
# Run the comprehensive backup script
./create-complete-backup.sh
```

#### Database Only
```bash
cd backend
node scripts/backup-critical-data.js
```

#### Git Backup Only
```bash
# Create backup branch
git checkout -b backup/pre-changes-$(date +%Y%m%d_%H%M%S)
git push origin backup/pre-changes-$(date +%Y%m%d_%H%M%S)
```

### Viewing Backups

#### List Database Backups
```bash
cd backend
node scripts/rollback-database.js list
```

#### Check Backup Integrity
```bash
cd backend
node scripts/backup-critical-data.js
# Automatically runs verification
```

### Rollback Procedures

#### Database Rollback (Dry Run)
```bash
cd backend
node scripts/rollback-database.js rollback <timestamp> --dry-run
```

#### Database Rollback (Actual)
```bash
cd backend
FORCE_ROLLBACK=true node scripts/rollback-database.js rollback <timestamp>
```

#### Code Rollback
```bash
# Option 1: Git branch rollback
git checkout backup/pre-changes-YYYYMMDD_HHMMSS

# Option 2: Archive restore
cd ~/Desktop/circles-backups/code/
tar -xzf circles-app-YYYYMMDD_HHMMSS.tar.gz
```

#### Individual File Rollback
```bash
# Restore from critical files backup
cp ~/Desktop/circles-backups/code/critical-files/path/to/file.ext path/to/file.ext
```

## Testing the Backup System

### Run All Tests
```bash
cd backend
node scripts/test-backup-system.js all
```

### Run Specific Tests
```bash
# Safety checks only
node scripts/test-backup-system.js safety

# Component tests only  
node scripts/test-backup-system.js components

# Full backup/rollback test
node scripts/test-backup-system.js full
```

## File Structure

```
circles-app/
├── create-complete-backup.sh          # Main backup script
├── BACKUP-SYSTEM.md                   # This file
└── backend/
    ├── backups/                       # Database backups
    │   ├── places-TIMESTAMP.json
    │   ├── circles-TIMESTAMP.json
    │   ├── users-essential-TIMESTAMP.json
    │   ├── place-videos-TIMESTAMP.json
    │   ├── user-place-relations-TIMESTAMP.json
    │   └── backup-summary-TIMESTAMP.json
    └── scripts/
        ├── backup-critical-data.js    # Database backup
        ├── rollback-database.js       # Database rollback
        └── test-backup-system.js      # Testing utilities

~/Desktop/circles-backups/             # External backup location
├── backup-summary-TIMESTAMP.txt       # Overall backup summary
├── code/
│   ├── circles-app-TIMESTAMP.tar.gz   # Complete code archive
│   └── critical-files/                # Individual file backups
├── database/                          # Copy of database backups
├── git/                              # Git metadata
└── storage/                          # Firebase storage info
```

## Safety Features

### Backup Verification
- Automatic integrity checks after backup
- Count verification against live database
- File existence validation

### Rollback Protection
- Dry-run mode for all rollback operations
- `FORCE_ROLLBACK` environment variable required
- Rollback history tracking

### Data Protection
- User data privacy (only essential fields backed up)
- Firestore timestamps properly handled
- Batch operations to prevent timeouts

## Emergency Procedures

### Complete System Failure
1. **Stop all services**
2. **Restore from git backup branch**:
   ```bash
   git checkout backup/pre-place-normalization-YYYYMMDD_HHMMSS
   ```
3. **Restore database**:
   ```bash
   FORCE_ROLLBACK=true node scripts/rollback-database.js rollback TIMESTAMP
   ```
4. **Deploy restored version**

### Partial Data Corruption
1. **Identify affected collections**
2. **Run targeted rollback**:
   ```bash
   # Only restore specific collections
   node scripts/rollback-database.js rollback TIMESTAMP
   ```
3. **Verify data integrity**

### Code Issues Only
1. **Rollback git branch**:
   ```bash
   git checkout backup/pre-place-normalization-YYYYMMDD_HHMMSS
   git checkout -b hotfix/emergency-restore
   ```
2. **Deploy hotfix branch**

## Monitoring & Alerts

### Key Metrics to Monitor
- API error rates (should be < 1%)
- Database operation success rates
- User session failures
- Place data integrity

### Alert Thresholds
- **API errors**: > 10 errors in 5 minutes
- **Database errors**: > 5 errors in 5 minutes  
- **User complaints**: > 3 reports about data loss

### Automatic Rollback Triggers
- API error rate > 5% for 10+ minutes
- Database operation failures > 10%
- Critical functionality broken

## Maintenance

### Regular Tasks
- **Weekly**: Verify backup system with test run
- **Monthly**: Clean old backups (keep 3 months)
- **Before major changes**: Always run complete backup

### Backup Retention
- **Database backups**: Keep 30 days
- **Code archives**: Keep 90 days  
- **Git branches**: Keep indefinitely (small size)

## Troubleshooting

### Common Issues

#### "Firebase connection failed"
```bash
# Check service account file
ls -la backend/config/firebase-service-account.json

# Verify Firebase project ID
grep "project_id" backend/config/firebase-service-account.json
```

#### "Backup directory permissions"
```bash
# Check backup directory
ls -la ~/Desktop/circles-backups/

# Fix permissions
chmod 755 ~/Desktop/circles-backups/
```

#### "Git branch already exists"
```bash
# Delete existing branch
git branch -D backup/pre-place-normalization-YYYYMMDD

# Or use different timestamp
git checkout -b backup/pre-place-normalization-$(date +%Y%m%d_%H%M%S)
```

## Support

For issues with the backup system:
1. Run the test suite: `node scripts/test-backup-system.js safety`
2. Check backup integrity: Review generated backup summaries
3. Verify file permissions and Firebase access
4. Contact the development team with specific error messages

Remember: **Always test backups before relying on them in production!**