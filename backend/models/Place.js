// backend/models/Place.js
const mongoose = require('mongoose');

const PlaceSchema = new mongoose.Schema({
  name: {
    type: String,
    required: [true, 'Please provide a name for the place'],
    trim: true,
    maxlength: [100, 'Name can not be more than 100 characters']
  },
  description: {
    type: String,
    maxlength: [1000, 'Description can not be more than 1000 characters']
  },
  address: String,
  location: {
    type: {
      type: String,
      enum: ['Point'],
      default: 'Point'
    },
    coordinates: {
      type: [Number],
      index: '2dsphere'
    }
  },
  googlePlaceId: {
    type: String,
    sparse: true
  },
  photos: [{
    type: String
  }],
  category: {
    type: String,
    enum: ['restaurant', 'cafe', 'bar', 'hotel', 'retail', 'service', 'attraction', 'entertainment', 'healthcare', 'fitness', 'education', 'outdoor', 'transport', 'finance', 'other'],
    default: 'other'
  },
  customCategory: {
    type: String,
    maxlength: [50, 'Custom category can not be more than 50 characters'],
    trim: true
  },
  rating: {
    type: Number,
    min: 1,
    max: 5
  },
  userRatingsTotal: {
    type: Number,
    default: 0
  },
  priceLevel: {
    type: String,
    enum: ['free', 'inexpensive', 'moderate', 'expensive', 'veryExpensive']
  },
  notes: {
    type: String,
    maxlength: [500, 'Notes can not be more than 500 characters']
  },
  tags: [{
    type: String
  }],
  privacy: {
    type: String,
    enum: ['public', 'myNetwork', 'private', 'followCircle'],
    default: 'followCircle'
  },
  addedBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  circles: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Circle'
  }],
  visits: [{
    date: Date,
    notes: String
  }],
  website: String,
  phone: String,
  openingHours: [{
    day: Number,
    open: String,
    close: String
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
PlaceSchema.pre('save', function(next) {
  this.updatedAt = Date.now();
  next();
});

module.exports = mongoose.model('Place', PlaceSchema);
