// Function to add to firebaseAuthController.js

// @desc    Use profile image from authentication provider
// @route   POST /api/auth/use-provider-image
// @access  Private
exports.useProviderImage = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { provider } = req.body;
    
    if (!provider || !['google', 'facebook', 'apple'].includes(provider)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid provider. Must be one of: google, facebook, apple'
      });
    }
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const user = userDoc.data();
    const linkedProviders = user.linkedProviders || {};
    
    if (!linkedProviders[provider]) {
      return res.status(400).json({
        success: false,
        message: `Account not linked with ${provider}`
      });
    }
    
    // Fetch the current profile image from the provider
    let providerImageUrl = null;
    
    if (provider === 'google' && linkedProviders.google) {
      // For Google, we would need to make an API call to get the current picture
      // This is a placeholder - in production, you'd fetch from Google API
      console.log('📸 Would fetch Google profile picture for user:', linkedProviders.google);
    }
    
    // For now, clear the custom flag so next sign-in will update the picture
    await userRef.update({
      hasCustomProfilePicture: false,
      updatedAt: new Date().toISOString()
    });
    
    res.status(200).json({
      success: true,
      message: `Profile picture will be updated from ${provider} on next sign-in`,
      note: 'Sign out and sign back in to see the updated profile picture'
    });
    
  } catch (error) {
    console.error('Use provider image error:', error);
    next(error);
  }
};