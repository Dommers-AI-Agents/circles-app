// Backend Background Data Aggregation Service
const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');
const { fetchActivitiesByActors } = require('./activityFeedService');
const db = getFirestore();

class BackgroundAggregationService {
    constructor() {
        this.isRunning = false;
        this.aggregationCache = new Map(); // In-memory cache for pre-aggregated data
        this.cacheExpiry = new Map(); // Track cache expiry times
        this.defaultCacheMinutes = 15; // 15 minutes default cache
    }

    // MARK: - Cache Management
    setCacheData(userId, data, expiryMinutes = this.defaultCacheMinutes) {
        const expiryTime = Date.now() + (expiryMinutes * 60 * 1000);
        this.aggregationCache.set(userId, data);
        this.cacheExpiry.set(userId, expiryTime);
        console.log(`🔄 [BackgroundAgg] Cached data for user ${userId}, expires in ${expiryMinutes}min`);
    }

    getCacheData(userId) {
        const expiry = this.cacheExpiry.get(userId);
        if (!expiry || Date.now() > expiry) {
            // Cache expired
            this.aggregationCache.delete(userId);
            this.cacheExpiry.delete(userId);
            return null;
        }
        
        const data = this.aggregationCache.get(userId);
        console.log(`🔄 [BackgroundAgg] Retrieved cached data for user ${userId}`);
        return data;
    }

    // MARK: - Background Aggregation for Active Users
    async aggregateDataForUser(userId) {
        try {
            console.log(`🔄 [BackgroundAgg] Starting aggregation for user: ${userId}`);
            const startTime = Date.now();

            // Parallel fetch core data
            const [
                myCirclesSnapshot,
                connections1,
                connections2,
                currentUserDoc
            ] = await Promise.all([
                // User's circles
                db.collection(COLLECTIONS.CIRCLES)
                    .where('userId', '==', userId)
                    .orderBy('updatedAt', 'desc')
                    .limit(50) // Reasonable limit for background processing
                    .get(),

                // Connections (both directions)
                db.collection(COLLECTIONS.CONNECTIONS)
                    .where('userId', '==', userId)
                    .where('status', '==', 'accepted')
                    .limit(100) // Limit for performance
                    .get(),

                db.collection(COLLECTIONS.CONNECTIONS)
                    .where('connectedUserId', '==', userId)
                    .where('status', '==', 'accepted')
                    .limit(100) // Limit for performance
                    .get(),

                // User data
                db.collection(COLLECTIONS.USERS).doc(userId).get()
            ]);

            // Process connections
            const connectedUserIds = new Set();
            connections1.docs.forEach(doc => connectedUserIds.add(doc.data().connectedUserId));
            connections2.docs.forEach(doc => connectedUserIds.add(doc.data().userId));

            // Add followed users
            if (currentUserDoc.exists) {
                const userData = currentUserDoc.data();
                const followedUserIds = userData.following || [];
                followedUserIds.forEach(id => connectedUserIds.add(id));
            }

            // Get network circles
            let networkCirclesSnapshot = null;
            if (connectedUserIds.size > 0) {
                const connectionArray = Array.from(connectedUserIds);
                const batches = [];
                for (let i = 0; i < connectionArray.length; i += 10) {
                    batches.push(connectionArray.slice(i, i + 10));
                }

                const networkPromises = batches.map(batch =>
                    db.collection(COLLECTIONS.CIRCLES)
                        .where('owner', 'in', batch)
                        .where('privacy', 'in', ['public', 'myNetwork'])
                        .limit(20) // Limit per batch
                        .get()
                );

                const networkResults = await Promise.all(networkPromises);
                // Combine results
                const allNetworkDocs = networkResults.flatMap(snapshot => snapshot.docs);
                networkCirclesSnapshot = { docs: allNetworkDocs };
            }

            // Process circles
            const myCircles = serializeQuerySnapshot(myCirclesSnapshot);
            const networkCircles = networkCirclesSnapshot 
                ? serializeQuerySnapshot(networkCirclesSnapshot)
                : [];

            // Get all user IDs for batch fetching
            const userIdsToFetch = new Set([userId]);
            [...myCircles, ...networkCircles].forEach(circle => {
                userIdsToFetch.add(circle.owner);
            });

            // Fetch activities scoped to network actors - scales with network
            // size, not platform activity volume
            const networkUserIds = new Set([...connectedUserIds, userId]);
            const filteredActivities = await fetchActivitiesByActors(networkUserIds, 30);

            // Add activity actors to fetch list
            filteredActivities.forEach(activity => userIdsToFetch.add(activity.actorId));

            // Batch fetch users (optimized)
            const userIdArray = Array.from(userIdsToFetch);
            const usersMap = await this.batchFetchUsers(userIdArray);

            // Build optimized user list
            const userList = Array.from(connectedUserIds)
                .map(id => usersMap[id])
                .filter(user => user && user._id !== userId)
                .sort((a, b) => {
                    // Sort by recent activity
                    const aActivity = filteredActivities.filter(act => act.actorId === a._id).length;
                    const bActivity = filteredActivities.filter(act => act.actorId === b._id).length;
                    return bActivity - aActivity;
                })
                .slice(0, 25) // Top 25 most active users
                .map(user => ({
                    _id: user._id,
                    displayName: user.displayName,
                    profileImageUrl: user.profileImageUrl,
                    isOnline: user.lastSeen ? (Date.now() - new Date(user.lastSeen).getTime()) < 300000 : false
                }));

            // Enrich activities
            const enrichedActivities = filteredActivities.map(activity => {
                // Convert timestamp
                if (activity.timestamp && activity.timestamp._seconds) {
                    activity.timestamp = new Date(activity.timestamp._seconds * 1000).toISOString();
                } else if (activity.timestamp && activity.timestamp.toDate) {
                    activity.timestamp = activity.timestamp.toDate().toISOString();
                } else if (activity.timestamp instanceof Date) {
                    activity.timestamp = activity.timestamp.toISOString();
                }

                return {
                    ...activity,
                    actor: usersMap[activity.actorId] || { _id: activity.actorId, displayName: 'Unknown User' },
                    isRead: activity.viewers?.includes(userId) || false
                };
            });

            const aggregatedData = {
                userList,
                recentActivities: enrichedActivities,
                myCircles: myCircles.slice(0, 20), // Limit for background processing
                networkCircles: networkCircles.slice(0, 20), // Limit for background processing
                stats: {
                    totalUsers: userList.length,
                    totalActivities: enrichedActivities.length,
                    totalCircles: myCircles.length + networkCircles.length,
                    aggregationTimeMs: Date.now() - startTime
                }
            };

            // Cache the aggregated data
            this.setCacheData(userId, aggregatedData);

            const totalTime = Date.now() - startTime;
            console.log(`✅ [BackgroundAgg] Completed for user ${userId} in ${totalTime}ms`);
            console.log(`  - User list: ${userList.length}`);
            console.log(`  - Activities: ${enrichedActivities.length}`);
            console.log(`  - My circles: ${myCircles.length}`);
            console.log(`  - Network circles: ${networkCircles.length}`);

            return aggregatedData;

        } catch (error) {
            console.error(`❌ [BackgroundAgg] Error for user ${userId}:`, error);
            return null;
        }
    }

