// backend/services/emailService.js
let nodemailer;
try {
  nodemailer = require('nodemailer');
  console.log('✅ Nodemailer loaded successfully');
  console.log('📧 Nodemailer type:', typeof nodemailer);
  console.log('📧 Nodemailer keys:', Object.keys(nodemailer || {}));
  console.log('📧 createTransporter type:', typeof nodemailer?.createTransporter);
} catch (error) {
  console.error('❌ Failed to load nodemailer:', error);
  throw error;
}

class EmailService {
  constructor() {
    console.log('📧 Initializing EmailService...');
    console.log('📧 Nodemailer version:', nodemailer?.version || 'unknown');
    
    // Configure email transporter based on EMAIL_SERVICE setting
    const emailService = process.env.EMAIL_SERVICE || 'gmail';
    
    if (emailService === 'custom') {
      // Use custom SMTP configuration
      if (!process.env.SMTP_HOST || !process.env.SMTP_USER || !process.env.SMTP_PASS) {
        console.warn('⚠️ Custom SMTP credentials not configured. Email service will not work.');
        console.warn('⚠️ Set SMTP_HOST, SMTP_USER, and SMTP_PASS environment variables.');
        
        // Create a dummy transporter that logs instead of sending
        this.createMockTransporter();
      } else {
        this.transporter = nodemailer.createTransport({
          host: process.env.SMTP_HOST,
          port: parseInt(process.env.SMTP_PORT || '587'),
          secure: process.env.SMTP_SECURE === 'true', // true for 465, false for other ports
          auth: {
            user: process.env.SMTP_USER,
            pass: process.env.SMTP_PASS
          },
          tls: {
            // Do not fail on invalid certs (useful for self-signed)
            rejectUnauthorized: false
          }
        });
        
        console.log('📧 Custom SMTP configured:', {
          host: process.env.SMTP_HOST,
          port: process.env.SMTP_PORT,
          user: process.env.SMTP_USER
        });
      }
    } else if (emailService === 'gmail') {
      // Use Gmail SMTP
      if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
        console.warn('⚠️ Gmail credentials not configured. Email service will not work.');
        console.warn('⚠️ Set GMAIL_USER and GMAIL_APP_PASSWORD environment variables.');
        console.warn('⚠️ Note: You must use an App Password, not your regular Gmail password.');
        console.warn('⚠️ Create an App Password at: https://myaccount.google.com/apppasswords');
        
        this.createMockTransporter();
      } else {
        this.transporter = nodemailer.createTransport({
          service: 'gmail',
          auth: {
            user: process.env.GMAIL_USER,
            pass: process.env.GMAIL_APP_PASSWORD // Must use App Password, not regular password
          }
        });
        
        console.log('📧 Gmail SMTP configured with user:', process.env.GMAIL_USER);
      }
    } else {
      console.warn('⚠️ Unknown EMAIL_SERVICE:', emailService);
      this.createMockTransporter();
    }

