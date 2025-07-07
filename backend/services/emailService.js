// backend/services/emailService.js
const nodemailer = require('nodemailer');

class EmailService {
  constructor() {
    // Configure email transporter
    // For production, you should use a service like SendGrid, AWS SES, etc.
    // This example uses Gmail SMTP
    
    // Check if Gmail credentials are configured
    if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
      console.warn('⚠️ Gmail credentials not configured. Email service will not work.');
      console.warn('⚠️ Set GMAIL_USER and GMAIL_APP_PASSWORD environment variables.');
      console.warn('⚠️ Note: You must use an App Password, not your regular Gmail password.');
      console.warn('⚠️ Create an App Password at: https://myaccount.google.com/apppasswords');
      
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

    // For production, you might want to use SendGrid instead:
    // const sgMail = require('@sendgrid/mail');
    // sgMail.setApiKey(process.env.SENDGRID_API_KEY);
  }

  async sendConnectionRequestEmail(toEmail, fromUserName, fromUserId) {
    try {
      const mailOptions = {
        from: `"Circles App" <${process.env.GMAIL_USER}>`,
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
        from: `"Circles App" <${process.env.GMAIL_USER}>`,
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
}

module.exports = new EmailService();