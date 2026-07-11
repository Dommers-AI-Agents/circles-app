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
        <p>Both codes are attached at print resolution (1200px ≈ 4in at 300dpi).</p>
        <table style="border-collapse:collapse;width:100%;background:#fafafa;border-radius:8px">
          <tr>
            <td style="padding:10px 16px;border-bottom:1px solid #eee"><strong>Window sticker</strong><br>
            Goes in the front window. Code: <code>${venue.windowCode}</code></td>
          </tr>
          <tr>
            <td style="padding:10px 16px"><strong>Register card</strong><br>
            Stays behind the counter, shown with a purchase. Code: <code>${venue.registerCode}</code></td>
          </tr>
        </table>
        <p style="margin-top:16px"><strong>Print tips:</strong> keep the white margin around each QR,
        print at least 1.5×1.5 in, use weatherproof vinyl for the window (front-adhesive for
        inside-glass mounting) and a laminated card for the register.</p>
        <p style="color:#888;font-size:13px">Verify on-site before leaving: scan the window QR with the
        iPhone Camera, and the register QR from a logged-in account.</p>
      </div>`;

    const mailOptions = {
      from: `"${this.fromName}" <${this.fromAddress}>`,
      to: toEmail,
      subject,
      html,
      text: `QR codes for ${venue.venueName}. Window code: ${venue.windowCode}. Register code: ${venue.registerCode}. Print-resolution PNGs attached.`,
      attachments: [
        { filename: `window-${venue.windowCode}.png`, content: windowQRBuffer },
        { filename: `register-${venue.registerCode}.png`, content: registerQRBuffer }
      ]
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
  async sendEmail({ to, subject, html, text }) {
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
        text: text || subject // Fallback text if not provided
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