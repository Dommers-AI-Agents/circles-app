// Simple syntax test
try {
  require('/Users/wesleysgroi/favcircles/backend/controllers/circleController.js');
  console.log('✅ Syntax is valid');
} catch (error) {
  console.log('❌ Syntax error:', error.message);
}