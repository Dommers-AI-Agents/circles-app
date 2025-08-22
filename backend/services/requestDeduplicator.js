// Request deduplication service to prevent duplicate concurrent API calls
// This prevents multiple identical requests from hitting Google APIs simultaneously

class RequestDeduplicator {
  constructor() {
    // Map to store pending requests
    this.pendingRequests = new Map();
    
    // Cleanup old requests every 5 minutes
    setInterval(() => this.cleanup(), 5 * 60 * 1000);
  }
  
  /**
   * Execute a request with deduplication
   * If an identical request is already pending, return the same promise
   * @param {string} key - Unique key for this request type
   * @param {Function} requestFunction - Async function that makes the actual request
   * @returns {Promise} - Promise that resolves with the request result
   */
  async execute(key, requestFunction) {
    // Check if we already have a pending request for this key
    if (this.pendingRequests.has(key)) {
      console.log(`🔄 Deduplicating request for key: ${key}`);
      return this.pendingRequests.get(key);
    }
    
    // Create the request promise
    const requestPromise = this.performRequest(key, requestFunction);
    
    // Store the pending request
    this.pendingRequests.set(key, requestPromise);
    
    return requestPromise;
  }
  
  /**
   * Perform the actual request and cleanup when done
   */
  async performRequest(key, requestFunction) {
    try {
      console.log(`🚀 Executing new request for key: ${key}`);
      const result = await requestFunction();
      
      // Remove from pending requests after a short delay
      // This prevents rapid successive calls from creating duplicates
      setTimeout(() => {
        this.pendingRequests.delete(key);
      }, 1000);
      
      return result;
    } catch (error) {
      // Remove from pending requests immediately on error
      this.pendingRequests.delete(key);
      throw error;
    }
  }
  
  /**
   * Generate a key for place details requests
   */
  generatePlaceKey(placeId) {
    return `place:${placeId}`;
  }
  
  /**
   * Generate a key for geocoding requests
   */
  generateGeocodeKey(address) {
    return `geocode:${address.toLowerCase().replace(/\s+/g, '_')}`;
  }
  
  /**
   * Generate a key for place search requests
   */
  generateSearchKey(query, location) {
    const locationStr = location ? `${location.lat},${location.lng}` : 'none';
    return `search:${query.toLowerCase().replace(/\s+/g, '_')}:${locationStr}`;
  }
  
  /**
   * Clean up old pending requests (in case they got stuck)
   */
  cleanup() {
    const now = Date.now();
    let cleaned = 0;
    
    // We'll track request ages in a future version
    // For now, just log the pending count
    if (this.pendingRequests.size > 0) {
      console.log(`📊 ${this.pendingRequests.size} pending deduplicated requests`);
    }
  }
  
  /**
   * Get statistics about pending requests
   */
  getStats() {
    return {
      pendingCount: this.pendingRequests.size,
      pendingKeys: Array.from(this.pendingRequests.keys())
    };
  }
  
  /**
   * Clear all pending requests (use with caution)
   */
  clearAll() {
    const count = this.pendingRequests.size;
    this.pendingRequests.clear();
    console.log(`🗑️ Cleared ${count} pending requests`);
  }
}

// Export singleton instance
module.exports = new RequestDeduplicator();