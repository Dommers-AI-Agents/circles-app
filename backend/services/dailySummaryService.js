const { getFirestore, FieldValue } = require('../config/firebase');
const notificationService = require('./notificationService');
const emailService = require('./emailService');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

// WEEKLY since 2026-09-15 (Wes: "daily is too much"). The module, the
// `dailySummary` preference key, the `daily_summary` push type, the
// `lastDailySummary` stamp and the /daily-summary routes keep their names so
// shipped iOS builds keep working; everything they describe is now a
// once-a-week recap of the last 7 days that also reports the user's FavCoins.
class DailySummaryService {
  constructor() {
    this.batchSize = 50; // Process users in batches (stats + push fan-out; email is pooled)
    this.windowDays = 7;
    // Local weekday the recap goes out (0 = Sunday … 6 = Saturday)
    this.summaryWeekday = 1; // Monday
  }

  // Send weekly summaries to all eligible users.
  // Runs every hour: each user gets their summary on SUMMARY_WEEKDAY at the
  // hour of their preferred summaryTime, evaluated in their own timezone
  // (both from notificationPreferences; defaults 12:00 America/New_York).
  async sendDailySummaries() {
    console.log('📊 Starting weekly summary generation...');

    try {
      // Implement distributed lock to prevent concurrent executions
      const lockAcquired = await this.acquireDailySummaryLock();
      if (!lockAcquired) {
        console.log('⚠️ Weekly summary already running for this hour - skipping execution');
        return;
      }

      console.log('🔒 Acquired weekly summary execution lock');

      try {
        // Get all users with daily summary enabled
        const usersSnapshot = await db.collection(COLLECTIONS.USERS)
          .where('notificationPreferences.dailySummary', '==', true)
          .get();

      if (usersSnapshot.empty) {
        console.log('No users have the weekly summary enabled');
        return;
      }

      const allUsers = [];
      usersSnapshot.forEach(doc => allUsers.push({ id: doc.id, ...doc.data() }));

      // Only users whose local clock is at their chosen summary hour on summary day right now
      const users = allUsers.filter(user => this.isUsersSummaryHour(user));

      console.log(`📊 Processing weekly summaries for ${users.length} of ${allUsers.length} enabled users (local weekday+hour match)`);

      // Process users in batches
      for (let i = 0; i < users.length; i += this.batchSize) {
        const batch = users.slice(i, i + this.batchSize);
        await Promise.all(batch.map(user => this.generateAndSendSummary(user)));
      }

        console.log('✅ Weekly summaries completed');
      } finally {
        // Always release the lock, even if there was an error
        await this.releaseDailySummaryLock();
        console.log('🔓 Released weekly summary execution lock');
      }
    } catch (error) {
      console.error('❌ Error in sendDailySummaries:', error);
      // Make sure to release lock on error
      await this.releaseDailySummaryLock();
      throw error;
    }
  }

  // Generate and send summary for individual user. `stamp: false` sends
  // without marking the week done (test route) so a manual check never
  // suppresses the real Monday send.
  async generateAndSendSummary(user, { stamp = true } = {}) {
    try {
      const userId = user.id;
      const stats = await this.gatherUserStats(userId);
      
      // Check if user has already received this week's summary
      if (await this.hasReceivedThisWeeksSummary(userId)) {
        console.log(`⏭️ User ${user.displayName || userId} already received this week's summary`);
        return;
      }

      // Quiet weeks stay quiet: a summary only goes out when there is real
      // network activity (or FavCoins earned) to report. (The old "engagement
      // prompt" fallback was retired — the engagement reminder job already
      // covers re-engagement, and stacking both trained users to mute
      // notifications.)
      if (!this.hasActivity(stats)) {
        console.log(`⏭️ Skipping summary for ${user.displayName || userId} - no activity this week`);
        return;
      }

      const notification = this.buildSummaryNotification(stats, user);

      // Send push notification (best-effort; the email is the deliverable)
      try {
        await notificationService.sendToUser(userId, notification);
      } catch (pushError) {
        console.error(`⚠️ Weekly summary push failed for ${userId}:`, pushError.message);
      }

      // Send email summary. Only a delivered email (or a user with no email
      // at all) stamps the week as done — a bounced send used to be stamped
      // too, which silently dropped everyone's summary for the week.
      const emailed = await this.sendSummaryEmail(user, stats, notification);
      if (!emailed && user.email) {
        console.warn(`⚠️ Weekly summary for ${user.displayName || userId} NOT stamped (email failed) — will retry next matching hour`);
        return;
      }

      if (stamp) await this.recordSummarySent(userId);

      console.log(`✅ Sent weekly summary to ${user.displayName || userId}${stamp ? '' : ' (not stamped)'}`);
    } catch (error) {
      console.error(`❌ Error sending summary to user ${user.id}:`, error);
    }
  }

