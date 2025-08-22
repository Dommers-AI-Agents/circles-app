// Simple in-memory cache for Google Places API responses
// This significantly reduces API costs by caching place details

class PlaceCache {
  constructor() {
    this.cache = new Map();
    this.TTL = {
      placeDetails: 7 * 24 * 60 * 60 * 1000, // 7 days for place details
      geocoding: 365 * 24 * 60 * 60 * 1000,  // 1 year for geocoding (addresses rarely change)
      photos: 30 * 24 * 60 * 60 * 1000,      // 30 days for photo metadata
    };
    
    // Periodically clean expired entries
    setInterval(() => this.cleanExpired(), 60 * 60 * 1000); // Every hour
  }
  
  // Generate cache key
  generateKey(type, identifier) {
    return `${type}:${identifier}`;
  }
  
  // Set item in cache with TTL
  set(type, identifier, data, customTTL = null) {
    const key = this.generateKey(type, identifier);
    const ttl = customTTL || this.TTL[type] || this.TTL.placeDetails;
    const expiresAt = Date.now() + ttl;
    
    this.cache.set(key, {
      data,
      expiresAt,
      createdAt: Date.now(),
      type
    });
    
    console.log(`📦 Cached ${type} for ${identifier}, expires in ${ttl / 1000 / 60} minutes`);
    return data;
  }
  
  // Get item from cache
  get(type, identifier) {
    const key = this.generateKey(type, identifier);
    const cached = this.cache.get(key);
    
    if (!cached) {
      return null;
    }
    
    // Check if expired
    if (Date.now() > cached.expiresAt) {
      this.cache.delete(key);
      console.log(`🗑️ Cache expired for ${type}:${identifier}`);
      return null;
    }
    
    const ageMinutes = Math.floor((Date.now() - cached.createdAt) / 1000 / 60);
    console.log(`✅ Cache hit for ${type}:${identifier} (age: ${ageMinutes} minutes)`);
    return cached.data;
  }
  
  // Check if item exists and is valid
  has(type, identifier) {
    return this.get(type, identifier) !== null;
  }
  
  // Clear specific item
  clear(type, identifier) {
    const key = this.generateKey(type, identifier);
    this.cache.delete(key);
  }
  
  // Clear all items of a specific type
  clearType(type) {
    for (const [key, value] of this.cache.entries()) {
      if (value.type === type) {
        this.cache.delete(key);
      }
    }
    console.log(`🗑️ Cleared all cached ${type} entries`);
  }
  
  // Clean expired entries
  cleanExpired() {
    const now = Date.now();
    let cleaned = 0;
    
    for (const [key, value] of this.cache.entries()) {
      if (now > value.expiresAt) {
        this.cache.delete(key);
        cleaned++;
      }
    }
    
    if (cleaned > 0) {
      console.log(`🧹 Cleaned ${cleaned} expired cache entries`);
    }
  }
  
  // Get cache statistics
  getStats() {
    const stats = {
      totalEntries: this.cache.size,
      byType: {},
      oldestEntry: null,
      newestEntry: null
    };
    
    let oldest = Infinity;
    let newest = 0;
    
    for (const [key, value] of this.cache.entries()) {
      // Count by type
      if (!stats.byType[value.type]) {
        stats.byType[value.type] = 0;
      }
      stats.byType[value.type]++;
      
      // Track oldest/newest
      if (value.createdAt < oldest) {
        oldest = value.createdAt;
        stats.oldestEntry = new Date(value.createdAt).toISOString();
      }
      if (value.createdAt > newest) {
        newest = value.createdAt;
        stats.newestEntry = new Date(value.createdAt).toISOString();
      }
    }
    
    return stats;
  }
  
  // Clear entire cache
  clearAll() {
    const size = this.cache.size;
    this.cache.clear();
    console.log(`🗑️ Cleared entire cache (${size} entries)`);
  }
}

// Export singleton instance
module.exports = new PlaceCache();