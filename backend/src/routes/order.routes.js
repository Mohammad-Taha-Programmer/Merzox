import { Router } from 'express';

import {
  cancelMyOrder,
  createOrder,
  getMyOrder,
  listMyOrders,
  updateMyOrderAddress
} from '../controllers/order.controller.js';
import { requireAuth } from '../middleware/auth.js';
import {
  validateOrderAddressPatch,
  validateOrderCancellation,
  validateOrderCreate
} from '../middleware/validate.js';

const router = Router();

router.use(requireAuth);
router.get('/', listMyOrders);
router.post('/', validateOrderCreate, createOrder);
router.get('/:id', getMyOrder);
router.patch('/:id/address', validateOrderAddressPatch, updateMyOrderAddress);
router.patch('/:id/cancel', validateOrderCancellation, cancelMyOrder);

export default router;
