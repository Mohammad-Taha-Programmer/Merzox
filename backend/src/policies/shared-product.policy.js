import { AppError } from '../utils/AppError.js';
import { finalPriceFor } from './product.policy.js';

/**
 * Sharing one product inside a conversation.
 *
 * The rule that matters is whose product may be shared, and it is structural
 * rather than checked: a message names a product by id alone, and the id is
 * looked up inside the shop the conversation already belongs to. A merchant
 * therefore cannot reach past their own shelves, and a customer cannot carry
 * one shop's catalogue into another shop's thread - not because a comparison
 * says no, but because there is nowhere else to look.
 *
 * What is stored is a copy, not a pointer. The card in the thread says what
 * was shared on the day it was shared, so a later price change does not
 * silently rewrite a conversation, and a product that is withdrawn leaves the
 * message readable. The link on the card still leads to the live product.
 */

export const SHARED_PRODUCT_CODES = Object.freeze({
  invalid: 'INVALID_SHARED_PRODUCT',
  notFound: 'SHARED_PRODUCT_NOT_FOUND'
});

/**
 * Reads the product id out of a request body.
 *
 * Absent is not an error: most messages are words. A present-but-unusable one
 * is, because silently dropping it would send a bare message where the reader
 * meant to send a product.
 */
export function readSharedProductId(body = {}) {
  const raw = body.productId;

  if (raw === undefined || raw === null) return null;

  if (typeof raw !== 'string' || raw.trim() === '') {
    throw new AppError(
      'Shared product id is invalid',
      400,
      SHARED_PRODUCT_CODES.invalid
    );
  }

  return raw.trim();
}

/**
 * Whether a message carries anything at all.
 *
 * A body was always required. It no longer is when a product is attached - a
 * card on its own is a message - but the two cannot both be empty.
 */
export function messageHasContent({ body = '', productId = null } = {}) {
  return String(body ?? '').trim().length > 0 || Boolean(productId);
}

/**
 * The copy kept on the message.
 *
 * Deliberately small: a picture, a name and a price is what the card draws.
 * Everything else - stock, variants, description - belongs to the product
 * page the card leads to, where it is read live rather than remembered.
 */
export function sharedProductSnapshot(business, product) {
  const discountPercent = product.discountPercent ?? 0;
  const imageUrl =
    (product.imageUrls ?? []).find(Boolean) ?? product.imageUrl ?? '';

  return {
    productId: product._id.toString(),
    businessId: business._id.toString(),
    name: product.name ?? '',
    price: finalPriceFor({ price: product.price ?? 0, discountPercent }),
    imageUrl
  };
}

/**
 * Finds the product a message may share, inside the shop it belongs to.
 *
 * Refuses a product that is not on that shop's shelves, and one the shop has
 * withdrawn: a card leading to a page the reader cannot open would be worse
 * than not sending it.
 */
export function findShareableProduct(business, productId) {
  const product = business?.products?.id?.(productId) ?? null;

  if (!product || product.isActive === false) {
    throw new AppError(
      'Product was not found in this conversation\'s store',
      404,
      SHARED_PRODUCT_CODES.notFound
    );
  }

  return product;
}
