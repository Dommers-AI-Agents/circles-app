// Smart Cache Invalidation Service
const backgroundAggregationService = require('./backgroundAggregationService');
const SSEService = require('./sseService');

class CacheInvalidationService {
    constructor() {
        this.invalidationRules = new Map();
        this.setupInvalidationRules();
    }

    // MARK: - Invalidation Rules Setup
    setupInvalidationRules() {
        // Define what changes invalidate cache for which users
        this.invalidationRules.set('circle_created', (data) => {
            return [data.userId]; // Invalidate cache for circle owner
        });

        this.invalidationRules.set('circle_updated', (data) => {
            const affectedUsers = [data.userId]; // Circle owner
            
            // If privacy changed to public, invalidate all connected users
            if (data.changes?.privacy === 'public') {
                // We'll need to fetch connected users - for now just owner
                return affectedUsers;
            }
            
            return affectedUsers;
        });

        this.invalidationRules.set('circle_deleted', (data) => {
            return [data.userId];
        });

        this.invalidationRules.set('place_created', (data) => {
            const affectedUsers = [data.userId]; // Place creator
            
            // If place is in a public circle, invalidate network users
            if (data.circlePrivacy === 'public' || data.circlePrivacy === 'myNetwork') {
                // Add connected users (we'd need to fetch them)
                // For now, just the creator
            }
            
            return affectedUsers;
        });

        this.invalidationRules.set('place_updated', (data) => {
            return [data.userId];
        });

        this.invalidationRules.set('place_deleted', (data) => {
            return [data.userId];
        });

        this.invalidationRules.set('connection_created', (data) => {
            // Both users need cache refresh when they connect
            return [data.userId, data.connectedUserId];
        });

        this.invalidationRules.set('connection_accepted', (data) => {
            // Both users need cache refresh
            return [data.userId, data.connectedUserId];
        });

        this.invalidationRules.set('activity_created', (data) => {
            const affectedUsers = [data.actorId]; // Actor
            
            // Add users who can see this activity based on privacy
            if (data.circlePrivacy === 'public') {
                // Public activities affect many users - trigger background refresh
                this.scheduleBackgroundRefresh([data.actorId]);
                return [data.actorId]; // Just actor for immediate invalidation
            }
            
            return affectedUsers;
        });

        this.invalidationRules.set('user_profile_updated', (data) => {
            // User profile changes affect their own cache and followers
            return [data.userId];
        });

        console.log(`📋 [CacheInvalidation] Initialized ${this.invalidationRules.size} invalidation rules`);
    }

    // MARK: - Cache Invalidation
    async invalidateCacheForEvent(eventType, eventData) {
        try {
            console.log(`🔄 [CacheInvalidation] Processing event: ${eventType}`);
            
            const rule = this.invalidationRules.get(eventType);
            if (!rule) {
                console.log(`⚠️ [CacheInvalidation] No rule found for event: ${eventType}`);
                return;
            }

            const affectedUserIds = rule(eventData);
            if (affectedUserIds.length === 0) {
                console.log(`ℹ️ [CacheInvalidation] No users affected by event: ${eventType}`);
                return;
            }

            console.log(`🔄 [CacheInvalidation] Invalidating cache for ${affectedUserIds.length} users`);
            
            // Invalidate memory cache immediately
            for (const userId of affectedUserIds) {
                backgroundAggregationService.invalidateUserCache(userId);
            }

            // Send real-time cache refresh signals to connected clients
            this.sendCacheRefreshSignals(affectedUserIds, eventType);

            // Schedule background re-aggregation for affected users
            this.scheduleBackgroundRefresh(affectedUserIds);

        } catch (error) {
            console.error('❌ [CacheInvalidation] Error processing cache invalidation:', error);
        }
    }