    // Store email configuration
    this.fromAddress = process.env.EMAIL_FROM_ADDRESS || process.env.GMAIL_USER || process.env.SMTP_USER || 'noreply@circles-app.com';
    this.fromName = process.env.EMAIL_FROM_NAME || 'Circles';
  }

  createMockTransporter() {
    // Create a dummy transporter that logs instead of sending
    this.transporter = {
      sendMail: async (options) => {
        console.log('📧 [MOCK] Would send email:', {
          to: options.to,
          subject: options.subject,
          from: options.from
        });
        return { messageId: 'mock-message-id' };
      },
      verify: async () => {
        console.log('📧 [MOCK] Email service in mock mode');
        return true;
      }
    };
  }

  async sendConnectionRequestEmail(toEmail, fromUserName, fromUserId) {
    try {
      const mailOptions = {
        from: `"${this.fromName}" <${this.fromAddress}>`,
        to: toEmail,
        subject: `${fromUserName} wants to connect with you on Circles`,
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background-color: #007AFF; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
              .content { background-color: #f4f4f4; padding: 20px; border-radius: 0 0 8px 8px; }
              .button { display: inline-block; padding: 12px 24px; background-color: #007AFF; color: white; text-decoration: none; border-radius: 6px; margin: 20px 0; }
              .footer { text-align: center; padding: 20px; color: #666; font-size: 12px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>New Connection Request</h1>
              </div>
              <div class="content">
                <h2>Hi there!</h2>
                <p><strong>${fromUserName}</strong> wants to connect with you on Circles.</p>
                <p>Once connected, you'll be able to:</p>
                <ul>
                  <li>Share circles and places with each other</li>
                  <li>See each other's public and network-only content</li>
                  <li>Send messages and suggestions</li>
                </ul>
                <p style="text-align: center;">
                  <a href="${process.env.APP_LINK_BASE || 'https://api.favcircles.com'}/app/open?path=network" class="button">View Request</a>
                </p>
                <p>Or open the Circles app on your phone to respond to this request.</p>
              </div>
              <div class="footer">
                <p>This email was sent by Circles App. If you didn't expect this email, you can safely ignore it.</p>
              </div>
            </div>
          </body>
          </html>
        `,
        text: `${fromUserName} wants to connect with you on Circles. Open the app to view and respond to this connection request.`
      };

      const info = await this.transporter.sendMail(mailOptions);
      console.log('📧 Connection request email sent:', info.messageId);
      return info;
    } catch (error) {
      console.error('📧 Error sending connection request email:', error);
      throw error;
    }
  }

  async sendConnectionAcceptedEmail(toEmail, acceptedByName) {
    try {
      const mailOptions = {
        from: `"${this.fromName}" <${this.fromAddress}>`,
        to: toEmail,
        subject: `${acceptedByName} accepted your connection request`,
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background-color: #34C759; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
              .content { background-color: #f4f4f4; padding: 20px; border-radius: 0 0 8px 8px; }
              .button { display: inline-block; padding: 12px 24px; background-color: #34C759; color: white; text-decoration: none; border-radius: 6px; margin: 20px 0; }
              .footer { text-align: center; padding: 20px; color: #666; font-size: 12px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>Connection Accepted!</h1>
              </div>
              <div class="content">
                <h2>Great news!</h2>
                <p><strong>${acceptedByName}</strong> has accepted your connection request.</p>
                <p>You can now:</p>
                <ul>
                  <li>View their shared circles and places</li>
                  <li>Share your own circles with them</li>
                  <li>Send messages and suggestions</li>
                </ul>
                <p style="text-align: center;">
                  <a href="${process.env.APP_LINK_BASE || 'https://api.favcircles.com'}/app/open?path=network" class="button">View Connection</a>
                </p>
              </div>
              <div class="footer">
                <p>This email was sent by Circles App.</p>
              </div>
            </div>
          </body>
          </html>
        `,
        text: `${acceptedByName} has accepted your connection request on Circles. You can now share circles and places with each other.`
      };

      const info = await this.transporter.sendMail(mailOptions);
      console.log('📧 Connection accepted email sent:', info.messageId);
      return info;
    } catch (error) {
      console.error('📧 Error sending connection accepted email:', error);
      throw error;
    }
  }

  // Test email configuration
  async testEmailConfiguration() {
    try {
      await this.transporter.verify();
      console.log('📧 Email service is configured correctly');
      return true;
    } catch (error) {
      console.error('📧 Email service configuration error:', error);
      return false;
    }
  }

  // Send a test email
  async sendTestEmail(toEmail, userName) {
    try {
      const mailOptions = {
        from: `"${this.fromName}" <${this.fromAddress}>`,
        to: toEmail,
        subject: 'Test Email from Circles',
        html: `
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background-color: #007AFF; color: white; padding: 20px; text-align: center; border-radius: 8px 8px 0 0; }
              .content { background-color: #f4f4f4; padding: 20px; border-radius: 0 0 8px 8px; }
              .footer { text-align: center; padding: 20px; color: #666; font-size: 12px; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>Test Email Successful!</h1>
              </div>
              <div class="content">
                <h2>Hello ${userName || 'there'}!</h2>
                <p>This is a test email from the Circles app to verify that email sending is working correctly.</p>
                <p><strong>Email Configuration:</strong></p>
                <ul>
                  <li>Service: ${process.env.EMAIL_SERVICE || 'Not configured'}</li>
                  <li>From: ${this.fromAddress}</li>
                  <li>SMTP Host: ${process.env.SMTP_HOST || process.env.GMAIL_USER ? 'Gmail' : 'Not configured'}</li>
                </ul>
                <p>If you received this email, your email configuration is working properly!</p>
              </div>
              <div class="footer">
                <p>This test email was sent from Circles App at ${new Date().toLocaleString()}</p>
              </div>
            </div>
          </body>
          </html>
        `,
        text: `Hello ${userName || 'there'}! This is a test email from Circles to verify email sending is working. If you received this, your configuration is correct!`
      };

      const info = await this.transporter.sendMail(mailOptions);
      console.log('📧 Test email sent successfully:', info.messageId);
      return { success: true, messageId: info.messageId };
    } catch (error) {
      console.error('📧 Error sending test email:', error);
      throw error;
    }
  }

  // Website email-capture flow: visitor left their email on favcircles.com
  // with the FavCoins promise. Walks them from download → signup (SAME email)
  // → first place = 25 FavCoins → piggy bank → Cactus wallet claim.
  async sendWebsiteLeadEmail(toEmail) {
    try {
      const subject = 'Your FavCoins are waiting 🌵';
      const htmlContent = `
        <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1a202c;">
          <h1 style="font-size: 22px;">Your FavCoins are waiting 🌵</h1>
          <p style="font-size: 15px; line-height: 1.6;">Hi there,</p>
          <p style="font-size: 15px; line-height: 1.6;">
            Thanks for your interest in FavCircles! FavCoins are rewards you earn for
            sharing the places you love — and they're real coins on the
            <strong>Cactus blockchain</strong> 🌵 that you can claim to your own wallet.
            Here's how to get your first ones:
          </p>
          <ol style="font-size: 15px; line-height: 1.8; padding-left: 20px;">
            <li><a href="https://apps.apple.com/us/app/favcircles/id6746807095" style="color: #667eea; font-weight: 600;">Download FavCircles</a> from the App Store.</li>
            <li>Create your account with <strong>this email address</strong> (${toEmail}).</li>
            <li>Add your first favorite place — <strong>25 FavCoins</strong> drop straight into your piggy bank. 🐷</li>
          </ol>
          <h2 style="font-size: 17px; margin-top: 24px;">Where your FavCoins live</h2>
          <p style="font-size: 15px; line-height: 1.6;">
            Tap the <strong>$</strong> button on the home screen to open your piggy bank.
            You'll watch coins drop in as you add places, connect with friends,
            share moments, and check in around town.
          </p>
          <h2 style="font-size: 17px; margin-top: 24px;">Make them yours on the blockchain</h2>
          <p style="font-size: 15px; line-height: 1.6;">
            In your piggy bank, tap the wallet row and FavCircles creates a
            <strong>Cactus blockchain wallet</strong> 🌵 for you in one tap (or link one you
            already have). Once your coins clear, claim them to your wallet —
            they land on-chain, verifiably yours.
            <a href="https://favcircles.com/cactus.html" style="color: #667eea;">How the Cactus blockchain works</a>.
          </p>
          <p style="font-size: 15px; line-height: 1.6; margin-top: 24px;">
            See you on the map!<br>— Wesley &amp; the FavCircles team
          </p>
        </div>`;

      const textContent = `Your FavCoins are waiting!

Thanks for your interest in FavCircles. FavCoins are rewards you earn for sharing the places you love — real coins on the Cactus blockchain that you can claim to your own wallet.

1. Download FavCircles: https://apps.apple.com/us/app/favcircles/id6746807095
2. Create your account with this email address (${toEmail}).
3. Add your first favorite place — 25 FavCoins drop straight into your piggy bank.

Where your FavCoins live: tap the $ button on the home screen to open your piggy bank. Coins drop in as you add places, connect with friends, share moments, and check in.

Make them yours: in your piggy bank, tap the wallet row and FavCircles creates a Cactus blockchain wallet for you in one tap (or link one you already have). Once your coins clear, claim them to your wallet — they're on-chain, verifiably yours. More: https://favcircles.com/cactus.html

See you on the map!
— Wesley & the FavCircles team`;

      await this.sendEmail({ to: toEmail, subject, html: htmlContent, text: textContent });
      console.log(`✅ Website lead email sent to ${toEmail}`);
      return { success: true };
    } catch (error) {
      console.error('❌ Error sending website lead email:', error);
      throw error;
    }
  }

  async sendWelcomeEmail(toEmail, name = null) {
    try {
      const greeting = name ? `Hi ${name},` : 'Hi there,';
      const subject = 'Welcome to Circles! 🎉 Here\'s how to get started';

      const htmlContent = `
        <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1a202c;">
          <h1 style="font-size: 22px;">Welcome to Circles! 🎉</h1>
          <p style="font-size: 15px; line-height: 1.6;">${greeting}</p>
          <p style="font-size: 15px; line-height: 1.6;">
            Circles is where you and your friends share the places you actually love —
            no strangers' reviews, just recommendations from people you trust.
          </p>
          <p style="font-size: 15px; line-height: 1.6;"><strong>Two quick things to do first:</strong></p>
          <ol style="font-size: 15px; line-height: 1.9; padding-left: 20px;">
            <li><strong>Add a few of your favorite places</strong> — tap "Add Your Places" on the home screen. Your go-to restaurant, coffee spot, anywhere you'd tell a friend about.</li>
            <li><strong>Find your friends</strong> — the more people you connect with, the more great places show up on your map.</li>
          </ol>
          <p style="font-size: 15px; line-height: 1.6;">
            That's it. Everything else — circles, the map, sharing — builds from there.
          </p>
          <p style="font-size: 15px; line-height: 1.6;">— Wesley &amp; the Circles team</p>
        </div>`;

      const textContent = `Welcome to Circles! 🎉

${greeting}

Circles is where you and your friends share the places you actually love — no strangers' reviews, just recommendations from people you trust.

Two quick things to do first:
1. Add a few of your favorite places — tap "Add Your Places" on the home screen.
2. Find your friends — the more people you connect with, the more great places show up on your map.

That's it. Everything else builds from there.

— Wesley & the Circles team`;

      await this.sendEmail({ to: toEmail, subject, html: htmlContent, text: textContent });
      console.log(`✅ Welcome email sent to ${toEmail}`);
      return { success: true };
    } catch (error) {
      console.error('❌ Error sending welcome email:', error);
      throw error;
    }
  }

  // Sent once on the premium signup transition (new sub or trial start) —
  // the moment they pay is the moment to show them everything they unlocked.
  async sendPremiumWelcomeEmail(toEmail, name = null, { isTrial = false } = {}) {
    try {
      const greeting = name ? `Hi ${name},` : 'Hi there,';
      const subject = isTrial
        ? 'Your FavCircles Premium trial has started 🎉'
        : 'Welcome to FavCircles Premium 🎉';
      const opener = isTrial
        ? 'Your free trial of FavCircles Premium is live — everything below is unlocked right now.'
        : 'Thanks for subscribing to FavCircles Premium — here\'s everything you just unlocked.';

      const htmlContent = `
        <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1a202c;">
          <h1 style="font-size: 22px;">${isTrial ? 'Your Premium trial has started 🎉' : 'Welcome to Premium 🎉'}</h1>
          <p style="font-size: 15px; line-height: 1.6;">${greeting}</p>
          <p style="font-size: 15px; line-height: 1.6;">${opener}</p>
          <ul style="font-size: 15px; line-height: 1.9; padding-left: 20px;">
            <li><strong>Unlimited circles and places</strong> — the free caps (6 circles, 15 places each) are gone. Build as big as your world is.</li>
            <li><strong>Import your places</strong> — bring everything over from Google Maps, Mapstr, or Swarm in one go (Profile → Settings → Import).</li>
            <li><strong>Export anytime</strong> — your places are yours; take a copy whenever you like.</li>
            <li><strong>Share without watermarks</strong> — circles you share look clean.</li>
            <li><strong>Circle Advisor</strong> — AI suggestions that help round out your circles with places you'll actually like.</li>
          </ul>
          <p style="font-size: 15px; line-height: 1.6;">
            A good first move: import your saved places from another app — a full map on day one makes everything else better.
          </p>
          <p style="font-size: 15px; line-height: 1.6;">— Wesley &amp; the FavCircles team</p>
        </div>`;

      const textContent = `${isTrial ? 'Your Premium trial has started 🎉' : 'Welcome to FavCircles Premium 🎉'}

${greeting}

${opener}

• Unlimited circles and places — the free caps (6 circles, 15 places each) are gone.
• Import your places — bring everything over from Google Maps, Mapstr, or Swarm (Profile → Settings → Import).
• Export anytime — your places are yours.
• Share without watermarks.
• Circle Advisor — AI suggestions for rounding out your circles.

A good first move: import your saved places from another app — a full map on day one makes everything else better.

— Wesley & the FavCircles team`;

      await this.sendEmail({ to: toEmail, subject, html: htmlContent, text: textContent });
      console.log(`✅ Premium welcome email sent to ${toEmail}`);
      return { success: true };
    } catch (error) {
      console.error('❌ Error sending premium welcome email:', error);
      throw error;
    }
  }

  // Sent once on the FavCircles Business signup transition — a store owner
  // just paid; walk them through turning that into foot traffic.
  async sendBusinessWelcomeEmail(toEmail, name = null, venueName = null, venue = null) {
    try {
      const greeting = name ? `Hi ${name},` : 'Hi there,';
      const forVenue = venueName ? ` for ${venueName}` : '';
      const subject = `Welcome to FavCircles Business${forVenue} 🏪`;

      // Ready-to-print loyalty assets (register card + table tent) ride along
      // when we know the venue — the loyalty program just activated, so the
      // thing customers scan should be one print away. Best-effort.
      const attachments = [];
      let printedNote = '';
      if (venue && venue.registerCode) {
        try {
          const printAssetService = require('./printAssetService');
          const [card, tent] = await Promise.all([
            printAssetService.registerCardPDF(venue),
            printAssetService.tableTentPDF(venue)
          ]);
          const safeName = (venue.venueName || 'venue').replace(/[^\w -]/g, '');
          attachments.push(
            { filename: `${safeName} - register card 4x6.pdf`, content: card },
            { filename: `${safeName} - table tent.pdf`, content: tent }
          );
          printedNote = `
          <p style="font-size: 15px; line-height: 1.6;">
            <strong>Attached and ready to print:</strong> your register card (4×6 — fits a standard
            photo stand) and a fold-in-half table tent, each with your store's unique rewards QR.
            Put one by the register today and customers start earning points on their next visit.
          </p>`;
        } catch (pdfError) {
          console.error('⚠️ Business welcome print PDFs failed (sending without):', pdfError.message);
        }
      }

      const htmlContent = `
        <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1a202c;">
          <h1 style="font-size: 22px;">Welcome to FavCircles Business 🏪</h1>
          <p style="font-size: 15px; line-height: 1.6;">${greeting}</p>
          <p style="font-size: 15px; line-height: 1.6;">
            Your Business subscription${forVenue} is active. Everything below is live now — all of it managed from your place page in the app (Profile → My Venues).
          </p>
          <ul style="font-size: 15px; line-height: 1.9; padding-left: 20px;">
            <li><strong>Your loyalty program is on</strong> — customers earn points scanning your window sticker and your register card, and you set how many points a purchase pays. Points earned at your store can only be spent at your store — never at a competitor.</li>
            <li><strong>Post offers</strong> — "Free coffee — 100 points" style rewards customers redeem with a short-lived voucher at your counter. You choose the offers and the prices.</li>
            <li><strong>Announcements</strong> — reach your followers' feeds and the app's Specials tab whenever you have news, an event, or a special.</li>
            <li><strong>Stats &amp; Insights</strong> — saves, followers, visits, scans, and redemptions, live on your dashboard, plus a monthly report by email.</li>
            <li><strong>Redemption codes</strong> — single-use codes to pack into orders or hand out at events; each one pays points when redeemed.</li>
          </ul>
          ${printedNote}
          <p style="font-size: 15px; line-height: 1.6;">
            A good first move: post one offer worth walking in for, and put the window sticker where people can see it. Reply to this email if you need stickers or help getting set up — happy to help personally.
          </p>
          <p style="font-size: 15px; line-height: 1.6;">— Wesley &amp; the FavCircles team</p>
        </div>`;

      const textContent = `Welcome to FavCircles Business 🏪

${greeting}

Your Business subscription${forVenue} is active. Everything below is live now — all managed from your place page in the app (Profile → My Venues).

• Your loyalty program is on — customers earn points scanning your window sticker and register card; you set how many points a purchase pays. Points earned at your store can only be spent at your store.
• Post offers — rewards customers redeem with a short-lived voucher at your counter.
• Announcements — reach your followers' feeds and the app's Specials tab.
• Stats & Insights — saves, followers, visits, scans, and redemptions, plus a monthly report by email.
• Redemption codes — single-use codes for orders or events.

A good first move: post one offer worth walking in for, and put the window sticker where people can see it. Reply to this email if you need stickers or help getting set up.

— Wesley & the FavCircles team`;

      await this.sendEmail({ to: toEmail, subject, html: htmlContent, text: textContent, attachments });
      console.log(`✅ Business welcome email sent to ${toEmail}${attachments.length ? ' (with print PDFs)' : ''}`);
      return { success: true };
    } catch (error) {
      console.error('❌ Error sending business welcome email:', error);
      throw error;
    }
  }

  // On-demand from the store-owner help section: everything needed to connect
  // ChatGPT or Claude to the FavCircles MCP server, in an email they can open
  // on their computer (the setup happens in the assistant's settings, not in
  // our app, so a durable reference beats in-app text).
  async sendAiSetupEmail(toEmail, name = null) {
    try {
      const greeting = name ? `Hi ${name},` : 'Hi there,';
      const subject = 'Manage your store with ChatGPT or Claude — setup guide 🤖';

      const starterPrompts = [
        'How is my store doing this month?',
        'Who are my regulars, and when are my busiest hours?',
        'Post an announcement: live music this Friday 7–9pm',
        'Create a reward: free smoothie for 250 points',
        'Update my store hours: open 7am–7pm weekdays, 8am–5pm weekends',
      ];

      const htmlContent = `
        <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1a202c;">
          <h1 style="font-size: 22px;">Manage your store with AI 🤖</h1>
          <p style="font-size: 15px; line-height: 1.6;">${greeting}</p>
          <p style="font-size: 15px; line-height: 1.6;">
            You can connect your FavCircles store to ChatGPT or Claude and manage it by just asking —
            stats, announcements, offers, store hours, loyalty codes, all of it. One-time setup, about two minutes.
          </p>

          <h2 style="font-size: 17px; margin-top: 24px;">Connect Claude (claude.ai)</h2>
          <ol style="font-size: 15px; line-height: 1.9; padding-left: 20px;">
            <li>Open <strong>claude.ai → Settings → Connectors</strong></li>
            <li>Click <strong>Add custom connector</strong></li>
            <li>Paste this URL: <code style="background:#f1f5f9;padding:2px 6px;border-radius:4px;">https://mcp.favcircles.com/mcp</code></li>
            <li>Sign in with your FavCircles email and password when asked</li>
          </ol>

          <h2 style="font-size: 17px; margin-top: 24px;">Connect ChatGPT</h2>
          <ol style="font-size: 15px; line-height: 1.9; padding-left: 20px;">
            <li>Open <strong>ChatGPT → Settings → Apps &amp; Connectors</strong> (turn on <em>Developer mode</em> under Advanced if you don't see an add option)</li>
            <li>Choose <strong>Create / Add connector</strong></li>
            <li>Name it <strong>FavCircles</strong> and paste the same URL: <code style="background:#f1f5f9;padding:2px 6px;border-radius:4px;">https://mcp.favcircles.com/mcp</code></li>
            <li>Sign in with your FavCircles email and password when asked</li>
          </ol>

          <p style="font-size: 13px; line-height: 1.6; color: #64748b;">
            Note: signing in requires a FavCircles password. If you normally sign in with Apple or Google,
            set a password first in the app (Profile → Settings).
          </p>

          <h2 style="font-size: 17px; margin-top: 24px;">Then just ask</h2>
          <ul style="font-size: 15px; line-height: 1.9; padding-left: 20px;">
            ${starterPrompts.map((p) => `<li>"${p}"</li>`).join('\n            ')}
          </ul>

          <p style="font-size: 15px; line-height: 1.6;">
            Full guide with screenshots: <a href="https://favcircles.com/connect-claude.html">favcircles.com/connect-claude.html</a>.
            Reply to this email if you get stuck — happy to help personally.
          </p>
          <p style="font-size: 15px; line-height: 1.6;">— Wesley &amp; the FavCircles team</p>
        </div>`;

      const textContent = `Manage your store with AI 🤖

${greeting}

Connect your FavCircles store to ChatGPT or Claude and manage it by just asking — stats, announcements, offers, store hours, loyalty codes. One-time setup, about two minutes.

CONNECT CLAUDE (claude.ai)
1. Open claude.ai → Settings → Connectors
2. Click "Add custom connector"
3. Paste this URL: https://mcp.favcircles.com/mcp
4. Sign in with your FavCircles email and password when asked

CONNECT CHATGPT
1. Open ChatGPT → Settings → Apps & Connectors (enable Developer mode under Advanced if needed)
2. Choose "Create / Add connector"
3. Name it FavCircles and paste the same URL: https://mcp.favcircles.com/mcp
4. Sign in with your FavCircles email and password when asked

Note: signing in requires a FavCircles password. If you normally sign in with Apple or Google, set a password first in the app (Profile → Settings).

THEN JUST ASK
${starterPrompts.map((p) => `• "${p}"`).join('\n')}

Full guide: https://favcircles.com/connect-claude.html
Reply to this email if you get stuck.

— Wesley & the FavCircles team`;

      await this.sendEmail({ to: toEmail, subject, html: htmlContent, text: textContent });
      console.log(`✅ AI setup email sent to ${toEmail}`);
      return { success: true };
    } catch (error) {
      console.error('❌ Error sending AI setup email:', error);
      throw error;
    }
  }

  // Sent when an ownership claim is approved — the push can be missed; this
  // is the durable "you now manage this business" record plus the pitch for
  // what Business unlocks.
  async sendClaimApprovedEmail(toEmail, name = null, businessName = null) {
    try {
      const greeting = name ? `Hi ${name},` : 'Hi there,';
      const business = businessName || 'your business';
      const subject = `You now manage ${business} on FavCircles ✅`;

      const htmlContent = `
        <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1a202c;">
          <h1 style="font-size: 22px;">Your claim was approved ✅</h1>
          <p style="font-size: 15px; line-height: 1.6;">${greeting}</p>
          <p style="font-size: 15px; line-height: 1.6;">
            You're verified as the owner of <strong>${business}</strong> on FavCircles. Your store now appears under <strong>Profile → My Venues</strong> in the app, and its place page shows you the owner tools.
          </p>
          <p style="font-size: 15px; line-height: 1.6;"><strong>What you can do right away (free):</strong></p>
          <ul style="font-size: 15px; line-height: 1.9; padding-left: 20px;">
            <li>Keep your business details accurate — your edits are the ones customers see</li>
            <li>Watch your Stats &amp; Insights — who's saving, following, and visiting</li>
          </ul>
          <p style="font-size: 15px; line-height: 1.6;"><strong>With a FavCircles Business subscription you also get:</strong></p>
          <ul style="font-size: 15px; line-height: 1.9; padding-left: 20px;">
            <li>A loyalty program at your counter — customers earn points with you that can only be spent at your store</li>
            <li>Offers customers redeem in person, at prices you set</li>
            <li>Announcements that reach your followers' feeds and the app's Specials tab</li>
          </ul>
          <p style="font-size: 15px; line-height: 1.6;">
            The upgrade lives on your place page in the app. Questions, or need a window sticker? Just reply to this email — happy to help personally.
          </p>
          <p style="font-size: 15px; line-height: 1.6;">— Wesley &amp; the FavCircles team</p>
        </div>`;

      const textContent = `Your claim was approved ✅

${greeting}

You're verified as the owner of ${business} on FavCircles. Your store now appears under Profile → My Venues in the app, and its place page shows you the owner tools.

What you can do right away (free):
• Keep your business details accurate — your edits are the ones customers see
• Watch your Stats & Insights — who's saving, following, and visiting

With a FavCircles Business subscription you also get:
• A loyalty program at your counter — customers earn points with you that can only be spent at your store
• Offers customers redeem in person, at prices you set
• Announcements that reach your followers' feeds and the app's Specials tab

The upgrade lives on your place page in the app. Questions, or need a window sticker? Just reply to this email.

— Wesley & the FavCircles team`;

      await this.sendEmail({ to: toEmail, subject, html: htmlContent, text: textContent });
      console.log(`✅ Claim-approved email sent to ${toEmail}`);
      return { success: true };
    } catch (error) {
      console.error('❌ Error sending claim-approved email:', error);
      throw error;
    }
  }

  async sendAppInvitation(toEmail, inviterName, recipientName = null, inviteLink = null) {
    try {
      // The connect link opens the app and auto-connects when installed,
      // otherwise it redirects to the App Store
      const joinUrl = inviteLink || 'https://apps.apple.com/us/app/favcircles/id6746807095';
      const subject = `${inviterName} invited you to join Circles`;

      const greeting = recipientName ? `Hi ${recipientName},` : 'Hi there,';
      
      const htmlContent = `
        <!DOCTYPE html>
        <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
              .container { max-width: 600px; margin: 0 auto; padding: 20px; }
              .header { background-color: #4A90E2; color: white; padding: 20px; text-align: center; border-radius: 10px 10px 0 0; }
              .content { background-color: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
              .button { display: inline-block; background-color: #4A90E2; color: white; padding: 14px 28px; text-decoration: none; border-radius: 5px; margin-top: 20px; font-weight: bold; }
              .features { background-color: white; padding: 20px; margin: 20px 0; border-radius: 5px; }
              .feature { margin: 15px 0; }
              .footer { margin-top: 30px; font-size: 12px; color: #666; text-align: center; }
            </style>
          </head>
          <body>
            <div class="container">
              <div class="header">
                <h1>You're invited to Circles! 🎉</h1>
              </div>
              <div class="content">
                <p>${greeting}</p>
                <p><strong>${inviterName}</strong> is using Circles to share their favorite places and wants you to join!</p>
                
                <div class="features">
                  <h3>With Circles, you can:</h3>
                  <div class="feature">📍 Create curated lists of your favorite restaurants, cafes, and shops</div>
                  <div class="feature">👥 Connect with friends to discover their go-to spots</div>
                  <div class="feature">🔒 Control who sees your recommendations with privacy settings</div>
                  <div class="feature">💬 Share suggestions and get personalized recommendations</div>
                </div>
                
                <p>Join ${inviterName} and start sharing the places you love!</p>
                
                <center>
                  <a href="${joinUrl}" class="button">Join Circles</a>
                </center>
                
                <p style="margin-top: 20px; font-size: 14px; color: #666;">
                  Tired of endless reviews? Trust yourself and your friends. Create a Circle and add your favorite places.
                </p>
              </div>
              <div class="footer">
                <p>This invitation was sent by ${inviterName} via Circles.</p>
                <p>&copy; ${new Date().getFullYear()} Circles. All rights reserved.</p>
              </div>
            </div>
          </body>
        </html>
      `;

      const textContent = `
You're invited to Circles! 🎉

${greeting}

${inviterName} is using Circles to share their favorite places and wants you to join!

With Circles, you can:
📍 Create curated lists of your favorite restaurants, cafes, and shops
👥 Connect with friends to discover their go-to spots
🔒 Control who sees your recommendations with privacy settings
💬 Share suggestions and get personalized recommendations

Join ${inviterName} and start sharing the places you love!

Join Circles: ${joinUrl}

Tired of endless reviews? Trust yourself and your friends. Create a Circle and add your favorite places.

This invitation was sent by ${inviterName} via Circles.
© ${new Date().getFullYear()} Circles. All rights reserved.
      `;

      // NOTE: sendEmail takes an options object — the old positional call
      // passed a string, destructured to `to: undefined`, and every email
      // invitation silently failed
      await this.sendEmail({ to: toEmail, subject, html: htmlContent, text: textContent });
      
      console.log(`✅ App invitation email sent to ${toEmail} from ${inviterName}`);
      return { success: true, message: 'Invitation email sent successfully' };
    } catch (error) {
      console.error('❌ Error sending app invitation email:', error);
      throw error;
    }
  }

  // Branded password reset email, sent from our own SMTP domain instead of
  // Firebase's default noreply@<project>.firebaseapp.com (which lands in spam)
  async sendPasswordResetEmail(toEmail, resetLink, displayName = null) {
    const subject = 'Reset your FavCircles password';
    const greeting = displayName ? `Hi ${displayName},` : 'Hi,';

    const html = `
      <div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:520px;margin:0 auto;padding:20px">
        <h2 style="color:#3182CE;margin-bottom:8px">Reset your password</h2>
        <p>${greeting}</p>
        <p>We received a request to reset the password for your FavCircles account
        (<strong>${toEmail}</strong>). Tap the button below to choose a new one:</p>
        <p style="text-align:center;margin:28px 0">
          <a href="${resetLink}"
             style="background:#3182CE;color:#fff;padding:14px 32px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">
            Reset Password
          </a>
        </p>
        <p style="color:#666;font-size:14px">This link expires in 1 hour. After resetting, you can sign in
        with your email and new password — and if you usually use Google or Apple sign-in, those still
        work too. It's all the same account.</p>
        <p style="color:#888;font-size:13px">Didn't request this? You can safely ignore this email —
        your password won't change.</p>
        <hr style="border:none;border-top:1px solid #eee;margin:24px 0">
        <p style="color:#aaa;font-size:12px">FavCircles · Save the places you love</p>
      </div>`;

    const text = `${greeting}

We received a request to reset the password for your FavCircles account (${toEmail}).

Reset it here (link expires in 1 hour):
${resetLink}

If you didn't request this, you can safely ignore this email — your password won't change.

FavCircles · Save the places you love`;

    return this.sendEmail({ to: toEmail, subject, html, text });
  }

  // Sticker QR codes for a newly created venue, sent to the super user for printing
  async sendStickerQREmail(toEmail, venue, windowQRBuffer, registerQRBuffer) {
    if (!this.transporter || !this.transporter.sendMail) {
      throw new Error('Email service not configured');
    }

    const subject = `Sticker QR codes for ${venue.venueName} — ready to print`;
    const html = `
      <div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:520px;margin:0 auto">
        <h2 style="color:#3182CE">QR codes for ${venue.venueName}</h2>
        <p><strong>Print either attachment on plain paper — that's it:</strong></p>
        <table style="border-collapse:collapse;width:100%;background:#fafafa;border-radius:8px">
          <tr>
            <td style="padding:10px 16px;border-bottom:1px solid #eee"><strong>Register card (4×6)</strong><br>
            Fits a standard photo frame or acrylic stand by the register.</td>
          </tr>
          <tr>
            <td style="padding:10px 16px"><strong>Table tent</strong><br>
            Print, fold in half along the dashed line — it stands on its own.</td>
          </tr>
        </table>
        <p style="margin-top:16px">Customers scan it to earn points on every visit
        (code: <code>${venue.registerCode}</code>).</p>
        <p style="color:#888;font-size:13px">Verify before you're done: scan the printed QR from a
        logged-in FavCircles account and check the points land. Reply to this email if you'd like
        the raw QR image for custom artwork.</p>
      </div>`;

    // Ready-to-print register assets — best-effort so a PDF glitch never
    // blocks the raw QR delivery
    const printAttachments = [];
    try {
      const printAssetService = require('./printAssetService');
      const [card, tent] = await Promise.all([
        printAssetService.registerCardPDF(venue),
        printAssetService.tableTentPDF(venue)
      ]);
      printAttachments.push(
        { filename: `${venue.venueName.replace(/[^\w -]/g, '')} - register card 4x6.pdf`, content: card },
        { filename: `${venue.venueName.replace(/[^\w -]/g, '')} - table tent.pdf`, content: tent }
      );
    } catch (pdfError) {
      console.error('⚠️ Print PDF generation failed (sending raw QRs only):', pdfError.message);
    }

    const mailOptions = {
      from: `"${this.fromName}" <${this.fromAddress}>`,
      to: toEmail,
      subject,
      html,
      text: `Rewards QR for ${venue.venueName} (register code: ${venue.registerCode}). Ready-to-print register card + table tent PDFs attached — print either on plain paper and put it by the register.`,
      // The raw QR PNGs used to ride along too, but mail apps render them
      // inline as two giant bare QR codes (confusing next to the finished
      // PDFs). The PDFs carry the register QR; raw assets on request. If PDF
      // generation failed, fall back to the raw register PNG so the owner is
      // never left with nothing.
      attachments: printAttachments.length > 0
        ? printAttachments
        : [{ filename: `register-${venue.registerCode}.png`, content: registerQRBuffer }]
    };

    const result = await this.transporter.sendMail(mailOptions);
    console.log(`✅ Sticker QR email sent to ${toEmail} for ${venue.venueName}`);
    return { success: true, messageId: result.messageId };
  }

  // Monthly performance report for a sticker-program venue
  async sendVenueReportEmail(venue, monthKey, stats) {
    const safeStats = {
      scans: stats?.scans || 0,
      signups: stats?.signups || 0,
      saves: stats?.saves || 0,
      visits: stats?.visits || 0,
      redemptions: stats?.redemptions || 0
    };

    const subject = `Your FavCircles sticker results for ${monthKey} — ${venue.venueName}`;

    const row = (label, value) => `
      <tr>
        <td style="padding:10px 16px;border-bottom:1px solid #eee;color:#444">${label}</td>
        <td style="padding:10px 16px;border-bottom:1px solid #eee;text-align:right;font-weight:600;color:#111">${value}</td>
      </tr>`;

    const html = `
      <div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:520px;margin:0 auto">
        <h2 style="color:#3182CE">FavCircles Sticker Report — ${monthKey}</h2>
        <p>Hi${venue.contactName ? ' ' + venue.contactName : ''},</p>
        <p>Here's how the FavCircles sticker at <strong>${venue.venueName}</strong> performed last month:</p>
        <table style="border-collapse:collapse;width:100%;background:#fafafa;border-radius:8px">
          ${row('QR scans', safeStats.scans)}
          ${row('New app signups from your sticker', safeStats.signups)}
          ${row('People who saved your place', safeStats.saves)}
          ${row('Verified repeat visits', safeStats.visits)}
          ${row('Rewards redeemed at your counter', safeStats.redemptions)}
        </table>
        <p style="margin-top:16px">Every save means a customer who won't forget you — and every reward
        redemption is a customer who came back. Thanks for being part of FavCircles!</p>
        <p style="color:#888;font-size:13px">Questions or want to change your offers? Just reply to this email.</p>
      </div>`;

    const text = `FavCircles Sticker Report ${monthKey} — ${venue.venueName}
QR scans: ${safeStats.scans}
New signups: ${safeStats.signups}
Place saves: ${safeStats.saves}
Verified repeat visits: ${safeStats.visits}
Rewards redeemed: ${safeStats.redemptions}`;

    return this.sendEmail({ to: venue.contactEmail, subject, html, text });
  }

  // Generic email sending method
  async sendEmail({ to, subject, html, text, attachments }) {
    try {
      // Check if transporter is configured
      if (!this.transporter || !this.transporter.sendMail) {
        console.error('❌ Email transporter not configured. Check EMAIL_SERVICE, GMAIL_USER, and GMAIL_APP_PASSWORD environment variables.');
        throw new Error('Email service not configured');
      }

      const mailOptions = {
        from: `"${this.fromName}" <${this.fromAddress}>`,
        to: to,
        subject: subject,
        html: html,
        text: text || subject, // Fallback text if not provided
        ...(attachments && attachments.length ? { attachments } : {})
      };

      console.log(`📧 Attempting to send email to ${to} with subject: ${subject}`);
      const result = await this.transporter.sendMail(mailOptions);
      console.log(`✅ Email sent successfully to ${to}: ${subject} (Message ID: ${result.messageId})`);
      return { success: true, messageId: result.messageId };
    } catch (error) {
      console.error(`❌ Error sending email to ${to}:`, error.message);
      console.error('Full error:', error);
      
      // Provide helpful error messages
      if (error.message.includes('self signed certificate')) {
        console.error('⚠️  TLS certificate issue. You may need to set NODE_TLS_REJECT_UNAUTHORIZED=0 for development.');
      } else if (error.message.includes('Invalid login')) {
        console.error('⚠️  Gmail authentication failed. Make sure you are using an App Password, not your regular password.');
        console.error('⚠️  Create an App Password at: https://myaccount.google.com/apppasswords');
      }
      
      throw error;
    }
  }
}

module.exports = new EmailService();