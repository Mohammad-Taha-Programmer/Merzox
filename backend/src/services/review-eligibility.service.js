import { Order } from '../models/Order.js';
import {
  OWN_BUSINESS_REVIEW_CODE,
  reviewsOwnBusiness
} from '../policies/review-authorship.policy.js';
import { AppError } from '../utils/AppError.js';

export const reviewEligibilityReasons = Object.freeze({
  customerAccountRequired: 'customerAccountRequired',
  ownBusiness: 'ownBusiness',
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
  /// The shop's owner, so the one review nobody may write can be recognised.
  ownerId,
  productId,
  orderModel = Order
}) {
  if (!user) {
    return {
      eligible: false,
      reason: reviewEligibilityReasons.customerAccountRequired
    };
  }

  // A merchant buying from another merchant is that shop's customer like any
  // other. The thing worth preventing is rating your own shop, and that is
  // what is checked - not the type printed on the account.
  if (reviewsOwnBusiness(user._id, ownerId)) {
    return {
      eligible: false,
      reason: reviewEligibilityReasons.ownBusiness
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

  if (eligibility.reason === reviewEligibilityReasons.ownBusiness) {
    throw new AppError(
      'A shop cannot be reviewed by the person who owns it',
      403,
      OWN_BUSINESS_REVIEW_CODE
    );
  }

  throw new AppError(
    'A delivered purchase is required to submit this review',
    403,
    'REVIEW_NOT_ELIGIBLE'
  );
}