    // MARK: - Real-time Cache Refresh Signals
    sendCacheRefreshSignals(userIds, eventType) {
        for (const userId of userIds) {
            // Send cache refresh signal via SSE
            SSEService.sendEventToUser(userId, 'cache_refresh', {
                reason: eventType,
                timestamp: new Date().toISOString(),
                action: 'refresh_home_data'
            });
        }
        
        console.log(`📡 [CacheInvalidation] Sent cache refresh signals to ${userIds.length} users`);
    }

    // MARK: - Background Refresh Scheduling
    scheduleBackgroundRefresh(userIds) {
        // Schedule background re-aggregation with a small delay to batch updates
        setTimeout(async () => {
            try {
                console.log(`🔄 [CacheInvalidation] Starting background refresh for ${userIds.length} users`);
                await backgroundAggregationService.processActiveUsers(userIds);
                console.log(`✅ [CacheInvalidation] Background refresh completed`);
            } catch (error) {
                console.error('❌ [CacheInvalidation] Background refresh error:', error);
            }
        }, 2000); // 2 second delay to batch multiple rapid changes
    }

    // MARK: - Manual Cache Operations
    async invalidateAllCache() {
        console.log('🗑️ [CacheInvalidation] Manually invalidating all cache');
        backgroundAggregationService.clearAllCache();
    }

    async refreshCacheForUser(userId) {
        console.log(`🔄 [CacheInvalidation] Manually refreshing cache for user: ${userId}`);
        backgroundAggregationService.invalidateUserCache(userId);
        
        // Send refresh signal
        this.sendCacheRefreshSignals([userId], 'manual_refresh');
        
        // Schedule background refresh
        this.scheduleBackgroundRefresh([userId]);
    }

    // MARK: - Event Helpers for Controllers
    
    // Helper for circle operations
    onCircleChange(action, circleData, userId) {
        this.invalidateCacheForEvent(`circle_${action}`, {
            userId: userId,
            circleId: circleData.id,
            privacy: circleData.privacy,
            changes: circleData.changes || {}
        });
    }

    // Helper for place operations
    onPlaceChange(action, placeData, userId) {
        this.invalidateCacheForEvent(`place_${action}`, {
            userId: userId,
            placeId: placeData.id,
            circleId: placeData.circleId,
            circlePrivacy: placeData.circlePrivacy
        });
    }

    // Helper for connection operations
    onConnectionChange(action, connectionData) {
        this.invalidateCacheForEvent(`connection_${action}`, {
            userId: connectionData.userId,
            connectedUserId: connectionData.connectedUserId,
            status: connectionData.status
        });
    }

    // Helper for activity creation
    onActivityCreated(activityData) {
        this.invalidateCacheForEvent('activity_created', {
            actorId: activityData.actorId,
            targetId: activityData.targetId,
            targetType: activityData.targetType,
            circleId: activityData.circleId,
            circlePrivacy: activityData.circlePrivacy
        });
    }

    // Helper for user profile updates
    onUserProfileUpdated(userId, changes) {
        this.invalidateCacheForEvent('user_profile_updated', {
            userId: userId,
            changes: changes
        });
    }

    // MARK: - Statistics
    getStats() {
        return {
            totalRules: this.invalidationRules.size,
            cacheStats: backgroundAggregationService.getCacheStats()
        };
    }
}

// Singleton instance
const cacheInvalidationService = new CacheInvalidationService();

// Add method to background aggregation service
backgroundAggregationService.invalidateUserCache = (userId) => {
    console.log(`🗑️ [BackgroundAgg] Invalidating cache for user: ${userId}`);
    // Remove from in-memory cache
    if (backgroundAggregationService.aggregationCache) {
        backgroundAggregationService.aggregationCache.delete(userId);
        backgroundAggregationService.cacheExpiry.delete(userId);
    }
};

backgroundAggregationService.clearAllCache = () => {
    console.log('🗑️ [BackgroundAgg] Clearing all cache');
    if (backgroundAggregationService.aggregationCache) {
        backgroundAggregationService.aggregationCache.clear();
        backgroundAggregationService.cacheExpiry.clear();
    }
};

module.exports = cacheInvalidationService;