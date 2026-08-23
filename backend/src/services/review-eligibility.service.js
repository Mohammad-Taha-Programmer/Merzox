import { Order } from '../models/Order.js';
import { AppError } from '../utils/AppError.js';

export const reviewEligibilityReasons = Object.freeze({
  customerAccountRequired: 'customerAccountRequired',
  deliveredPurchaseRequired: 'deliveredPurchaseRequired'
});

function deliveredPurchaseFilter({ userId, businessId, productId }) {
  const filter = {
    user: userId,
    business: businessId,
    status: 'delivered'
  };

  if (productId !== undefined && productId !== null) {
    filter['items.productId'] = productId;
  }

  return filter;
}

/**
 * Server-authoritative review eligibility.
 *
 * The client never supplies an order id or an eligibility assertion. The
 * server proves eligibility directly from delivered orders owned by the
 * authenticated customer.
 */
export async function getReviewEligibility({
  user,
  businessId,
  productId,
  orderModel = Order
}) {
  if (!user || user.userType !== 'normal') {
    return {
      eligible: false,
      reason: reviewEligibilityReasons.customerAccountRequired
    };
  }

  const deliveredPurchase = await orderModel.exists(
    deliveredPurchaseFilter({
      userId: user._id,
      businessId,
      productId
    })
  );

  if (!deliveredPurchase) {
    return {
      eligible: false,
      reason: reviewEligibilityReasons.deliveredPurchaseRequired
    };
  }

  return { eligible: true, reason: null };
}

/**
 * Write-time fence.
 *
 * Eligibility is always checked again immediately before a review mutation.
 * A prior eligibility GET is only UI guidance and is never trusted as proof.
 */
export async function assertReviewEligible(options) {
  const eligibility = await getReviewEligibility(options);

  if (eligibility.eligible) {
    return eligibility;
  }

  if (
    eligibility.reason ===
    reviewEligibilityReasons.customerAccountRequired
  ) {
    throw new AppError(
      'A customer account is required to submit reviews',
      403,
      'CUSTOMER_ACCOUNT_REQUIRED'
    );
  }

  throw new AppError(
    'A delivered purchase is required to submit this review',
    403,
    'REVIEW_NOT_ELIGIBLE'
  );
}
