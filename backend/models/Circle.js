// backend/models/Circle.js
const mongoose = require('mongoose');

const CircleSchema = new mongoose.Schema({
  name: {
    type: String,
    required: [true, 'Please provide a name for the circle'],
    trim: true,
    maxlength: [50, 'Name can not be more than 50 characters']
  },
  description: {
    type: String,
    maxlength: [500, 'Description can not be more than 500 characters']
  },
  coverImage: {
    type: String,
    default: ''
  },
  owner: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  places: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Place'
  }],
  privacy: {
    type: String,
    enum: ['public', 'friends', 'private'],
    default: 'friends'
  },
  category: {
    type: String,
    enum: ['travel', 'food', 'services', 'shopping', 'healthcare', 'entertainment', 'other'],
    default: 'other'
  },
  location: {
    type: String,
    default: ''
  },
  tags: [{
    type: String
  }],
  sharedWith: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  followers: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Update the updatedAt field before save
CircleSchema.pre('save', function(next) {
  this.updatedAt = Date.now();
  next();
});

module.exports = mongoose.model('Circle', CircleSchema);