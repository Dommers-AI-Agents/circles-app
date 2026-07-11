// backend/routes/trashRoutes.js
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const {
  listTrash,
  restoreCircle,
  permanentDeleteCircle,
  restorePlace,
  permanentDeletePlace
} = require('../controllers/trashController');

const router = express.Router();

router.use(protect);

router.get('/', listTrash);

router.post('/circles/:id/restore', restoreCircle);
router.delete('/circles/:id', permanentDeleteCircle);

router.post('/places/:id/restore', restorePlace);
router.delete('/places/:id', permanentDeletePlace);

module.exports = router;
