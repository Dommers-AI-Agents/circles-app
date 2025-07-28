# Private Relay Account Migration Guide

This guide explains how to handle the migration of existing private relay users and the prevention of new private relay accounts.

## Overview

As of July 2025, Circles no longer allows users to create accounts with Apple's private relay emails (`@privaterelay.appleid.com`). This change was made to:

1. **Prevent duplicate accounts** - Users were creating multiple accounts unknowingly
2. **Improve account management** - Real emails allow better account recovery and communication
3. **Enhance user experience** - Users can access their accounts from any device

## What's Been Implemented

### 1. Private Relay Blocking
- **Backend**: All auth endpoints now reject private relay emails with error code `PRIVATE_RELAY_NOT_ALLOWED`
- **iOS**: Shows user-friendly guidance to use real email when signing in with Apple

### 2. Account Merge System
- **Backend API**: `/api/users/merge-accounts` endpoint for merging duplicate accounts
- **iOS UI**: Account merge interface accessible from Settings > Manage Accounts
- **Automatic Detection**: Backend suggests potential merges during login

### 3. Migration Scripts
- **Analysis Script**: `migrate-private-relay-users.js` - Identifies existing private relay users
- **Execution Script**: `execute-private-relay-merges.js` - Executes safe merges in batch

## Migration Process

### Step 1: Analysis
Run the analysis script to identify private relay users and potential duplicates:

```bash
# Dry run to see what would be found
node migrate-private-relay-users.js --dry-run --output-csv

# Actually flag safe merges for execution
node migrate-private-relay-users.js --auto-flag --output-csv
```

**Options:**
- `--dry-run`: Show results without making changes
- `--output-csv`: Generate CSV report for analysis
- `--auto-flag`: Flag accounts with high-confidence matches for auto-merge

### Step 2: Review Results
The script categorizes users into:

1. **Auto-Merge Safe** - Very high confidence matches (e.g., email already in alternateEmails)
2. **Manual Review** - Potential matches that need human verification
3. **Orphaned** - No matches found, user needs to be contacted

### Step 3: Execute Safe Merges
For accounts flagged as safe to merge:

```bash
# Dry run to see what would be merged
node execute-private-relay-merges.js --dry-run

# Execute actual merges (requires --confirm for safety)
node execute-private-relay-merges.js --confirm

# Limit to specific number for testing
node execute-private-relay-merges.js --confirm --limit 10
```

### Step 4: Manual Review
For accounts requiring manual review:

1. **Verify Match**: Confirm the accounts belong to the same person
2. **Use API**: Call `/api/users/merge-accounts` with appropriate IDs
3. **Test Merge**: Verify the merge worked correctly

### Step 5: User Communication
For orphaned accounts (no matches found):

1. **Email User**: Inform them about the private relay restriction
2. **Provide Guidance**: Explain how to sign in with Apple using real email
3. **Offer Support**: Help them merge accounts if they create a new one

## User Experience

### For New Users
When trying to sign in with private relay:

1. **Rejection**: Authentication fails with clear error message
2. **Guidance**: iOS shows options to:
   - Try Apple Sign In again with real email
   - Use email/password registration instead
3. **Education**: Explains why private relay isn't allowed

### For Existing Users
When logging in with real email account:

1. **Detection**: Backend checks for potential duplicates
2. **Suggestion**: Response includes `duplicateSuggestion` if matches found
3. **UI**: iOS can show merge option in settings or during login
4. **Merge Process**: User-friendly interface guides through merge

## API Reference

### Find Duplicates
```http
POST /api/users/find-duplicates
Authorization: Bearer <token>
Content-Type: application/json

{
  "email": "user@example.com",
  "displayName": "John Doe"
}
```

### Merge Accounts
```http
POST /api/users/merge-accounts
Authorization: Bearer <token>
Content-Type: application/json

{
  "primaryAccountId": "main-account-id",
  "secondaryAccountId": "duplicate-account-id"
}
```

## Monitoring and Alerts

### Metrics to Track
1. **Private Relay Rejections** - Count of blocked sign-in attempts
2. **Successful Merges** - Accounts successfully merged
3. **User Contacts** - Support requests related to account access

### Alerts to Set Up
1. **High Rejection Rate** - Many users trying private relay
2. **Merge Failures** - Technical issues with merge process
3. **Orphaned Users** - Users who can't access their accounts

## Rollback Plan

If needed, you can temporarily allow private relay emails by:

1. **Comment out validation** in backend auth controllers
2. **Update iOS error handling** to not show private relay guidance
3. **Deploy changes** to allow private relay sign-ins

However, this should only be done as a last resort, as it reintroduces the duplicate account problem.

## Testing

### Test Scenarios
1. **New private relay sign-in** - Should be rejected with helpful message
2. **Existing user with duplicate** - Should suggest merge
3. **Account merge process** - Should preserve all data correctly
4. **Login after merge** - Should work seamlessly with merged account

### Test Data Cleanup
After testing, clean up any test accounts created during the process.

## Support Documentation

### For Users
Create documentation explaining:
1. Why private relay isn't allowed
2. How to sign in with Apple using real email
3. How to merge existing accounts
4. How to access account if locked out

### For Support Team
Provide troubleshooting guide for:
1. Account access issues
2. Merge problems
3. Data loss concerns
4. Technical error codes

## Security Considerations

1. **Data Privacy** - Merges preserve all user data securely
2. **Access Control** - Only account owners can initiate merges
3. **Audit Trail** - All merges are logged with timestamps
4. **Reversibility** - Merged accounts are marked inactive, not deleted

## Success Criteria

The migration is successful when:
1. **Zero private relay sign-ups** - All new attempts are blocked
2. **High merge rate** - Most duplicates are successfully merged
3. **Low support load** - Few users need help accessing accounts
4. **Data integrity** - No data loss during merges
5. **User satisfaction** - Users understand and accept the change

## Timeline

1. **Week 1**: Deploy private relay blocking and merge UI
2. **Week 2**: Run analysis script and identify users
3. **Week 3**: Execute safe merges and manual reviews
4. **Week 4**: Contact orphaned users and provide support
5. **Ongoing**: Monitor and handle any edge cases