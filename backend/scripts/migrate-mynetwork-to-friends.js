#!/usr/bin/env node

/**
 * Rollback migration script to revert 'myNetwork' privacy back to 'friends'
 * Use this only if you need to rollback the network sharing feature
 */

require('dotenv').config();
const mongoose = require('mongoose');
const Circle = require('../models/Circle');
const Place = require('../models/Place');

async function rollback() {
  try {
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/circles', {
      useNewUrlParser: true,
      useUnifiedTopology: true
    });

    console.log('Connected to MongoDB');

    // Rollback circles
    console.log('\nRolling back circles...');
    const circleResult = await Circle.updateMany(
      { privacy: 'myNetwork' },
      { $set: { privacy: 'friends' } }
    );
    console.log(`Reverted ${circleResult.modifiedCount} circles from 'myNetwork' to 'friends' privacy`);

    // Note: We don't remove allowNetworkEdit field to preserve data integrity
    console.log('Note: allowNetworkEdit field preserved for data integrity');

    // Rollback places
    console.log('\nRolling back places...');
    const placeResult = await Place.updateMany(
      { privacy: 'myNetwork' },
      { $set: { privacy: 'friends' } }
    );
    console.log(`Reverted ${placeResult.modifiedCount} places from 'myNetwork' to 'friends' privacy`);

    // Get counts for verification
    const totalCircles = await Circle.countDocuments();
    const friendsCircles = await Circle.countDocuments({ privacy: 'friends' });
    const totalPlaces = await Place.countDocuments();
    const friendsPlaces = await Place.countDocuments({ privacy: 'friends' });

    console.log('\nRollback Summary:');
    console.log(`Total circles: ${totalCircles} (${friendsCircles} with friends privacy)`);
    console.log(`Total places: ${totalPlaces} (${friendsPlaces} with friends privacy)`);

    // Check for any remaining 'myNetwork' privacy
    const remainingMyNetworkCircles = await Circle.countDocuments({ privacy: 'myNetwork' });
    const remainingMyNetworkPlaces = await Place.countDocuments({ privacy: 'myNetwork' });

    if (remainingMyNetworkCircles > 0 || remainingMyNetworkPlaces > 0) {
      console.warn('\n⚠️  Warning: Some documents still have "myNetwork" privacy:');
      console.warn(`  - Circles: ${remainingMyNetworkCircles}`);
      console.warn(`  - Places: ${remainingMyNetworkPlaces}`);
    } else {
      console.log('\n✅ Rollback completed successfully!');
    }

  } catch (error) {
    console.error('Rollback failed:', error);
    process.exit(1);
  } finally {
    await mongoose.disconnect();
    console.log('\nDisconnected from MongoDB');
  }
}

// Run rollback
if (require.main === module) {
  console.log('Starting rollback: myNetwork -> friends');
  console.log('Database:', process.env.MONGODB_URI || 'mongodb://localhost:27017/circles');
  console.log('---');
  
  // Add confirmation prompt for safety
  const readline = require('readline');
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  rl.question('\n⚠️  This will rollback the network sharing migration. Are you sure? (yes/no): ', (answer) => {
    rl.close();
    
    if (answer.toLowerCase() === 'yes') {
      rollback()
        .then(() => process.exit(0))
        .catch(err => {
          console.error(err);
          process.exit(1);
        });
    } else {
      console.log('Rollback cancelled.');
      process.exit(0);
    }
  });
}

module.exports = rollback;