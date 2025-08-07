const admin = require('firebase-admin');
const crypto = require('crypto');

// Generate a unique 6-character referral code
const generateReferralCode = () => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let code = '';
    for (let i = 0; i < 6; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return code;
};

// Check if a referral code already exists
const isCodeUnique = async (code) => {
    const snapshot = await admin.firestore()
        .collection('users')
        .where('referralCode', '==', code)
        .limit(1)
        .get();
    
    return snapshot.empty;
};

// @desc    Generate or get user's referral code
// @route   POST /api/users/referral/generate
// @access  Private
exports.generateReferralCode = async (req, res) => {
    try {
        const userId = req.userId;
        const userRef = admin.firestore().collection('users').doc(userId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            return res.status(404).json({
                success: false,
                error: 'User not found'
            });
        }
        
        const userData = userDoc.data();
        
        // If user already has a referral code, return it
        if (userData.referralCode) {
            return res.json({
                success: true,
                referralCode: userData.referralCode,
                referralCount: userData.referralCount || 0,
                referralRewards: userData.referralRewards || []
            });
        }
        
        // Generate a new unique code
        let code;
        let attempts = 0;
        const maxAttempts = 10;
        
        do {
            code = generateReferralCode();
            attempts++;
        } while (!(await isCodeUnique(code)) && attempts < maxAttempts);
        
        if (attempts >= maxAttempts) {
            return res.status(500).json({
                success: false,
                error: 'Failed to generate unique referral code'
            });
        }
        
        // Save the code to user
        await userRef.update({
            referralCode: code,
            referralCount: 0,
            referralRewards: []
        });
        
        res.json({
            success: true,
            referralCode: code,
            referralCount: 0,
            referralRewards: []
        });
        
    } catch (error) {
        console.error('Generate referral code error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to generate referral code'
        });
    }
};

// @desc    Apply referral code during signup
// @route   POST /api/users/referral/apply
// @access  Private
exports.applyReferralCode = async (req, res) => {
    try {
        const { referralCode } = req.body;
        const userId = req.userId;
        
        if (!referralCode) {
            return res.status(400).json({
                success: false,
                error: 'Referral code is required'
            });
        }
        
        // Convert to uppercase for case-insensitive comparison
        const code = referralCode.toUpperCase();
        
        // Check if user already used a referral code
        const userRef = admin.firestore().collection('users').doc(userId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            return res.status(404).json({
                success: false,
                error: 'User not found'
            });
        }
        
        const userData = userDoc.data();
        
        if (userData.referredBy) {
            return res.status(400).json({
                success: false,
                error: 'You have already used a referral code'
            });
        }
        
        // Find the referrer
        const referrerSnapshot = await admin.firestore()
            .collection('users')
            .where('referralCode', '==', code)
            .limit(1)
            .get();
        
        if (referrerSnapshot.empty) {
            return res.status(404).json({
                success: false,
                error: 'Invalid referral code'
            });
        }
        
        const referrerDoc = referrerSnapshot.docs[0];
        const referrerId = referrerDoc.id;
        const referrerData = referrerDoc.data();
        
        // Check if user is trying to use their own code
        if (referrerId === userId) {
            return res.status(400).json({
                success: false,
                error: 'You cannot use your own referral code'
            });
        }
        
        // Check if referrer has reached maximum referrals (12 per year)
        const oneYearAgo = new Date();
        oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);
        
        const recentRewards = (referrerData.referralRewards || []).filter(reward => {
            return new Date(reward.date) > oneYearAgo;
        });
        
        if (recentRewards.length >= 12) {
            return res.status(400).json({
                success: false,
                error: 'This referral code has reached its maximum usage limit'
            });
        }
        
        // Start a batch write
        const batch = admin.firestore().batch();
        
        // Update new user
        batch.update(userRef, {
            referredBy: referrerId,
            // Give 1 month free (no additional trial extension - they just get the subscription free for 1 month)
            referralBenefit: {
                type: 'free_month',
                value: 30,
                appliedAt: new Date().toISOString()
            }
        });
        
        // Update referrer
        const newReward = {
            userId: userId,
            date: new Date().toISOString(),
            type: 'referral',
            value: 30 // 30 days
        };
        
        batch.update(referrerDoc.ref, {
            referralCount: admin.firestore.FieldValue.increment(1),
            referralRewards: admin.firestore.FieldValue.arrayUnion(newReward)
        });
        
        // Commit the batch
        await batch.commit();
        
        res.json({
            success: true,
            message: 'Referral code applied successfully! You get 1 month free.',
            referralBenefit: {
                type: 'free_month',
                value: 30
            }
        });
        
    } catch (error) {
        console.error('Apply referral code error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to apply referral code'
        });
    }
};

