import { Router } from 'express';

import {
  getBusinessFavoriteStatus,
  listFavoriteBusinesses,
  listFavoriteProducts
} from '../controllers/favorite.controller.js';
import { requireAuth } from '../middleware/auth.js';

const router = Router();

router.use(requireAuth);
router.get('/businesses', listFavoriteBusinesses);
router.get('/products', listFavoriteProducts);
router.get('/businesses/:businessId/status', getBusinessFavoriteStatus);

export default router;
