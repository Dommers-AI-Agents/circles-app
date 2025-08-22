# Subscription Limits Backend Enforcement

## Overview
Backend enforcement has been implemented to prevent API bypass of free tier limits. This ensures that subscription limits are consistently enforced across both the iOS app and API endpoints.

## Implementation Date
January 20, 2025

## Free Tier Limits
- **Maximum Circles**: 6 circles per user
- **Maximum Places per Circle**: 15 places
- **Total Theoretical Maximum**: 90 places (6 circles × 15 places)
- **Export Functionality**: Disabled
- **Watermark-free Sharing**: Disabled

## Premium/Trial Tier
- **All limits**: Unlimited
- **All features**: Enabled

## Files Created/Modified

### New Files
1. **`/backend/config/subscriptionLimits.js`**
   - Central configuration for all subscription tier limits
   - Matches iOS app limits defined in PremiumFeatures
   - Easy to maintain and adjust limits

2. **`/backend/services/subscriptionLimitService.js`**
   - Service class for checking subscription limits
   - Methods:
     - `getUserSubscriptionData(userId)` - Get user's subscription status
     - `canCreateCircle(userId)` - Check if user can create a new circle
     - `canAddPlace(userId, circleId)` - Check if user can add a place
     - `canExport(userId)` - Check export permission
     - `canShareWithoutWatermark(userId)` - Check watermark permission
     - `getUserUsageStats(userId)` - Get detailed usage statistics

3. **`/backend/test-subscription-limits.js`**
   - Comprehensive test script for limit enforcement
   - Tests all limit scenarios for free and premium users

### Modified Files
1. **`/backend/controllers/firebaseCircleController.js`**
   - Added limit check before creating new circles
   - Returns 403 with upgrade message when limit reached

2. **`/backend/controllers/firebasePlaceController.js`**
   - Added limit check before adding places to circles
   - Checks limits for circle owner (important for shared circles)
   - Returns 403 with upgrade message when limit reached

3. **`/backend/controllers/subscriptionController.js`**
   - Added `getUserUsageStats` endpoint for usage statistics

4. **`/backend/routes/subscriptionRoutes.js`**
   - Added `/usage` route for getting usage statistics

## API Responses

### When Limit is Reached
```json
{
  "success": false,
  "message": "Free users can create up to 6 circles. Upgrade to Premium for unlimited circles!",
  "upgradeRequired": true,
  "currentCount": 6,
  "maxAllowed": 6
}
```

### Usage Statistics Endpoint
**GET** `/api/users/subscription/usage`

Response:
```json
{
  "success": true,
  "usage": {
    "subscriptionStatus": "none",
    "circles": {
      "current": 3,
      "max": 6
    },
    "circleDetails": [
      {
        "circleId": "abc123",
        "circleName": "Favorite Restaurants",
        "placeCount": 12,
        "maxPlaces": 15
      }
    ],
    "canExport": false,
    "canShareWithoutWatermark": false
  }
}
```

## Error Messages
- **Circle Limit**: "Free users can create up to 6 circles. Upgrade to Premium for unlimited circles!"
- **Place Limit**: "Free users can add up to 15 places per circle. Upgrade to Premium for unlimited places!"
- **Export Limit**: "Export functionality is available to Premium members only."
- **Watermark Limit**: "Share without watermarks with Premium membership."

## Testing
Run the test script to verify implementation:
```bash
cd backend
node test-subscription-limits.js
```

## Important Notes

### Security Considerations
1. **Fail Open for Core Features**: If there's an error checking limits for circles/places, the system allows the action (better UX)
2. **Fail Closed for Premium Features**: If there's an error checking premium features (export, watermark), the system denies the action (protects premium features)

### Shared Circles
- Place limits are checked against the **circle owner's** subscription, not the user adding the place
- This ensures consistent limits per circle regardless of who is adding places

### Performance
- Subscription status is cached in user documents
- Expired subscriptions are automatically updated when checked
- Limit checks are lightweight database queries

## Future Enhancements
1. Add caching layer for subscription status (Redis)
2. Implement webhook for real-time subscription updates
3. Add analytics for limit violations
4. Consider middle tier with higher but not unlimited limits
5. Add batch operations support with limit checking

## Consistency with iOS App
The backend limits exactly match the iOS app limits defined in:
- iOS: `/ios/Circles-iOS-UIKit/Models/SubscriptionProduct.swift` (PremiumFeatures struct)
- Backend: `/backend/config/subscriptionLimits.js`

Both define:
- `maxFreeCircles = 6`
- `maxFreePlacesPerCircle = 15`

This ensures consistent behavior across all platforms.