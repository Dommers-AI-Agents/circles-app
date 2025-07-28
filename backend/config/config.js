module.exports = {
    jwtSecret: process.env.JWT_SECRET,
    jwtExpire: process.env.JWT_EXPIRE || '30d',
    googleMapsApiKey: process.env.GOOGLE_MAPS_API_KEY,
    firebaseApiKey: process.env.FIREBASE_API_KEY,
    env: process.env.NODE_ENV || 'development'
  };