// backend/controllers/placeController.js
const Place = require('../models/Place');
const Circle = require('../models/Circle');
const { Client } = require('@googlemaps/google-maps-services-js');
const { googleMapsApiKey } = require('../config/config');
const { storage } = require('../config/firebase');
const axios = require('axios');

const googleMapsClient = new Client({});

// Helper function to download Google Place photo and upload to Firebase
async function downloadAndStoreGooglePlacePhoto(photoUrl, placeId, photoIndex) {
  try {
    // Download the image from Google
    const response = await axios.get(photoUrl, {
      responseType: 'arraybuffer'
    });
    
    // Convert to buffer
    const buffer = Buffer.from(response.data, 'binary');
    
    // Generate a unique filename
    const fileName = `place-photos/${placeId}/google-photo-${photoIndex}-${Date.now()}.jpg`;
    
    // Upload to Firebase Storage
    const bucket = storage.bucket();
    const file = bucket.file(fileName);
    
    await new Promise((resolve, reject) => {
      const stream = file.createWriteStream({
        metadata: {
          contentType: 'image/jpeg'
        }
      });
      
      stream.on('error', reject);
      stream.on('finish', async () => {
        // Make the file public
        await file.makePublic();
        resolve();
      });
      
      stream.end(buffer);
    });
    
    // Return the public URL
    return `https://storage.googleapis.com/${bucket.name}/${fileName}`;
  } catch (error) {
    console.error('Error downloading/storing Google Place photo:', error);
    // Return the original URL as fallback
    return photoUrl;
  }
}

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
            fields: ['name', 'formatted_address', 'geometry', 'photos', 'website', 'formatted_phone_number', 'opening_hours', 'types', 'rating', 'user_ratings_total', 'price_level', 'reviews', 'business_status']
          }
        });
        
        const placeDetails = response.data.result;
        
        // Enhance the request body with Google data
        req.body.name = req.body.name || placeDetails.name;
        req.body.address = placeDetails.formatted_address;
        req.body.location = {
          type: 'Point',
          coordinates: [
            placeDetails.geometry.location.lng,
            placeDetails.geometry.location.lat
          ]
        };
        req.body.website = placeDetails.website;
        req.body.phone = placeDetails.formatted_phone_number;
        
        // Add rating and review information
        if (placeDetails.rating) req.body.rating = placeDetails.rating;
        if (placeDetails.user_ratings_total) req.body.userRatingsTotal = placeDetails.user_ratings_total;
        if (placeDetails.price_level !== undefined) req.body.priceLevel = placeDetails.price_level;
        
        // Add opening hours
        if (placeDetails.opening_hours && placeDetails.opening_hours.periods) {
          req.body.openingHours = placeDetails.opening_hours.periods.map(period => ({
            day: period.open.day,
            open: `${period.open.hours.padStart(2, '0')}:${period.open.minutes.padStart(2, '0')}`,
            close: period.close ? `${period.close.hours.padStart(2, '0')}:${period.close.minutes.padStart(2, '0')}` : '23:59',
            isClosed: false
          }));
        }
        
        // Add reviews
        if (placeDetails.reviews && placeDetails.reviews.length > 0) {
          req.body.reviews = placeDetails.reviews.map(review => ({
            user: review.author_name,
            rating: review.rating,
            comment: review.text,
            date: new Date(review.time * 1000)
          }));
        }
        
        // Process Google Places photos - download and store in Firebase
        if (placeDetails.photos && placeDetails.photos.length > 0) {
          console.log('Processing Google Places photos...');
          
          // Generate Google photo URLs
          const googlePhotoUrls = placeDetails.photos.slice(0, 5).map(photo => {
            return `https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photoreference=${photo.photo_reference}&key=${googleMapsApiKey}`;
          });
          
          // Download and store each photo in Firebase
          const firebasePhotoUrls = await Promise.all(
            googlePhotoUrls.map(async (url, index) => {
              const firebaseUrl = await downloadAndStoreGooglePlacePhoto(url, req.body.googlePlaceId || Date.now().toString(), index);
              return firebaseUrl;
            })
          );
          
          req.body.photos = firebasePhotoUrls;
          console.log('Stored photos in Firebase:', req.body.photos);
        }
        
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
    
    // Debug: Log if photos are present
    if (placeData.photos) {
      console.log('Creating place with photos:', placeData.photos);
    }
    
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

    // Return the populated place
    const populatedPlace = await Place.findById(place._id)
      .populate('addedBy', 'displayName profilePicture')
      .populate('circles', 'name privacy');
    
    res.status(201).json({
      success: true,
      place: populatedPlace
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
        { address: { $regex: query, $options: 'i' } },
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

// @desc    Refresh place data from Google Places
// @route   POST /api/places/:id/refresh-google
// @access  Private
exports.refreshPlaceFromGoogle = async (req, res, next) => {
  try {
    const place = await Place.findById(req.params.id);
    
    if (!place) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    // Check permissions
    const isOwner = place.addedBy.toString() === req.user.id;
    const circle = await Circle.findById(place.circleId);
    const isCircleMember = circle && circle.members.includes(req.user.id);
    
    if (!isOwner && !isCircleMember) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to refresh this place'
      });
    }
    
    // Check if place has Google Place ID
    if (!place.googlePlaceId) {
      return res.status(400).json({
        success: false,
        message: 'This place does not have a Google Place ID'
      });
    }
    
    try {
      // Fetch fresh data from Google Places API
      const response = await googleMapsClient.placeDetails({
        params: {
          place_id: place.googlePlaceId,
          fields: [
            'name',
            'formatted_address',
            'formatted_phone_number',
            'website',
            'rating',
            'user_ratings_total',
            'price_level',
            'types',
            'opening_hours',
            'photos',
            'reviews',
            'business_status'
          ].join(','),
          key: googleMapsApiKey
        }
      });
      
      const googleData = response.data.result;
      
      // Update place with fresh Google data
      if (googleData.name) place.name = googleData.name;
      if (googleData.formatted_address) place.address = googleData.formatted_address;
      if (googleData.formatted_phone_number) place.phone = googleData.formatted_phone_number;
      if (googleData.website) place.website = googleData.website;
      if (googleData.rating) place.rating = googleData.rating;
      if (googleData.user_ratings_total) place.userRatingsTotal = googleData.user_ratings_total;
      
      // Update price level
      if (googleData.price_level !== undefined) {
        place.priceLevel = googleData.price_level;
      }
      
      // Update opening hours
      if (googleData.opening_hours && googleData.opening_hours.periods) {
        place.openingHours = googleData.opening_hours.periods.map(period => ({
          day: period.open.day,
          open: `${period.open.hours.padStart(2, '0')}:${period.open.minutes.padStart(2, '0')}`,
          close: period.close ? `${period.close.hours.padStart(2, '0')}:${period.close.minutes.padStart(2, '0')}` : '23:59',
          isClosed: false
        }));
      }
      
      // Update reviews from Google
      if (googleData.reviews && googleData.reviews.length > 0) {
        place.reviews = googleData.reviews.map(review => ({
          user: review.author_name,
          rating: review.rating,
          comment: review.text,
          date: new Date(review.time * 1000) // Convert Unix timestamp to Date
        }));
      }
      
      place.updatedAt = Date.now();
      
      await place.save();
      
      res.status(200).json({
        success: true,
        place: place
      });
      
    } catch (googleError) {
      console.error('Google Places API Error:', googleError);
      return res.status(500).json({
        success: false,
        message: 'Failed to fetch data from Google Places'
      });
    }
    
  } catch (error) {
    next(error);
  }
};

