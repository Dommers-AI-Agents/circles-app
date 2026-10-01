// backend/routes/adminDashboardRoutes.js — /api/admin/dashboard/*
// Super users only (users.isSuperUser, set with scripts/setSuperUser.js).
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const c = require('../controllers/adminDashboardController');

const router = express.Router();

router.use(protect, (req, res, next) => {
  if (req.user && req.user.isSuperUser === true) return next();
  return res.status(403).json({ success: false, code: 'NOT_ADMIN', message: "This account isn't an admin." });
});

router.get('/me', c.me);
router.get('/overview', c.overview);
router.get('/people', c.people);
router.get('/people/:id', c.person);
router.get('/money', c.money);
router.get('/messaging', c.messaging);

module.exports = router;