// @desc    Get user's referral status
// @route   GET /api/users/referral/status
// @access  Private
exports.getReferralStatus = async (req, res) => {
    try {
        const userId = req.userId;
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        
        if (!userDoc.exists) {
            return res.status(404).json({
                success: false,
                error: 'User not found'
            });
        }
        
        const userData = userDoc.data();
        
        // Calculate available rewards
        const oneYearAgo = new Date();
        oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);
        
        const allRewards = userData.referralRewards || [];
        const recentRewards = allRewards.filter(reward => {
            return new Date(reward.date) > oneYearAgo;
        });
        
        const unclaimedRewards = allRewards.filter(reward => !reward.claimed);
        
        res.json({
            success: true,
            referralCode: userData.referralCode || null,
            referralCount: userData.referralCount || 0,
            totalRewards: allRewards.length,
            recentRewards: recentRewards.length,
            unclaimedRewards: unclaimedRewards.length,
            remainingReferrals: Math.max(0, 12 - recentRewards.length),
            referralLink: userData.referralCode ? 
                `circles://referral?code=${userData.referralCode}` : null
        });
        
    } catch (error) {
        console.error('Get referral status error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get referral status'
        });
    }
};

// @desc    Claim referral rewards
// @route   POST /api/users/referral/claim
// @access  Private
exports.claimReferralRewards = async (req, res) => {
    try {
        const userId = req.userId;
        const userRef = admin.firestore().collection('users').doc(userId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            return res.status(404).json({
                success: false,
                error: 'User not found'
            });
        }
        
        const userData = userDoc.data();
        const rewards = userData.referralRewards || [];
        const unclaimedRewards = rewards.filter(reward => !reward.claimed);
        
        if (unclaimedRewards.length === 0) {
            return res.status(400).json({
                success: false,
                error: 'No unclaimed rewards available'
            });
        }
        
        // Calculate total days to add
        const totalDays = unclaimedRewards.reduce((sum, reward) => sum + (reward.value || 30), 0);
        
        // Mark rewards as claimed
        const updatedRewards = rewards.map(reward => {
            if (!reward.claimed) {
                return { ...reward, claimed: true, claimedDate: new Date().toISOString() };
            }
            return reward;
        });
        
        // Calculate new subscription expiry date
        let newExpiryDate;
        if (userData.subscriptionExpiryDate) {
            const currentExpiry = new Date(userData.subscriptionExpiryDate);
            const now = new Date();
            const baseDate = currentExpiry > now ? currentExpiry : now;
            newExpiryDate = new Date(baseDate.getTime() + totalDays * 24 * 60 * 60 * 1000);
        } else {
            // If no active subscription, add days from now
            newExpiryDate = new Date(Date.now() + totalDays * 24 * 60 * 60 * 1000);
        }
        
        // Update user
        await userRef.update({
            referralRewards: updatedRewards,
            subscriptionExpiryDate: newExpiryDate.toISOString(),
            subscriptionStatus: 'active'
        });
        
        res.json({
            success: true,
            message: `Successfully claimed ${unclaimedRewards.length} referral rewards`,
            daysAdded: totalDays,
            newExpiryDate: newExpiryDate.toISOString()
        });
        
    } catch (error) {
        console.error('Claim referral rewards error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to claim referral rewards'
        });
    }
};