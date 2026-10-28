// Order ahead from a store's menu, pay at pickup (services/orders). Customers.
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const orders = require('../controllers/orders/orderController');

const router = express.Router();
router.use(protect);
router.post('/', orders.place);
router.get('/mine', orders.mine);
router.get('/:orderId', orders.get);
router.post('/:orderId/cancel', orders.cancel);
router.post('/:orderId/picked-up', orders.pickedUp);

module.exports = router;