  // Gather statistics for user's network activity over the last windowDays
  async gatherUserStats(userId) {
    // Short TTL cache: the summary describes the past week, which barely
    // changes within minutes — and the modal fetch usually lands right after
    // the scheduler computed the same stats to build the push.
    this._statsCache = this._statsCache || new Map();
    const cached = this._statsCache.get(userId);
    if (cached && Date.now() - cached.at < 10 * 60 * 1000) return cached.stats;

    const stats = {
      newPlaces: 0,
      newPlacesByCategory: {},
      newConnections: 0,
      unreadMessages: 0,
      circleUpdates: 0,
      placeComments: 0,
      placeLikes: 0,
      topContributors: [],
      connectionCount: 0,
      userPlaceCount: 0,
      windowDays: this.windowDays,
      favCoins: null
    };

    // Window start: midnight `windowDays` ago. (Variable kept as `yesterday`
    // below only to keep the diff of the query code readable.)
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - this.windowDays);
    yesterday.setHours(0, 0, 0, 0);
    stats.windowStart = yesterday.toISOString();

    try {
      // Get user's connections (need to check both userId and connectedUserId fields)
      const [connectionsAsUser, connectionsAsConnected] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', userId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('connectedUserId', '==', userId)
          .where('status', '==', 'accepted')
          .get()
      ]);

      const connectionIds = [];
      
      // Process connections where user is the initiator
      connectionsAsUser.forEach(doc => {
        const connection = doc.data();
        if (connection.connectedUserId) {
          connectionIds.push(connection.connectedUserId);
        }
      });
      
      // Process connections where user is the recipient
      connectionsAsConnected.forEach(doc => {
        const connection = doc.data();
        if (connection.userId) {
          connectionIds.push(connection.userId);
        }
      });
      
      // Remove duplicates
      const uniqueConnectionIds = [...new Set(connectionIds)];
      
      // Store total connection count
      stats.connectionCount = uniqueConnectionIds.length;
      
      // Replace connectionIds with unique ones
      connectionIds.length = 0;
      connectionIds.push(...uniqueConnectionIds);

      // New connections in the window
      try {
        const [newConnectionsAsUser, newConnectionsAsConnected] = await Promise.all([
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', userId)
            .where('status', '==', 'accepted')
            .where('acceptedAt', '>=', yesterday.toISOString())
            .get(),
          db.collection(COLLECTIONS.CONNECTIONS)
            .where('connectedUserId', '==', userId)
            .where('status', '==', 'accepted')
            .where('acceptedAt', '>=', yesterday.toISOString())
            .get()
        ]);
        
        stats.newConnections = newConnectionsAsUser.size + newConnectionsAsConnected.size;
      } catch (error) {
        console.log('⚠️ Could not query new connections (index may be needed)');
        stats.newConnections = 0;
      }

      if (connectionIds.length > 0) {
        // Get new places from network (batch query due to Firestore limits)
        const placePromises = [];
        for (let i = 0; i < connectionIds.length; i += 10) {
          const batch = connectionIds.slice(i, i + 10);
          placePromises.push(
            db.collection(COLLECTIONS.PLACES)
              .where('addedBy', 'in', batch)
              .where('createdAt', '>=', yesterday.toISOString())
              .get()
          );
        }

        const placeSnapshots = await Promise.all(placePromises);
        const contributorCounts = {};

        placeSnapshots.forEach(snapshot => {
          snapshot.forEach(doc => {
            const place = doc.data();
            stats.newPlaces++;
            
            // Count by category
            const category = place.category || 'other';
            stats.newPlacesByCategory[category] = (stats.newPlacesByCategory[category] || 0) + 1;
            
            // Track contributors
            contributorCounts[place.addedBy] = (contributorCounts[place.addedBy] || 0) + 1;
          });
        });

        // Get top contributors
        const topContributorIds = Object.entries(contributorCounts)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 3)
          .map(([userId, count]) => ({ userId, count }));

        // Fetch contributor names (parallel — max 3)
        const contributorDocs = await Promise.all(
          topContributorIds.map(c => db.collection(COLLECTIONS.USERS).doc(c.userId).get())
        );
        contributorDocs.forEach((userDoc, i) => {
          if (userDoc.exists) {
            stats.topContributors.push({
              name: userDoc.data().displayName || 'A connection',
              count: topContributorIds[i].count
            });
          }
        });
      }

      // Get unread messages count
      const conversationsSnapshot = await db.collection(COLLECTIONS.CONVERSATIONS)
        .where('participants', 'array-contains', userId)
        .get();

      for (const convDoc of conversationsSnapshot.docs) {
        const conversation = convDoc.data();
        const unreadCount = conversation.unreadCounts?.[userId] || 0;
        stats.unreadMessages += unreadCount;
      }

      // Get activity on user's places (comments and likes).
      //
      // INVERTED from the original per-place fan-out: a heavy user (2k saves)
      // used to trigger ~4,000 parallel Firestore queries here, which is why
      // the summary modal sat on a spinner (and sometimes timed out). A single
      // day's comments/likes across the whole platform is a tiny set, so we
      // range-scan those once each and filter to the user's places in memory.
      // select() keeps the places scan to two fields instead of full docs.
      const userPlacesSnapshot = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', userId)
        .select('globalPlaceId')
        .get();

      const userPlaceIds = new Set(userPlacesSnapshot.docs.map(doc => doc.id));

      // Store user's total place count
      stats.userPlaceCount = userPlaceIds.size;

      if (userPlaceIds.size > 0) {
        const cutoff = yesterday.toISOString();
        const userGlobalPlaceIds = new Set(
          userPlacesSnapshot.docs.map(doc => doc.data().globalPlaceId).filter(Boolean)
        );

        const [recentComments, recentLikes] = await Promise.all([
          db.collection('placeComments').where('createdAt', '>=', cutoff).get(),
          db.collection('placeLikes').where('createdAt', '>=', cutoff).get()
        ]);

        recentComments.docs.forEach(doc => {
          if (userGlobalPlaceIds.has(doc.data().globalPlaceId)) stats.placeComments += 1;
        });
        recentLikes.docs.forEach(doc => {
          if (userPlaceIds.has(doc.data().placeId)) stats.placeLikes += 1;
        });
      }

    } catch (error) {
      console.error(`Error gathering stats for user ${userId}:`, error);
    }

    // FavCoins: balance + what the week earned (never fails the summary)
    try {
      stats.favCoins = await this.gatherFavCoinStats(userId, yesterday);
    } catch (error) {
      console.error(`Error gathering FavCoin stats for user ${userId}:`, error.message);
    }

    this._statsCache.set(userId, { stats, at: Date.now() });
    return stats;
  }

  // The user's piggy bank: spendable/pending/lifetime balances plus the coins
  // earned inside the summary window. Earn rows only — claims (coins leaving
  // for the wallet) and reversals don't count as "earned this week".
  async gatherFavCoinStats(userId, windowStart) {
    const { PIGGY_COLLECTIONS } = require('../models/PiggyBankModels');
    const [bankDoc, weekSnap] = await Promise.all([
      db.collection(PIGGY_COLLECTIONS.BANKS).doc(userId).get(),
      db.collection(PIGGY_COLLECTIONS.LEDGER)
        .where('userId', '==', userId)
        .where('createdAt', '>=', windowStart.toISOString())
        .orderBy('createdAt', 'desc')
        .get()
    ]);
    const round2 = (n) => Math.round((n || 0) * 100) / 100;
    const bank = bankDoc.exists ? bankDoc.data() : {};
    let earnedThisWeek = 0;
    let earnEvents = 0;
    weekSnap.forEach((doc) => {
      const row = doc.data();
      if (row.eventType === 'claim' || row.reversedAt || (row.status && row.status.startsWith('claim'))) return;
      if (typeof row.coins === 'number' && row.coins > 0) {
        earnedThisWeek += row.coins;
        earnEvents += 1;
      }
    });
    return {
      confirmedCoins: round2(bank.confirmedCoins),
      pendingCoins: round2(bank.pendingCoins),
      lifetimeCoins: round2(bank.lifetimeCoins),
      settledOnChain: round2(bank.settledOnChain),
      hasWallet: !!bank.walletAddress,
      earnedThisWeek: round2(earnedThisWeek),
      earnEventsThisWeek: earnEvents
    };
  }

  // Check if user has any activity to report
  hasActivity(stats) {
    // Include new places from connections as activity!
    return stats.newPlaces > 0 || 
           stats.newConnections > 0 || 
           stats.unreadMessages > 0 || 
           stats.placeComments > 0 ||
           stats.placeLikes > 0 ||
           !!(stats.favCoins && stats.favCoins.earnedThisWeek > 0);
  }

  // "12.5 FavCoins" / "1 FavCoin" — plural is always "FavCoins", never "FavCoin's"
  formatCoins(n) {
    const value = Math.round((n || 0) * 100) / 100;
    const text = Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/0$/, '');
    return `${text} FavCoin${value === 1 ? '' : 's'}`;
  }

  // Build the summary notification
  buildSummaryNotification(stats, user) {
    const parts = [];
    const emojis = [];
    
    // New places from network
    if (stats.newPlaces > 0) {
      emojis.push('📍');
      parts.push(`${stats.newPlaces} new place${stats.newPlaces > 1 ? 's' : ''}`);
      
      // Add top category if significant
      const topCategory = Object.entries(stats.newPlacesByCategory)
        .sort((a, b) => b[1] - a[1])[0];
      if (topCategory && topCategory[1] >= 2) {
        // Include category name in parentheses for context
        const categoryName = topCategory[0].charAt(0).toUpperCase() + topCategory[0].slice(1);
        parts[parts.length - 1] += ` (${topCategory[1]} ${categoryName})`;
      }
    }

    // New connections
    if (stats.newConnections > 0) {
      emojis.push('👥');
      parts.push(`${stats.newConnections} new connection${stats.newConnections > 1 ? 's' : ''}`);
    }

    // Unread messages
    if (stats.unreadMessages > 0) {
      emojis.push('💬');
      parts.push(`${stats.unreadMessages} unread message${stats.unreadMessages > 1 ? 's' : ''}`);
    }

    // Activity on user's places
    const activityParts = [];
    if (stats.placeComments > 0) {
      activityParts.push(`${stats.placeComments} comment${stats.placeComments > 1 ? 's' : ''}`);
    }
    if (stats.placeLikes > 0) {
      activityParts.push(`${stats.placeLikes} like${stats.placeLikes > 1 ? 's' : ''}`);
    }
    if (activityParts.length > 0) {
      emojis.push('❤️');
      parts.push(activityParts.join(' & ') + ' on your places');
    }

    // FavCoins earned this week
    if (stats.favCoins && stats.favCoins.earnedThisWeek > 0) {
      emojis.push('🌵');
      parts.push(`+${this.formatCoins(stats.favCoins.earnedThisWeek)} earned`);
    }

    // Build title and body with more detail
    const title = `Your Weekly Summary`;
    
    // Create a concise but informative body
    let body = '';
    if (parts.length === 0) {
      body = 'Check out what\'s new in your network';
    } else if (parts.length === 1) {
      body = parts[0];
    } else if (parts.length === 2) {
      body = parts.join(' • ');
    } else {
      // For 3+ items, show first two with count of remaining
      body = parts.slice(0, 2).join(' • ') + ` + ${parts.length - 2} more`;
    }

    // Add emoji prefix to body for visual appeal
    const emojiPrefix = emojis.slice(0, 3).join(' ');
    if (emojiPrefix) {
      body = emojiPrefix + ' ' + body;
    }

    // Add top contributor mention if significant
    let contributorNote = '';
    if (stats.topContributors.length > 0 && stats.topContributors[0].count >= 2) {
      contributorNote = ` (${stats.topContributors[0].name} shared ${stats.topContributors[0].count})`;
    }

    // Format date for subtitle
    const today = new Date();
    const dateFormatter = new Intl.DateTimeFormat('en-US', { 
      month: 'long', 
      day: 'numeric',
      year: 'numeric'
    });
    const subtitle = `Week ending ${dateFormatter.format(today)}`;

    return {
      type: 'daily_summary',
      title,
      subtitle, // Add subtitle with formatted date
      body: body + contributorNote,
      // Summaries should not affect badge count - they're informational only
      badge: 0,
      data: {
        // Keep only essential fields to stay under APNS 4KB limit
        type: 'daily_summary',
        summaryDate: new Date().toISOString().split('T')[0]
        // Removed large fields that were causing APNS payload to exceed 4KB limit
        // The app can fetch full summary data via API when notification is tapped
      }
    };
  }

  // Get appropriate greeting emoji
  getGreeting(user) {
    const hour = new Date().getHours();
    if (hour < 12) return '🌅';
    if (hour < 17) return '☀️';
    return '🌙';
  }

  // Record that this week's summary was sent. `lastWeeklySummary` is the
  // dedupe key; `lastDailySummary` is still written for older scripts and
  // the admin reset route that read it.
  async recordSummarySent(userId) {
    try {
      const now = new Date().toISOString();
      await db.collection(COLLECTIONS.USERS).doc(userId).update({
        lastWeeklySummary: now,
        lastDailySummary: now
      });
    } catch (error) {
      console.error(`Error recording summary sent for ${userId}:`, error);
    }
  }

  // True when the user's local clock is currently in the hour of their chosen
  // summaryTime AND it's summary day (Monday) where they are. Invalid/missing
  // timezone falls back to America/New_York, which matches the historical
  // noon-ET behavior.
  isUsersSummaryHour(user, now = new Date()) {
    const prefs = user.notificationPreferences || {};
    const preferredHour = parseInt(String(prefs.summaryTime || '12:00').split(':')[0], 10);
    if (isNaN(preferredHour)) return false;

    const local = this.localClock(prefs.timezone, now);
    return local.weekday === this.summaryWeekday && local.hour === preferredHour;
  }

  // { hour (0-23), weekday (0=Sunday) } in the given IANA zone
  localClock(timeZone, now = new Date()) {
    const read = (zone) => {
      const parts = new Intl.DateTimeFormat('en-US', {
        timeZone: zone,
        hour: 'numeric',
        hour12: false,
        weekday: 'short'
      }).formatToParts(now);
      const hour = parseInt(parts.find((p) => p.type === 'hour').value, 10) % 24;
      const weekday = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
        .indexOf(parts.find((p) => p.type === 'weekday').value);
      return { hour, weekday };
    };
    try {
      return read(timeZone || 'America/New_York');
    } catch (error) {
      return read('America/New_York');
    }
  }

  // Check if user already received this week's summary. A rolling 6-day
  // window instead of a calendar compare: timezone-proof, and it still lets
  // next Monday's send through even across DST shifts. Reads ONLY the new
  // lastWeeklySummary stamp: the retired daily job kept writing
  // lastDailySummary right up to the deploy, and honoring it would have
  // silently skipped everyone's first Monday.
  isWithinWeeklyWindow(userData, now = Date.now()) {
    if (!userData || !userData.lastWeeklySummary) return false;
    const hoursSinceLast = (now - new Date(userData.lastWeeklySummary).getTime()) / (1000 * 60 * 60);
    return hoursSinceLast < 6 * 24;
  }

  async hasReceivedThisWeeksSummary(userId) {
    try {
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
      if (!userDoc.exists) return false;
      return this.isWithinWeeklyWindow(userDoc.data());
    } catch (error) {
      console.error(`Error checking summary status for ${userId}:`, error);
      return false;
    }
  }

  // Send summary email
  // Resolves true when the email was handed to the SMTP server (or the user
  // has no email address), false on failure — the caller decides whether the
  // week is done.
  async sendSummaryEmail(user, stats, notification) {
    try {
      if (!user.email) {
        console.log(`⚠️ No email for user ${user.displayName}`);
        return true;
      }

      const emailHtml = this.buildSummaryEmailHtml(user, stats, notification);

      await emailService.sendEmail({
        to: user.email,
        subject: notification.title,
        html: emailHtml
      });

      console.log(`📧 Sent summary email to ${user.email}`);
      return true;
    } catch (error) {
      console.error(`❌ Error sending summary email to ${user.email}:`, error.message);
      // Don't throw - email failure shouldn't stop the batch
      return false;
    }
  }

  // Build HTML email for daily summary
  buildSummaryEmailHtml(user, stats, notification) {
    const today = new Date().toLocaleDateString('en-US', { 
      weekday: 'long', 
      year: 'numeric', 
      month: 'long', 
      day: 'numeric' 
    });

    const statsHtml = [];
    
    if (stats.newPlaces > 0) {
      const categoryList = Object.entries(stats.newPlacesByCategory)
        .sort((a, b) => b[1] - a[1])
        .map(([cat, count]) => `${count} ${cat}${count > 1 ? 's' : ''}`)
        .join(', ');
      
      statsHtml.push(`
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
          <h3 style="margin: 0 0 10px 0; color: #4CAF50;">🆕 ${stats.newPlaces} New Places</h3>
          <p style="margin: 0; color: #666;">${categoryList}</p>
          ${stats.topContributors.length > 0 ? `
            <p style="margin: 10px 0 0 0; color: #666;">
              Top contributors: ${stats.topContributors.slice(0, 3)
                .map(c => `${c.name} (${c.count})`)
                .join(', ')}
            </p>
          ` : ''}
        </div>
      `);
    }

    if (stats.newConnections > 0) {
      statsHtml.push(`
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
          <h3 style="margin: 0 0 10px 0; color: #2196F3;">👥 ${stats.newConnections} New Connection${stats.newConnections > 1 ? 's' : ''}</h3>
          <p style="margin: 0; color: #666;">Your network is growing!</p>
        </div>
      `);
    }

    if (stats.unreadMessages > 0) {
      statsHtml.push(`
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
          <h3 style="margin: 0 0 10px 0; color: #FF9800;">💬 ${stats.unreadMessages} Unread Message${stats.unreadMessages > 1 ? 's' : ''}</h3>
          <p style="margin: 0; color: #666;">Check your messages to stay connected</p>
        </div>
      `);
    }

    // FavCoins card — always present when the user has a piggy bank so the
    // email doubles as the weekly balance statement
    if (stats.favCoins && (stats.favCoins.lifetimeCoins > 0 || stats.favCoins.earnedThisWeek > 0)) {
      const c = stats.favCoins;
      const growth = c.earnedThisWeek > 0
        ? `<p style="margin: 0 0 6px 0; color: #2e7d32; font-weight: 600;">+${this.formatCoins(c.earnedThisWeek)} earned this week (${c.earnEventsThisWeek} reward${c.earnEventsThisWeek === 1 ? '' : 's'})</p>`
        : `<p style="margin: 0 0 6px 0; color: #666;">No new FavCoins this week — add a place, check in, or share a circle to earn more.</p>`;
      const pending = c.pendingCoins > 0
        ? ` <span style="color: #999;">(+${this.formatCoins(c.pendingCoins)} clearing)</span>`
        : '';
      const walletLine = c.hasWallet
        ? `${c.settledOnChain > 0 ? `${this.formatCoins(c.settledOnChain)} already sent to your wallet. ` : ''}Claim your balance to your Cactus wallet 🌵 anytime from the Piggy Bank.`
        : 'Create your wallet in the app and you can claim them to the Cactus blockchain 🌵.';
      statsHtml.push(`
        <div style="background: #f1f8e9; padding: 15px; border-radius: 8px; margin-bottom: 15px; border: 1px solid #c5e1a5;">
          <h3 style="margin: 0 0 10px 0; color: #558b2f;">🌵 Your FavCoins</h3>
          <p style="margin: 0 0 6px 0; color: #333; font-size: 18px; font-weight: 700;">${this.formatCoins(c.confirmedCoins)} available${pending}</p>
          ${growth}
          <p style="margin: 0 0 6px 0; color: #666;">Lifetime earned: ${this.formatCoins(c.lifetimeCoins)}</p>
          <p style="margin: 10px 0 0 0; color: #666; font-size: 13px; line-height: 1.5;">
            FavCoins are real crypto coins on the Cactus blockchain 🌵 that you earn for sharing the places you love.
            ${walletLine}<br>
            See them in FavCircles: <strong>Rewards → Piggy Bank</strong>.
          </p>
        </div>
      `);
    }

    if (stats.placeComments > 0 || stats.placeLikes > 0) {
      const activities = [];
      if (stats.placeComments > 0) activities.push(`${stats.placeComments} comment${stats.placeComments > 1 ? 's' : ''}`);
      if (stats.placeLikes > 0) activities.push(`${stats.placeLikes} like${stats.placeLikes > 1 ? 's' : ''}`);
      
      statsHtml.push(`
        <div style="background: #f8f9fa; padding: 15px; border-radius: 8px; margin-bottom: 15px;">
          <h3 style="margin: 0 0 10px 0; color: #E91E63;">❤️ Activity on Your Places</h3>
          <p style="margin: 0; color: #666;">${activities.join(' and ')}</p>
        </div>
      `);
    }

    return `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>${notification.title}</title>
      </head>
      <body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff;">
          <!-- Header -->
          <div style="background-color: #4CAF50; padding: 30px 20px; text-align: center;">
            <h1 style="margin: 0; color: #ffffff; font-size: 24px;">Circles</h1>
            <p style="margin: 10px 0 0 0; color: #ffffff; font-size: 16px;">Your Weekly Summary</p>
          </div>
          
          <!-- Content -->
          <div style="padding: 30px 20px;">
            <h2 style="margin: 0 0 20px 0; color: #333; font-size: 20px;">
              Hi ${user.displayName || 'there'} 👋
            </h2>
            
            <p style="color: #666; line-height: 1.6; margin: 0 0 20px 0;">
              Here's what happened in your Circles network this week:
            </p>
            
            ${statsHtml.join('')}
            
            <!-- CTA Buttons -->
            <div style="text-align: center; margin: 30px 0;">
              <a href="https://api.favcircles.com/app/daily-summary" style="display: inline-block; background-color: #4CAF50; color: #ffffff; text-decoration: none; padding: 12px 30px; border-radius: 25px; font-weight: 600;">
                View in App
              </a>
              ${stats.favCoins ? `
              <a href="https://api.favcircles.com/app/open?path=create-wallet" style="display: inline-block; background-color: #558b2f; color: #ffffff; text-decoration: none; padding: 12px 30px; border-radius: 25px; font-weight: 600; margin: 8px 0 0 0;">
                🌵 See my FavCoins
              </a>` : ''}
            </div>
            
            <!-- Footer -->
            <div style="border-top: 1px solid #eee; margin-top: 40px; padding-top: 20px; text-align: center;">
              <p style="color: #999; font-size: 14px; margin: 0;">
                ${today}
              </p>
              <p style="color: #999; font-size: 12px; margin: 10px 0 0 0;">
                You're receiving this because you have the weekly summary enabled.<br>
                <a href="https://api.favcircles.com/app/open?path=settings/notifications" style="color: #4CAF50;">Manage notification preferences</a>
              </p>
            </div>
          </div>
        </div>
      </body>
      </html>
    `;
  }

  // Acquire distributed lock for daily summary execution
  async acquireDailySummaryLock() {
    // Keyed by UTC date+hour: the job runs hourly (each hour serves the users
    // whose local time matches), so the lock only guards against concurrent
    // runs within the same hour, not against later hours the same day
    const now = new Date();
    const today = `${now.toISOString().split('T')[0]}-${String(now.getUTCHours()).padStart(2, '0')}`;
    const lockId = `daily-summary-${today}`;
    const lockDoc = db.collection('system_locks').doc(lockId);
    
    try {
      // Try to create the lock document atomically
      await lockDoc.create({
        lockType: 'daily_summary',
        date: today,
        acquiredAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(), // 2 hour expiry
        status: 'acquired'
      });
      
      console.log(`🔒 Successfully acquired lock for daily summary: ${lockId}`);
      return true;
    } catch (error) {
      if (error.code === 6) { // ALREADY_EXISTS error code
        console.log(`⚠️ Daily summary lock already exists for ${today} - another process is running`);
        return false;
      } else {
        console.error('Error acquiring daily summary lock:', error);
        throw error;
      }
    }
  }

  // Release distributed lock for daily summary execution
  async releaseDailySummaryLock() {
    const now = new Date();
    const today = `${now.toISOString().split('T')[0]}-${String(now.getUTCHours()).padStart(2, '0')}`;
    const lockId = `daily-summary-${today}`;
    const lockDoc = db.collection('system_locks').doc(lockId);
    
    try {
      await lockDoc.update({
        status: 'completed',
        completedAt: new Date().toISOString()
      });
      console.log(`🔓 Successfully released lock for daily summary: ${lockId}`);
    } catch (error) {
      // Don't throw error on lock release failure - just log it
      console.warn('Warning: Could not release daily summary lock:', error.message);
    }
  }
}

// Create singleton instance
const dailySummaryService = new DailySummaryService();

module.exports = dailySummaryService;