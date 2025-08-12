// backend/services/videoQuotaService.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, createUserVideoQuota } = require('../models/FirestoreModels');

const db = getFirestore();

class VideoQuotaService {
  // Get or create user's video quota
  async getUserQuota(userId) {
    const now = new Date();
    const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    const quotaDoc = await quotaRef.get();
    
    if (!quotaDoc.exists) {
      // Create new quota record
      // TODO: Check user's subscription status to determine tier
      const tier = await this.getUserSubscriptionTier(userId);
      const newQuota = createUserVideoQuota(userId, tier);
      await quotaRef.set(newQuota);
      return newQuota;
    }
    
    const quotaData = quotaDoc.data();
    
    // Reset quota if new month
    if (quotaData.currentMonth !== currentMonth) {
      const updatedQuota = {
        ...quotaData,
        currentMonth: currentMonth,
        videosUploaded: 0,
        totalSize: 0,
        lastResetDate: now.toISOString(),
        updatedAt: now.toISOString()
      };
      await quotaRef.update(updatedQuota);
      return updatedQuota;
    }
    
    return quotaData;
  }
  
  // Check if user can upload a video
  async canUploadVideo(userId, fileSize) {
    const quota = await this.getUserQuota(userId);
    
    if (quota.videosUploaded >= quota.quotaLimit) {
      return {
        allowed: false,
        reason: 'Monthly video quota exceeded',
        quotaInfo: quota
      };
    }
    
    if (quota.totalSize + fileSize > quota.sizeLimit) {
      return {
        allowed: false,
        reason: 'Monthly storage quota exceeded',
        quotaInfo: quota
      };
    }
    
    return {
      allowed: true,
      quotaInfo: quota
    };
  }
  
  // Get user's subscription tier
  async getUserSubscriptionTier(userId) {
    // TODO: Implement subscription check
    // For now, return 'free' for all users
    return 'free';
  }
  
  // Update quota limits based on subscription
  async updateUserTier(userId, newTier) {
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    const quotaDoc = await quotaRef.get();
    
    if (!quotaDoc.exists) {
      // Create new quota with specified tier
      const newQuota = createUserVideoQuota(userId, newTier);
      await quotaRef.set(newQuota);
      return newQuota;
    }
    
    // Update existing quota
    const updates = {
      subscriptionTier: newTier,
      quotaLimit: newTier === 'free' ? 5 : 50,
      sizeLimit: newTier === 'free' ? 262144000 : 2147483648, // 250MB : 2GB
      updatedAt: new Date().toISOString()
    };
    
    await quotaRef.update(updates);
    return { ...quotaDoc.data(), ...updates };
  }
  
  // Get quota usage statistics
  async getQuotaStats(userId) {
    const quota = await this.getUserQuota(userId);
    
    return {
      tier: quota.subscriptionTier,
      usage: {
        videos: {
          used: quota.videosUploaded,
          limit: quota.quotaLimit,
          remaining: quota.quotaLimit - quota.videosUploaded,
          percentage: (quota.videosUploaded / quota.quotaLimit) * 100
        },
        storage: {
          used: quota.totalSize,
          limit: quota.sizeLimit,
          remaining: quota.sizeLimit - quota.totalSize,
          percentage: (quota.totalSize / quota.sizeLimit) * 100,
          usedMB: Math.round(quota.totalSize / 1048576),
          limitMB: Math.round(quota.sizeLimit / 1048576)
        }
      },
      currentMonth: quota.currentMonth,
      lastResetDate: quota.lastResetDate
    };
  }
  
  // Reset all quotas (for monthly cron job)
  async resetMonthlyQuotas() {
    const now = new Date();
    const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    
    const batch = db.batch();
    const quotasSnapshot = await db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).get();
    
    quotasSnapshot.docs.forEach(doc => {
      const data = doc.data();
      if (data.currentMonth !== currentMonth) {
        batch.update(doc.ref, {
          currentMonth: currentMonth,
          videosUploaded: 0,
          totalSize: 0,
          lastResetDate: now.toISOString(),
          updatedAt: now.toISOString()
        });
      }
    });
    
    await batch.commit();
    
    return {
      processed: quotasSnapshot.docs.length,
      month: currentMonth
    };
  }
}

module.exports = new VideoQuotaService();