    // MARK: - Helper Methods
    async batchFetchUsers(userIdArray) {
        if (userIdArray.length === 0) return {};

        const userBatches = [];
        for (let i = 0; i < userIdArray.length; i += 10) {
            userBatches.push(userIdArray.slice(i, i + 10));
        }

        const userSnapshots = await Promise.all(
            userBatches.map(batch => 
                db.collection(COLLECTIONS.USERS)
                    .where('__name__', 'in', batch)
                    .get()
            )
        );

        const usersMap = {};
        userSnapshots.forEach(snapshot => {
            snapshot.docs.forEach(doc => {
                const user = serializeDoc(doc);
                usersMap[user._id] = user;
            });
        });

        return usersMap;
    }

    // MARK: - Batch Processing
    async processActiveUsers(userIds) {
        console.log(`🔄 [BackgroundAgg] Processing ${userIds.length} active users`);
        
        // Process users in small batches to avoid overwhelming the system
        const batchSize = 5;
        const batches = [];
        
        for (let i = 0; i < userIds.length; i += batchSize) {
            batches.push(userIds.slice(i, i + batchSize));
        }

        for (let i = 0; i < batches.length; i++) {
            const batch = batches[i];
            console.log(`🔄 [BackgroundAgg] Processing batch ${i + 1}/${batches.length}`);

            // Process batch in parallel
            const promises = batch.map(userId => this.aggregateDataForUser(userId));
            await Promise.all(promises);

            // Small delay between batches to avoid overwhelming Firestore
            if (i < batches.length - 1) {
                await new Promise(resolve => setTimeout(resolve, 1000));
            }
        }

        console.log(`✅ [BackgroundAgg] Completed processing ${userIds.length} users`);
    }

    // MARK: - Cache Cleanup
    cleanExpiredCache() {
        const now = Date.now();
        let cleanedCount = 0;

        for (const [userId, expiry] of this.cacheExpiry.entries()) {
            if (now > expiry) {
                this.aggregationCache.delete(userId);
                this.cacheExpiry.delete(userId);
                cleanedCount++;
            }
        }

        if (cleanedCount > 0) {
            console.log(`🧹 [BackgroundAgg] Cleaned ${cleanedCount} expired cache entries`);
        }
    }

    // MARK: - Status
    getCacheStats() {
        return {
            totalCached: this.aggregationCache.size,
            memoryUsage: Math.round(JSON.stringify([...this.aggregationCache.values()]).length / 1024) + ' KB'
        };
    }
}

// Singleton instance
const backgroundAggregationService = new BackgroundAggregationService();

module.exports = backgroundAggregationService;