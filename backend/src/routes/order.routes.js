import { Router } from 'express';

import {
  updateCourierLocationByCapability
} from '../controllers/courier-location.controller.js';
import {
  cancelMyOrder,
  createOrder,
  getMyOrder,
  listDeliveryOptions,
  listMyOrders,
  updateMyOrderAddress
} from '../controllers/order.controller.js';
import { requireAuth } from '../middleware/auth.js';
import {
  validateCourierLocationUpdate,
  validateOrderAddressPatch,
  validateOrderCancellation,
  validateOrderCreate
} from '../middleware/validate.js';

const router = Router();

router.patch(
  '/:id/courier-location',
  validateCourierLocationUpdate,
  updateCourierLocationByCapability
);

// Public: the fee is the same for everyone, and a shopper deciding
// whether to check out should not have to sign in to see it.
router.get('/delivery-options', listDeliveryOptions);

router.use(requireAuth);
router.get('/', listMyOrders);
router.post('/', validateOrderCreate, createOrder);
router.get('/:id', getMyOrder);
router.patch('/:id/address', validateOrderAddressPatch, updateMyOrderAddress);
router.patch('/:id/cancel', validateOrderCancellation, cancelMyOrder);

export default router;
