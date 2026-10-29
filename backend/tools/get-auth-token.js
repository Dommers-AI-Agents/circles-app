#!/usr/bin/env node

// Script to get auth token for API testing
const https = require('https');
const readline = require('readline');

const API_BASE_URL = 'https://circles-backend-196924649787.us-central1.run.app';

// Create readline interface for password input
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

function askQuestion(question) {
  return new Promise((resolve) => {
    rl.question(question, resolve);
  });
}

function hidePassword() {
  return new Promise((resolve) => {
    const stdin = process.stdin;
    const stdout = process.stdout;
    
    stdout.write('Password: ');
    
    stdin.setRawMode(true);
    stdin.resume();
    stdin.setEncoding('utf8');
    
    let password = '';
    
    stdin.on('data', (ch) => {
      ch = ch.toString('utf8');
      
      switch (ch) {
        case '\n':
        case '\r':
        case '\u0004':
          stdin.setRawMode(false);
          stdin.pause();
          stdout.write('\n');
          resolve(password);
          break;
        case '\u0003':
          process.exit();
          break;
        case '\u007f':
        case '\b':
          if (password.length > 0) {
            password = password.slice(0, -1);
          }
          break;
        default:
          password += ch;
          break;
      }
    });
  });
}

async function login(email, password) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({ email, password });
    
    const options = {
      hostname: 'circles-backend-196924649787.us-central1.run.app',
      path: '/api/auth/login',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length
      }
    };
    
    const req = https.request(options, (res) => {
      let responseData = '';
      
      res.on('data', (chunk) => {
        responseData += chunk;
      });
      
      res.on('end', () => {
        try {
          const response = JSON.parse(responseData);
          if (response.success) {
            resolve(response);
          } else {
            reject(new Error(response.message || 'Login failed'));
          }
        } catch (error) {
          reject(error);
        }
      });
    });
    
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function testEmail(token, toEmail) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({ toEmail });
    
    const options = {
      hostname: 'circles-backend-196924649787.us-central1.run.app',
      path: '/api/email/test-send',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': data.length,
        'Authorization': `Bearer ${token}`
      }
    };
    
    const req = https.request(options, (res) => {
      let responseData = '';
      
      res.on('data', (chunk) => {
        responseData += chunk;
      });
      
      res.on('end', () => {
        try {
          const response = JSON.parse(responseData);
          resolve(response);
        } catch (error) {
          reject(error);
        }
      });
    });
    
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function main() {
  console.log('=== Circles App Auth Token Tool ===\n');
  
  try {
    // Get email
    const email = await askQuestion('Email: ');
    
    // Get password (hidden)
    const password = await hidePassword();
    
    console.log('\nLogging in...');
    
    // Login
    const loginResponse = await login(email, password);
    
    console.log('\n✅ Login successful!');
    console.log(`\nUser: ${loginResponse.user.displayName || loginResponse.user.email}`);
    console.log(`User ID: ${loginResponse.user.id}`);
    console.log('\n📋 Auth Token:');
    console.log('─'.repeat(80));
    console.log(loginResponse.token);
    console.log('─'.repeat(80));
    
    // Ask if they want to test email
    const testEmailAnswer = await askQuestion('\nWould you like to send a test email? (y/n): ');
    
    if (testEmailAnswer.toLowerCase() === 'y') {
      const recipientEmail = await askQuestion('Recipient email (or press Enter for your email): ');
      const toEmail = recipientEmail || email;
      
      console.log(`\nSending test email to ${toEmail}...`);
      
      const emailResponse = await testEmail(loginResponse.token, toEmail);
      
      if (emailResponse.success) {
        console.log('✅ Test email sent successfully!');
        console.log(`Message ID: ${emailResponse.messageId}`);
      } else {
        console.log('❌ Failed to send test email:', emailResponse.message);
      }
    }
    
    console.log('\n💡 To use this token with curl:');
    console.log(`curl -X POST ${API_BASE_URL}/api/email/test-send \\`);
    console.log('  -H "Content-Type: application/json" \\');
    console.log(`  -H "Authorization: Bearer ${loginResponse.token}" \\`);
    console.log('  -d \'{"toEmail": "sgroiwes@gmail.com"}\'');
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
  } finally {
    rl.close();
  }
}

// Run the script
main();