// backend/routes/userCategoriesRoutes.js
const express = require('express');
const {
  getUserCategories,
  createCategory,
  updateCategory,
  deleteCategory,
  getPredefinedCategories
} = require('../controllers/userCategoriesController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// Apply auth middleware to all routes
router.use(protect);

// User categories routes
router.route('/')
  .get(getUserCategories)
  .post(createCategory);

router.route('/predefined')
  .get(getPredefinedCategories);

router.route('/:id')
  .put(updateCategory)
  .delete(deleteCategory);

module.exports = router;