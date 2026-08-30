/**
 * The canonical checkout contract: what a customer actually pays, and what a
 * purchase actually consumes.
 *
 * Two rules drive everything here.
 *
 * 1. The payable unit price is derived on the server from the stored base price
 *    and discount. A client sends only a product id and a quantity, so it can
 *    never name a price.
 * 2. Finite inventory is reserved with a single conditional document update, so
 *    two concurrent checkouts for the last unit cannot both succeed.
 *
 * The reservation is expressed as a Mongo filter/update pair rather than
 * executed here, which keeps this module free of I/O and directly testable.
 */

import { AppError } from '../utils/AppError.js';
import {
  finalPriceFor,
  hasProductVariants,
  isProductInStock,
  roundMoney,
  variantFinalPriceFor
} from './product.policy.js';

/** Matches the per-item bound the order validator already enforces. */
export const MAX_ITEM_QUANTITY = 100;

export const CHECKOUT_ERRORS = {
  duplicateQuantity: 'INVALID_QUANTITY',
  notAvailable: 'PRODUCT_NOT_AVAILABLE',
  variantRequired: 'PRODUCT_VARIANT_REQUIRED',
  variantNotAvailable: 'PRODUCT_VARIANT_NOT_AVAILABLE',
  outOfStock: 'PRODUCT_OUT_OF_STOCK',
  insufficientStock: 'INSUFFICIENT_STOCK'
};

/**
 * A product is finite only when it explicitly says so.
 *
 * Legacy documents predate inventory and carry no `unlimitedStock` at all;
 * `isProductInStock` already treats those as unlimited, and this must agree or
 * a historical product would be decremented from a quantity it never had.
 */
export function isFiniteStockProduct(product) {
  return product?.unlimitedStock === false;
}

/**
 * Collapses repeated sellable identities into one line.
 *
 * A simple product identity is `(productId)`. A variant product identity is
 * `(productId, variantId)`, so sibling variants can never be merged together.
 *
 * This is not hypothetical: adding the same product to the cart twice appends
 * two entries, so a real checkout can carry the same id more than once.
 * Rejecting duplicates would break that flow, so they are summed instead - and
 * the summed quantity is re-checked against the same per-item bound, so two
 * lines of 60 cannot smuggle 120 units past the validator.
 *
 * Returns `{ items }` on success or `{ error }` with a stable code.
 */
export function normalizeRequestedItems(requestedItems) {
  const merged = new Map();

  for (const requested of requestedItems ?? []) {
    const productId = String(requested?.productId ?? '');
    const rawVariantId = requested?.variantId;
    const variantId =
      rawVariantId === undefined ||
      rawVariantId === null ||
      String(rawVariantId).trim().length === 0
        ? null
        : String(rawVariantId).trim();

    const identity = `${productId}\u0000${variantId ?? ''}`;
    const quantity = Number(requested?.quantity);
    const running = merged.get(identity);

    if (running) {
      running.quantity += quantity;
    } else {
      merged.set(identity, {
        productId,
        ...(variantId ? { variantId } : {}),
        quantity
      });
    }
  }

  for (const item of merged.values()) {
    if (!Number.isInteger(item.quantity) || item.quantity < 1) {
      return {
        error: CHECKOUT_ERRORS.duplicateQuantity,
        productId: item.productId,
        ...(item.variantId ? { variantId: item.variantId } : {})
      };
    }

    if (item.quantity > MAX_ITEM_QUANTITY) {
      return {
        error: CHECKOUT_ERRORS.duplicateQuantity,
        productId: item.productId,
        ...(item.variantId ? { variantId: item.variantId } : {})
      };
    }
  }

  return { items: [...merged.values()] };
}

/**
 * Turns normalized requests into priced order lines, or reports the first
 * reason the order cannot be accepted.
 *
 * The unit price comes from `finalPriceFor` - the same function the public
 * serializer uses for `finalPrice` - so the price shown to the customer and the
 * price stored on the order are derived from one rule.
 *
 * Stock is checked here for a clear error code. It is checked AGAIN, atomically,
 * by the reservation below; this pass is diagnosis, not the guarantee.
 */
