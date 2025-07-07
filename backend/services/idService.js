// Centralized ID normalization service
// Handles conversion between complex and simple user ID formats

/**
 * Normalizes a user ID to its simple format
 * Complex format: 000454.9b5eeac93282416c9bc6dcecbc49b40f.2127
 * Simple format: 9b5eeac93282416c9bc6dcecbc49b40f
 * 
 * @param {string} userId - The user ID to normalize
 * @returns {string|null} - The normalized user ID or null if invalid
 */
exports.normalizeUserId = (userId) => {
  if (!userId) return null;
  
  // Convert to string in case it's not
  const userIdStr = String(userId);
  
  // If complex format (contains dots), extract the Firebase UID (middle part)
  if (userIdStr.includes('.')) {
    const parts = userIdStr.split('.');
    if (parts.length >= 2) {
      const normalizedId = parts[1];
      console.log(`📋 ID Service: Normalized ${userIdStr} → ${normalizedId}`);
      return normalizedId;
    }
  }
  
  // Already in simple format
  return userIdStr;
};

/**
 * Check if two IDs refer to the same user
 * Handles comparison between complex and simple formats
 * 
 * @param {string} id1 - First user ID
 * @param {string} id2 - Second user ID
 * @returns {boolean} - True if IDs refer to the same user
 */
exports.isSameUser = (id1, id2) => {
  if (!id1 || !id2) return false;
  return this.normalizeUserId(id1) === this.normalizeUserId(id2);
};

/**
 * Get all possible ID variants for a user
 * Used during migration to find all references
 * 
 * @param {string} userId - The user ID
 * @returns {string[]} - Array of possible ID formats
 */
exports.getUserIdVariants = (userId) => {
  if (!userId) return [];
  
  const normalized = this.normalizeUserId(userId);
  const variants = new Set([normalized]);
  
  // Add the original ID if it's different
  if (userId !== normalized) {
    variants.add(userId);
  }
  
  return Array.from(variants);
};

/**
 * Extract the simple ID from a complex ID or return as-is
 * Similar to normalizeUserId but used for clarity in migration contexts
 * 
 * @param {string} complexId - The potentially complex ID
 * @returns {string} - The simple ID
 */
exports.extractSimpleId = (complexId) => {
  return this.normalizeUserId(complexId);
};

/**
 * Check if an ID is in complex format
 * 
 * @param {string} userId - The user ID to check
 * @returns {boolean} - True if ID is in complex format
 */
exports.isComplexId = (userId) => {
  return userId && String(userId).includes('.');
};

/**
 * Log ID normalization for debugging
 * 
 * @param {string} context - Where the normalization is happening
 * @param {string} originalId - The original ID
 * @param {string} normalizedId - The normalized ID
 */
exports.logNormalization = (context, originalId, normalizedId) => {
  if (originalId !== normalizedId) {
    console.log(`🔄 [${context}] ID normalized: ${originalId} → ${normalizedId}`);
  }
};