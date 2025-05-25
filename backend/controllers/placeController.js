// backend/controllers/placeController.js
const Place = require('../models/Place');
const Circle = require('../models/Circle');
const { Client } = require('@googlemaps/google-maps-services-js');
const { googleMapsApiKey } = require('../config/config');
const { storage } = require('../config/firebase');

const googleMapsClient = new Client({});

// @desc    Get all places for current user
// @route   GET /api/places
// @access  Private
exports.getMyPlaces = async (req, res, next) => {
  try {
    const places = await Place.find({ addedBy: req.user.id })
      .populate('circles', 'name privacy')
      .sort('-createdAt');

    res.status(200).json({
      success: true,
      count: places.length,
      data: places
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Get single place
// @route   GET /api/places/:id
// @access  Private
exports.getPlace = async (req, res, next) => {
  try {
    const place = await Place.findById(req.params.id)
      .populate('addedBy', 'displayName profilePicture')
      .populate('circles', 'name privacy owner');

    if (!place) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    // Check permissions
    const isOwner = place.addedBy._id.toString() === req.user.id;
    const isPublic = place.privacy === 'public';
    const isFriend = req.user.friends.includes(place.addedBy._id.toString()) && place.privacy === 'friends';
    
    // Check if place is in a circle shared with the user
    let isInSharedCircle = false;
    for (const circle of place.circles) {
      const fullCircle = await Circle.findById(circle._id);
      if (fullCircle.sharedWith.includes(req.user.id) || 
          (fullCircle.privacy === 'public') || 
          (fullCircle.privacy === 'friends' && req.user.friends.includes(fullCircle.owner.toString()))) {
        isInSharedCircle = true;
        break;
      }
    }

    if (!isOwner && !isPublic && !isFriend && !isInSharedCircle) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view this place'
      });
    }

    res.status(200).json({
      success: true,
      data: place
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Create new place
// @route   POST /api/places
// @access  Private
exports.createPlace = async (req, res, next) => {
  try {
    // Add user to request body
    req.body.addedBy = req.user.id;
    
    // Handle Google Place ID lookup if provided
    if (req.body.googlePlaceId && !req.body.location) {
      try {
        const response = await googleMapsClient.placeDetails({
          params: {
            place_id: req.body.googlePlaceId,
            key: googleMapsApiKey,
            fields: ['name', 'formatted_address', 'geometry', 'photos', 'website', 'formatted_phone_number', 'opening_hours', 'types']
          }
        });
        
        const placeDetails = response.data.result;
        
        // Enhance the request body with Google data
        req.body.name = req.body.name || placeDetails.name;
        req.body.address = {
          formattedAddress: placeDetails.formatted_address
        };
        req.body.location = {
          type: 'Point',
          coordinates: [
            placeDetails.geometry.location.lng,
            placeDetails.geometry.location.lat
          ]
        };
        req.body.website = placeDetails.website;
        req.body.phone = placeDetails.formatted_phone_number;
        
        // Determine category based on types
        if (placeDetails.types) {
          if (placeDetails.types.includes('restaurant')) {
            req.body.category = 'restaurant';
          } else if (placeDetails.types.includes('cafe')) {
            req.body.category = 'cafe';
          } else if (placeDetails.types.includes('lodging')) {
            req.body.category = 'hotel';
          } else if (placeDetails.types.includes('store') || placeDetails.types.includes('shopping_mall')) {
            req.body.category = 'store';
          } else if (placeDetails.types.includes('tourist_attraction') || placeDetails.types.includes('museum')) {
            req.body.category = 'attraction';
          } else if (placeDetails.types.includes('health')) {
            req.body.category = 'healthcare';
          }
        }
      } catch (error) {
        console.error('Error fetching place details:', error);
        // Continue with user-provided data if Google lookup fails
      }
    }
    
    // Add to circle if circleId is provided
    const { circleId, ...placeData } = req.body;
    
    const place = await Place.create(placeData);
    
    if (circleId) {
      const circle = await Circle.findById(circleId);
      
      if (circle && circle.owner.toString() === req.user.id) {
        // Add place to circle
        circle.places.push(place._id);
        await circle.save();
        
        // Add circle to place
        place.circles.push(circle._id);
        await place.save();
      }
    }

    res.status(201).json({
      success: true,
      data: place
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Update place
// @route   PUT /api/places/:id
// @access  Private
exports.updatePlace = async (req, res, next) => {
  try {
    let place = await Place.findById(req.params.id);

    if (!place) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    // Make sure user is place owner
    if (place.addedBy.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to update this place'
      });
    }

    // Don't allow changing owner
    const { addedBy, ...updateData } = req.body;

    place = await Place.findByIdAndUpdate(req.params.id, updateData, {
      new: true,
      runValidators: true
    });

    res.status(200).json({
      success: true,
      data: place
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Upload place photos
// @route   POST /api/places/:id/upload-photos
// @access  Private
exports.uploadPlacePhotos = async (req, res, next) => {
  try {
    const place = await Place.findById(req.params.id);

    if (!place) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    // Make sure user is place owner
    if (place.addedBy.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to update this place'
      });
    }

    if (!req.files || req.files.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Please upload at least one file'
      });
    }

    const bucket = storage.bucket();
    const uploadPromises = req.files.map(async (file) => {
      const fileName = `place-photos/${place._id}-${Date.now()}-${file.originalname}`;
      const fileUpload = bucket.file(fileName);
      
      return new Promise((resolve, reject) => {
        const blobStream = fileUpload.createWriteStream({
          metadata: {
            contentType: file.mimetype
          }
        });

        blobStream.on('error', reject);

        blobStream.on('finish', async () => {
          // Make the file public
          await fileUpload.makePublic();
          
          // Get the public URL
          const publicUrl = `https://storage.googleapis.com/${bucket.name}/${fileUpload.name}`;
          resolve(publicUrl);
        });

        blobStream.end(file.buffer);
      });
    });

    const photoUrls = await Promise.all(uploadPromises);
    
    // Add new photos to place
    place.photos = [...place.photos, ...photoUrls];
    await place.save();

    res.status(200).json({
      success: true,
      data: place
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Delete place
// @route   DELETE /api/places/:id
// @access  Private
exports.deletePlace = async (req, res, next) => {
  try {
    const place = await Place.findById(req.params.id);

    if (!place) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    // Make sure user is place owner
    if (place.addedBy.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to delete this place'
      });
    }

    // Remove place reference from all circles
    await Circle.updateMany(
      { places: place._id },
      { $pull: { places: place._id } }
    );

    await place.deleteOne();

    res.status(200).json({
      success: true,
      data: {}
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Add place to circle
// @route   POST /api/places/:id/add-to-circle/:circleId
// @access  Private
exports.addPlaceToCircle = async (req, res, next) => {
  try {
    const place = await Place.findById(req.params.id);
    const circle = await Circle.findById(req.params.circleId);

    if (!place || !circle) {
      return res.status(404).json({
        success: false,
        message: 'Place or circle not found'
      });
    }

    // Make sure user owns the circle
    if (circle.owner.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to modify this circle'
      });
    }

    // Check if place is already in circle
    if (circle.places.includes(place._id)) {
      return res.status(400).json({
        success: false,
        message: 'Place already in this circle'
      });
    }

    // Add place to circle
    circle.places.push(place._id);
    await circle.save();

    // Add circle to place if not already there
    if (!place.circles.includes(circle._id)) {
      place.circles.push(circle._id);
      await place.save();
    }

    res.status(200).json({
      success: true,
      message: 'Place added to circle'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Remove place from circle
// @route   DELETE /api/places/:id/remove-from-circle/:circleId
// @access  Private
exports.removePlaceFromCircle = async (req, res, next) => {
  try {
    const place = await Place.findById(req.params.id);
    const circle = await Circle.findById(req.params.circleId);

    if (!place || !circle) {
      return res.status(404).json({
        success: false,
        message: 'Place or circle not found'
      });
    }

    // Make sure user owns the circle
    if (circle.owner.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to modify this circle'
      });
    }

    // Remove place from circle
    circle.places = circle.places.filter(
      id => id.toString() !== place._id.toString()
    );
    await circle.save();

    // Remove circle from place
    place.circles = place.circles.filter(
      id => id.toString() !== circle._id.toString()
    );
    await place.save();

    res.status(200).json({
      success: true,
      message: 'Place removed from circle'
    });
  } catch (error) {
    next(error);
  }
};

// @desc    Search for places
// @route   GET /api/places/search
// @access  Private
exports.searchPlaces = async (req, res, next) => {
  try {
    const { query, category, near } = req.query;
    
    let searchQuery = {};
    
    // Text search
    if (query) {
      searchQuery.$or = [
        { name: { $regex: query, $options: 'i' } },
        { 'address.formattedAddress': { $regex: query, $options: 'i' } },
        { description: { $regex: query, $options: 'i' } },
        { notes: { $regex: query, $options: 'i' } }
      ];
    }
    
    // Category filter
    if (category) {
      searchQuery.category = category;
    }
    
    // Location search (near coordinates)
    if (near) {
      const [lng, lat] = near.split(',').map(coord => parseFloat(coord));
      
      if (!isNaN(lng) && !isNaN(lat)) {
        searchQuery.location = {
          $near: {
            $geometry: {
              type: 'Point',
              coordinates: [lng, lat]
            },
            $maxDistance: 10000 // 10km
          }
        };
      }
    }
    
    // Find places that are publicly accessible, from friends, or owned by the user
    const friendIds = req.user.friends.map(friend => friend.toString());
    
    const places = await Place.find({
      ...searchQuery,
      $or: [
        { addedBy: req.user.id },
        { privacy: 'public' },
        { addedBy: { $in: friendIds }, privacy: 'friends' }
      ]
    })
      .populate('addedBy', 'displayName')
      .populate('circles', 'name');

    res.status(200).json({
      success: true,
      count: places.length,
      data: places
    });
  } catch (error) {
    next(error);
  }
};