export function resolveOrderLines({ products, items }) {
  const byId = new Map(
    (products ?? [])
      .filter((product) => product.isActive)
      .map((product) => [product._id.toString(), product])
  );
  const lines = [];

  for (const item of items) {
    const productId = item.productId;
    const quantity = item.quantity;
    const variantId = item.variantId
      ? String(item.variantId).trim()
      : null;

    const product = byId.get(productId);

    if (!product) {
      return { error: CHECKOUT_ERRORS.notAvailable, productId };
    }

    const variantMode = hasProductVariants(product);
    let variant = null;
    let inventoryTarget = product;

    if (variantMode) {
      if (!variantId) {
        return {
          error: CHECKOUT_ERRORS.variantRequired,
          productId
        };
      }

      variant =
        (product.variants ?? []).find(
          (entry) =>
            entry?.isActive !== false &&
            String(entry?._id ?? '') === variantId
        ) ?? null;

      if (!variant) {
        return {
          error: CHECKOUT_ERRORS.variantNotAvailable,
          productId,
          variantId
        };
      }

      inventoryTarget = variant;
    } else if (variantId) {
      // A variant identity can never turn a simple product into a variant
      // product. The catalog stored on the server owns that decision.
      return {
        error: CHECKOUT_ERRORS.variantNotAvailable,
        productId,
        variantId
      };
    }

    if (!isProductInStock(inventoryTarget)) {
      return {
        error: CHECKOUT_ERRORS.outOfStock,
        productId,
        ...(variantId ? { variantId } : {})
      };
    }

    const finite = isFiniteStockProduct(inventoryTarget);

    if (
      finite &&
      quantity > (Number(inventoryTarget.stockQuantity) || 0)
    ) {
      return {
        error: CHECKOUT_ERRORS.insufficientStock,
        productId,
        ...(variantId ? { variantId } : {})
      };
    }

    lines.push({
      product,
      productId,
      ...(variant
        ? {
            variant,
            variantId: String(variant._id),
            variantLabel: String(variant.label ?? '').trim()
          }
        : {}),
      quantity,
      finite,
      unitPrice: variant
        ? variantFinalPriceFor(product, variant)
        : finalPriceFor({
            price: product.price ?? 0,
            discountPercent: product.discountPercent ?? 0
          })
    });
  }

  return { lines };
}

export function subtotalFor(lines) {
  return roundMoney(
    lines.reduce((sum, line) => sum + line.unitPrice * line.quantity, 0)
  );
}

/**
 * The delivery tiers, priced here and nowhere else.
 *
 * The buyer picks a tier; the price of that tier is never sent by the client
 * and never trusted from it. `standard` is the fee this system has always
 * charged, so an order that names no option is charged exactly what it was
 * charged before this choice existed.
 */
export const DELIVERY_OPTIONS = Object.freeze({
  standard: 10,
  express: 30
});

export const DEFAULT_DELIVERY_OPTION = 'standard';

export function isDeliveryOption(value) {
  return Object.prototype.hasOwnProperty.call(DELIVERY_OPTIONS, value);
}

/**
 * The delivery fee for a subtotal and a tier. Charged only when something is
 * actually payable, so a fully discounted basket is not handed a delivery
 * charge on its own.
 */
export function deliveryFeeFor(subtotal, option = DEFAULT_DELIVERY_OPTION) {
  if (subtotal <= 0) return 0;
  // An unrecognised tier must not silently resolve to the cheapest one.
  if (!isDeliveryOption(option)) {
    throw new AppError(
      'Delivery option is invalid',
      400,
      'INVALID_DELIVERY_OPTION'
    );
  }

  return DELIVERY_OPTIONS[option];
}

/** The payable total, always derived from the server-side subtotal. */
export function totalFor(subtotal, option = DEFAULT_DELIVERY_OPTION) {
  return roundMoney(subtotal + deliveryFeeFor(subtotal, option));
}

/**
 * NOTE: the reservation and release builders no longer live here.
 *
 * An unguarded `$inc` pair could be applied twice - once by a crash replay and
 * once by a retry - so both operations now carry a durable reservation identity
 * and live in `checkout-intent.policy.js`. Nothing in this module may
 * reintroduce an unconditional stock increment.
 */
