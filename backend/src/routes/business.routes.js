import { Router } from 'express';

import {
  createBusinessProductReview,
  createBusinessReview,
  getBusiness,
  getBusinessProduct,
  getBusinessProductReviewEligibility,
  getBusinessReviewEligibility,
  likeBusinessProduct,
  listBusinessProductReviews,
  listBusinesses,
  listBusinessProducts,
  listBusinessReviews
} from '../controllers/business.controller.js';
import { setBusinessFavorite } from '../controllers/favorite.controller.js';
import {
  getMerchantConversationUnreadCount,
  listMerchantConversations
} from '../controllers/message.controller.js';
import {
  createMyBusinessProduct,
  deleteMyBusinessProduct,
  enrollBusiness,
  getMyBusiness,
  getMyBusinessDashboard,
  listMyBusinessOrders,
  listMyBusinessProducts,
  revokeMyBusinessOrderCourierLocation,
  updateMyBusiness,
  updateMyBusinessOrderCourier,
  updateMyBusinessOrderStatus,
  updateMyBusinessProduct
} from '../controllers/merchant.controller.js';
import {
  requireAuth,
  requireBusinessUser,
  requireCustomerUser
} from '../middleware/auth.js';
import {
  validateBusinessEnrollment,
  validateBusinessOrderStatus,
  validateBusinessProductCreate,
  validateBusinessProductPatch,
  validateBusinessProfilePatch,
  validateOrderCourierPatch
} from '../middleware/validate.js';

const router = Router();

router.post('/enroll', requireAuth, validateBusinessEnrollment, enrollBusiness);
router.get('/me', requireAuth, requireBusinessUser, getMyBusiness);
router.patch(
  '/me',
  requireAuth,
  requireBusinessUser,
  validateBusinessProfilePatch,
  updateMyBusiness
);
router.get(
  '/me/dashboard',
  requireAuth,
  requireBusinessUser,
  getMyBusinessDashboard
);
router.get('/me/orders', requireAuth, requireBusinessUser, listMyBusinessOrders);
router.patch(
  '/me/orders/:orderId/status',
  requireAuth,
  requireBusinessUser,
  validateBusinessOrderStatus,
  updateMyBusinessOrderStatus
);
router.patch(
  '/me/orders/:orderId/courier',
  requireAuth,
  requireBusinessUser,
  validateOrderCourierPatch,
  updateMyBusinessOrderCourier
);
router.delete(
  '/me/orders/:orderId/courier-location-capability',
  requireAuth,
  requireBusinessUser,
  revokeMyBusinessOrderCourierLocation
);
router.get(
  '/me/conversations/unread-count',
  requireAuth,
  requireBusinessUser,
  getMerchantConversationUnreadCount
);
router.get(
  '/me/conversations',
  requireAuth,
  requireBusinessUser,
  listMerchantConversations
);
router.get('/me/products', requireAuth, requireBusinessUser, listMyBusinessProducts);
router.post(
  '/me/products',
  requireAuth,
  requireBusinessUser,
  validateBusinessProductCreate,
  createMyBusinessProduct
);
router.patch(
  '/me/products/:productId',
  requireAuth,
  requireBusinessUser,
  validateBusinessProductPatch,
  updateMyBusinessProduct
);
router.delete(
  '/me/products/:productId',
  requireAuth,
  requireBusinessUser,
  deleteMyBusinessProduct
);
router.get('/', listBusinesses);
router.get('/:id/products', listBusinessProducts);
router.get('/:id/products/:productId', getBusinessProduct);
router.get(
  '/:id/products/:productId/review-eligibility',
  requireAuth,
  getBusinessProductReviewEligibility
);
router.get('/:id/products/:productId/reviews', listBusinessProductReviews);
router.post(
  '/:id/products/:productId/reviews',
  requireAuth,
  requireCustomerUser,
  createBusinessProductReview
);
router.post('/:id/products/:productId/like', requireAuth, likeBusinessProduct);
router.post('/:id/favorite', requireAuth, setBusinessFavorite);
router.get(
  '/:id/review-eligibility',
  requireAuth,
  getBusinessReviewEligibility
);
router.get('/:id/reviews', listBusinessReviews);
router.post(
  '/:id/reviews',
  requireAuth,
  requireCustomerUser,
  createBusinessReview
);
router.get('/:id', getBusiness);

export default router;