// @desc    Get places by circle ID
// @route   GET /api/circles/:id/places
// @access  Private
exports.getPlacesByCircleId = async (req, res, next) => {
  try {
    const circleId = req.params.id;
    
    // First get the circle to check permissions and get the ordered place IDs
    const circle = await Circle.findById(circleId);
    
    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    // Check permissions
    const isOwner = circle.owner.toString() === req.user.id;
    const isSharedWith = circle.sharedWith.includes(req.user.id);
    const isFriend = req.user.friends.includes(circle.owner.toString());
    const isPublic = circle.privacy === 'public';
    const isFriendsCircle = circle.privacy === 'friends' && isFriend;
    
    if (!isOwner && !isSharedWith && !isPublic && !isFriendsCircle) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view this circle'
      });
    }
    
    // Fetch places and preserve the order from the circle's places array
    const placesMap = new Map();
    
    // Fetch all places
    const places = await Place.find({
      _id: { $in: circle.places }
    })
      .populate('addedBy', 'displayName profilePicture')
      .populate('circles', 'name privacy');
    
    // Create a map for quick lookup
    places.forEach(place => {
      placesMap.set(place._id.toString(), place);
    });
    
    // Return places in the order specified in the circle's places array
    const orderedPlaces = circle.places
      .map(placeId => placesMap.get(placeId.toString()))
      .filter(place => place !== undefined); // Filter out any deleted places
    
    console.log('Circle places order:', circle.places.map(id => id.toString()));
    console.log('Returning places in order:', orderedPlaces.map(p => ({ id: p._id.toString(), name: p.name })));
    
    res.status(200).json({
      success: true,
      count: orderedPlaces.length,
      places: orderedPlaces
    });
    
  } catch (error) {
    next(error);
  }
};

// @desc    Reorder places within a circle
// @route   PUT /api/circles/:id/places/reorder
// @access  Private
exports.reorderPlacesInCircle = async (req, res, next) => {
  try {
    const { placeIds } = req.body;
    const circleId = req.params.id;
    
    if (!placeIds || !Array.isArray(placeIds)) {
      return res.status(400).json({
        success: false,
        message: 'Please provide an array of place IDs'
      });
    }
    
    const circle = await Circle.findById(circleId);
    
    if (!circle) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    // Make sure user owns the circle
    if (circle.owner.toString() !== req.user.id) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to modify this circle'
      });
    }
    
    // Verify all place IDs exist in the circle
    const existingPlaceIds = circle.places.map(id => id.toString());
    const providedPlaceIds = placeIds.map(id => id.toString());
    
    // Check if all provided IDs exist in the circle
    const allIdsExist = providedPlaceIds.every(id => existingPlaceIds.includes(id));
    
    if (!allIdsExist) {
      return res.status(400).json({
        success: false,
        message: 'Invalid place IDs - some places do not belong to this circle'
      });
    }
    
    // Check if all circle places are accounted for
    if (providedPlaceIds.length !== existingPlaceIds.length) {
      return res.status(400).json({
        success: false,
        message: 'All places in the circle must be included in the reorder'
      });
    }
    
    // Update the places array with the new order
    console.log('Reordering places from:', circle.places.map(id => id.toString()));
    console.log('Reordering places to:', placeIds);
    
    circle.places = placeIds;
    await circle.save();
    
    console.log('Saved circle with new order:', circle.places.map(id => id.toString()));
    
    res.status(200).json({
      success: true,
      message: 'Places reordered successfully'
    });
    
  } catch (error) {
    next(error);
  }
};
