// backend/routes/circleGroupsRoutes.js
const express = require('express');
const {
  getMyCircleGroups,
  createCircleGroup,
  updateCircleGroup,
  deleteCircleGroup,
  addCircleToGroup,
  removeCircleFromGroup
} = require('../controllers/circleGroupsController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();

// All routes require authentication
router.use(protect);

// Circle groups CRUD operations
router.route('/')
  .get(getMyCircleGroups)      // GET /api/circles/groups
  .post(createCircleGroup);     // POST /api/circles/groups

router.route('/:id')
  .put(updateCircleGroup)       // PUT /api/circles/groups/:id
  .delete(deleteCircleGroup);   // DELETE /api/circles/groups/:id

// Circle management within groups
router.route('/:id/circles')
  .post(addCircleToGroup);      // POST /api/circles/groups/:id/circles

router.route('/:groupId/circles/:circleId')
  .delete(removeCircleFromGroup); // DELETE /api/circles/groups/:groupId/circles/:circleId

module.exports = router;