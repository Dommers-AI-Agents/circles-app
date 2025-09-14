// Data Aggregation Background Job
const backgroundAggregationService = require('../services/backgroundAggregationService');
const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const db = getFirestore();

class DataAggregationJob {
    constructor() {
        this.isRunning = false;
        this.lastRunTime = null;
        this.runInterval = 10 * 60 * 1000; // 10 minutes
        this.maxActiveUsers = 50; // Limit to most active users
    }

    // MARK: - Job Execution
    async execute() {
        if (this.isRunning) {
            console.log('⏳ [DataAggJob] Job already running, skipping...');
            return;
        }

        this.isRunning = true;
        this.lastRunTime = new Date();
        
        try {
            console.log('🚀 [DataAggJob] Starting background data aggregation job');
            const startTime = Date.now();

            // Clean expired cache first
            backgroundAggregationService.cleanExpiredCache();

            // Get most active users (based on recent activity)
            const activeUserIds = await this.getActiveUsers();
            
            if (activeUserIds.length === 0) {
                console.log('📭 [DataAggJob] No active users found');
                return;
            }

            // Process active users
            await backgroundAggregationService.processActiveUsers(activeUserIds);

            const totalTime = Date.now() - startTime;
            const cacheStats = backgroundAggregationService.getCacheStats();
            
            console.log(`✅ [DataAggJob] Completed in ${Math.round(totalTime/1000)}s`);
            console.log(`  - Processed: ${activeUserIds.length} users`);
            console.log(`  - Cache: ${cacheStats.totalCached} entries (${cacheStats.memoryUsage})`);

        } catch (error) {
            console.error('❌ [DataAggJob] Error during aggregation job:', error);
        } finally {
            this.isRunning = false;
        }
    }

    // MARK: - Active User Detection
    async getActiveUsers() {
        try {
            // Get users who have been active in the last 24 hours
            const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
            
            // Find users with recent activities
            const recentActivitiesSnapshot = await db.collection(COLLECTIONS.ACTIVITIES)
                .where('timestamp', '>=', yesterday)
                .orderBy('timestamp', 'desc')
                .limit(200) // Get recent activities
                .get();

            // Extract unique active user IDs
            const activeUserIds = new Set();
            recentActivitiesSnapshot.docs.forEach(doc => {
                const activity = doc.data();
                if (activity.actorId) {
                    activeUserIds.add(activity.actorId);
                }
            });

            // Also include users with recent login (lastSeen)
            const recentUsersSnapshot = await db.collection(COLLECTIONS.USERS)
                .where('lastSeen', '>=', yesterday)
                .limit(100)
                .get();

            recentUsersSnapshot.docs.forEach(doc => {
                activeUserIds.add(doc.id);
            });

            // Convert to array and limit
            const activeUserArray = Array.from(activeUserIds).slice(0, this.maxActiveUsers);
            
            console.log(`👥 [DataAggJob] Found ${activeUserArray.length} active users`);
            return activeUserArray;

        } catch (error) {
            console.error('❌ [DataAggJob] Error getting active users:', error);
            return [];
        }
    }

    // MARK: - Scheduler
    start() {
        console.log(`⏰ [DataAggJob] Starting scheduler (interval: ${this.runInterval/1000/60}min)`);
        
        // Run immediately
        this.execute();
        
        // Schedule recurring execution
        this.intervalId = setInterval(() => {
            this.execute();
        }, this.runInterval);
    }

    stop() {
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
            console.log('⏹️ [DataAggJob] Scheduler stopped');
        }
    }

    // MARK: - Status
    getStatus() {
        return {
            isRunning: this.isRunning,
            lastRunTime: this.lastRunTime,
            nextRunTime: this.lastRunTime ? new Date(this.lastRunTime.getTime() + this.runInterval) : null,
            intervalMinutes: this.runInterval / 1000 / 60,
            maxActiveUsers: this.maxActiveUsers
        };
    }
}

// Singleton instance
const dataAggregationJob = new DataAggregationJob();

module.exports = dataAggregationJob;