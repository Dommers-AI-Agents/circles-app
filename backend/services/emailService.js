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
                  <a href="${process.env.APP_URL || 'https://circles-app.com'}/connections" class="button">View Request</a>
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
                  <a href="${process.env.APP_URL || 'https://circles-app.com'}/network" class="button">View Connection</a>
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

  async sendAppInvitation(toEmail, inviterName, recipientName = null) {
    try {
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
                  <a href="${process.env.APP_URL || 'https://circles-app.com'}/join?referrer=${encodeURIComponent(inviterName)}" class="button">Join Circles</a>
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

Join Circles: ${process.env.APP_URL || 'https://circles-app.com'}/join?referrer=${encodeURIComponent(inviterName)}

Tired of endless reviews? Trust yourself and your friends. Create a Circle and add your favorite places.

This invitation was sent by ${inviterName} via Circles.
© ${new Date().getFullYear()} Circles. All rights reserved.
      `;

      await this.sendEmail(toEmail, subject, textContent, htmlContent);
      
      console.log(`✅ App invitation email sent to ${toEmail} from ${inviterName}`);
      return { success: true, message: 'Invitation email sent successfully' };
    } catch (error) {
      console.error('❌ Error sending app invitation email:', error);
      throw error;
    }
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