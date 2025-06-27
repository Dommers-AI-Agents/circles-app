#!/usr/bin/env node

/**
 * Migration script to update 'friends' privacy to 'myNetwork' in the database
 * Run this before deploying the network sharing feature
 */

require('dotenv').config();
const mongoose = require('mongoose');
const Circle = require('../models/Circle');
const Place = require('../models/Place');

async function migrate() {
  try {
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/circles', {
      useNewUrlParser: true,
      useUnifiedTopology: true
    });

    console.log('Connected to MongoDB');

    // Migrate circles
    console.log('\nMigrating circles...');
    const circleResult = await Circle.updateMany(
      { privacy: 'friends' },
      { $set: { privacy: 'myNetwork' } }
    );
    console.log(`Updated ${circleResult.modifiedCount} circles from 'friends' to 'myNetwork' privacy`);

    // Add allowNetworkEdit field to existing circles (default to false)
    const circleFieldResult = await Circle.updateMany(
      { allowNetworkEdit: { $exists: false } },
      { $set: { allowNetworkEdit: false } }
    );
    console.log(`Added allowNetworkEdit field to ${circleFieldResult.modifiedCount} circles`);

    // Migrate places
    console.log('\nMigrating places...');
    const placeResult = await Place.updateMany(
      { privacy: 'friends' },
      { $set: { privacy: 'myNetwork' } }
    );
    console.log(`Updated ${placeResult.modifiedCount} places from 'friends' to 'myNetwork' privacy`);

    // Get counts for verification
    const totalCircles = await Circle.countDocuments();
    const myNetworkCircles = await Circle.countDocuments({ privacy: 'myNetwork' });
    const totalPlaces = await Place.countDocuments();
    const myNetworkPlaces = await Place.countDocuments({ privacy: 'myNetwork' });

    console.log('\nMigration Summary:');
    console.log(`Total circles: ${totalCircles} (${myNetworkCircles} with myNetwork privacy)`);
    console.log(`Total places: ${totalPlaces} (${myNetworkPlaces} with myNetwork privacy)`);

    // Check for any remaining 'friends' privacy
    const remainingFriendsCircles = await Circle.countDocuments({ privacy: 'friends' });
    const remainingFriendsPlaces = await Place.countDocuments({ privacy: 'friends' });

    if (remainingFriendsCircles > 0 || remainingFriendsPlaces > 0) {
      console.warn('\n⚠️  Warning: Some documents still have "friends" privacy:');
      console.warn(`  - Circles: ${remainingFriendsCircles}`);
      console.warn(`  - Places: ${remainingFriendsPlaces}`);
    } else {
      console.log('\n✅ Migration completed successfully!');
    }

  } catch (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  } finally {
    await mongoose.disconnect();
    console.log('\nDisconnected from MongoDB');
  }
}

// Run migration
if (require.main === module) {
  console.log('Starting migration: friends -> myNetwork');
  console.log('Database:', process.env.MONGODB_URI || 'mongodb://localhost:27017/circles');
  console.log('---');

  migrate()
    .then(() => process.exit(0))
    .catch(err => {
      console.error(err);
      process.exit(1);
    });
}

module.exports = migrate;