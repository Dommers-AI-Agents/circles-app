#!/usr/bin/env node

/**
 * Compare Wesley and Brittany's tokens
 */

require('dotenv').config();
const { initializeFirebase, getFirestore } = require('./config/firebase');

async function compareTokens() {
  try {
    initializeFirebase();
    const db = getFirestore();
    
    console.log('🔍 Comparing Device Tokens\n');
    console.log('=' .repeat(60));
    
    // Get Wesley's data
    const wesleySnapshot = await db.collection('users')
      .where('email', '==', 'sgroiwes@gmail.com')
      .limit(1)
      .get();
      
    // Get Brittany's data
    const brittanySnapshot = await db.collection('users')
      .where('email', '==', 'brittanyvans@gmail.com')
      .limit(1)
      .get();
    
    if (!wesleySnapshot.empty && !brittanySnapshot.empty) {
      const wesley = wesleySnapshot.docs[0].data();
      const brittany = brittanySnapshot.docs[0].data();
      
      console.log('WESLEY (sgroiwes@gmail.com):');
      console.log('----------------------------');
      if (wesley.deviceTokens && wesley.deviceTokens.length > 0) {
        wesley.deviceTokens.forEach((token, i) => {
          console.log(`Token ${i + 1}:`);
          console.log(`  Platform: ${token.platform}`);
          console.log(`  Token prefix: ${token.token.substring(0, 30)}...`);
          console.log(`  Created: ${token.createdAt || 'Not tracked'}`);
          console.log(`  Updated: ${token.updatedAt || 'Not tracked'}`);
          
          if (token.updatedAt) {
            const updated = new Date(token.updatedAt);
            const ageInHours = Math.floor((Date.now() - updated.getTime()) / (1000 * 60 * 60));
            console.log(`  Age: ${ageInHours} hours`);
          }
          
          // Check token format
          const tokenParts = token.token.split(':');
          console.log(`  Format: ${tokenParts.length} parts`);
          if (tokenParts.length === 2) {
            console.log(`  Instance ID: ${tokenParts[0].substring(0, 20)}...`);
            console.log(`  FCM Token: ${tokenParts[1].substring(0, 10)}...`);
          }
        });
      } else {
        console.log('  No tokens');
      }
      
      console.log('\n');
      console.log('BRITTANY (brittanyvans@gmail.com):');
      console.log('-----------------------------------');
      if (brittany.deviceTokens && brittany.deviceTokens.length > 0) {
        brittany.deviceTokens.forEach((token, i) => {
          console.log(`Token ${i + 1}:`);
          console.log(`  Platform: ${token.platform}`);
          console.log(`  Token prefix: ${token.token.substring(0, 30)}...`);
          console.log(`  Created: ${token.createdAt || 'Not tracked'}`);
          console.log(`  Updated: ${token.updatedAt || 'Not tracked'}`);
          
          if (token.updatedAt) {
            const updated = new Date(token.updatedAt);
            const ageInHours = Math.floor((Date.now() - updated.getTime()) / (1000 * 60 * 60));
            console.log(`  Age: ${ageInHours} hours`);
          }
          
          // Check token format
          const tokenParts = token.token.split(':');
          console.log(`  Format: ${tokenParts.length} parts`);
          if (tokenParts.length === 2) {
            console.log(`  Instance ID: ${tokenParts[0].substring(0, 20)}...`);
            console.log(`  FCM Token: ${tokenParts[1].substring(0, 10)}...`);
          }
        });
      } else {
        console.log('  No tokens');
      }
      
      console.log('\n' + '=' .repeat(60));
      console.log('\n📊 ANALYSIS:');
      console.log('-----------');
      
      // Compare token ages
      if (wesley.deviceTokens?.length > 0 && brittany.deviceTokens?.length > 0) {
        const wesleyToken = wesley.deviceTokens[0];
        const brittanyToken = brittany.deviceTokens[0];
        
        if (wesleyToken.updatedAt && brittanyToken.updatedAt) {
          const wesleyAge = Math.floor((Date.now() - new Date(wesleyToken.updatedAt).getTime()) / (1000 * 60 * 60));
          const brittanyAge = Math.floor((Date.now() - new Date(brittanyToken.updatedAt).getTime()) / (1000 * 60 * 60));
          
          console.log(`Wesley's token age: ${wesleyAge} hours`);
          console.log(`Brittany's token age: ${brittanyAge} hours`);
          
          if (wesleyAge < 24 && brittanyAge > 24) {
            console.log('\n⚠️  Wesley\'s token is newer but failing');
            console.log('   This might indicate:');
            console.log('   - Development vs Production build mismatch');
            console.log('   - Different provisioning profile');
            console.log('   - Debug vs Release configuration');
          }
        }
        
        // Compare token formats
        const wesleyParts = wesleyToken.token.split(':');
        const brittanyParts = brittanyToken.token.split(':');
        
        if (wesleyParts[0].length !== brittanyParts[0].length) {
          console.log('\n⚠️  Token format difference detected');
          console.log(`   Wesley's instance ID length: ${wesleyParts[0].length}`);
          console.log(`   Brittany's instance ID length: ${brittanyParts[0].length}`);
        }
      }
    }
    
  } catch (error) {
    console.error('Error:', error);
  }
}

compareTokens().then(() => {
  process.exit(0);
});