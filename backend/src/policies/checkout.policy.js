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

import { finalPriceFor, isProductInStock, roundMoney } from './product.policy.js';

/** Matches the per-item bound the order validator already enforces. */
export const MAX_ITEM_QUANTITY = 100;

export const CHECKOUT_ERRORS = {
  duplicateQuantity: 'INVALID_QUANTITY',
  notAvailable: 'PRODUCT_NOT_AVAILABLE',
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
 * Collapses repeated product ids into one line.
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
    const quantity = Number(requested?.quantity);
    const running = merged.get(productId);

    merged.set(productId, (running ?? 0) + quantity);
  }

  for (const [productId, quantity] of merged) {
    if (!Number.isInteger(quantity) || quantity < 1) {
      return { error: CHECKOUT_ERRORS.duplicateQuantity, productId };
    }
    if (quantity > MAX_ITEM_QUANTITY) {
      return { error: CHECKOUT_ERRORS.duplicateQuantity, productId };
    }
  }

  return {
    items: [...merged].map(([productId, quantity]) => ({ productId, quantity }))
  };
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

  for (const { productId, quantity } of items) {
    const product = byId.get(productId);

    if (!product) {
      return { error: CHECKOUT_ERRORS.notAvailable, productId };
    }

    if (!isProductInStock(product)) {
      return { error: CHECKOUT_ERRORS.outOfStock, productId };
    }

    const finite = isFiniteStockProduct(product);

    if (finite && quantity > (Number(product.stockQuantity) || 0)) {
      // Deliberately no available-quantity figure: the exact remaining count is
      // merchant-private and must not leak through an error response.
      return { error: CHECKOUT_ERRORS.insufficientStock, productId };
    }

    lines.push({
      product,
      productId,
      quantity,
      finite,
      unitPrice: finalPriceFor({
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
 * The flat delivery fee. Charged only when something is actually payable, so a
 * fully discounted basket is not handed a delivery charge on its own.
 */
export function deliveryFeeFor(subtotal) {
  return subtotal > 0 ? 10 : 0;
}

/** The payable total, always derived from the server-side subtotal. */
export function totalFor(subtotal) {
  return roundMoney(subtotal + deliveryFeeFor(subtotal));
}

/**
 * The atomic reservation.
 *
 * Every product of one order lives inside the SAME business document, so a
 * single `updateOne` covers the whole basket. MongoDB guarantees a single
 * document update is atomic and isolated even on a standalone server, which
 * matters here: the project's documented local database is standalone
 * (`mongodb://127.0.0.1:27017/...`) and therefore cannot run multi-document
 * transactions at all. This design needs none.
 *
 * The filter asserts, for every line at once, that the product is still active
 * and still has enough stock. If any single assertion fails the update matches
 * nothing and NOTHING is decremented - that is the all-or-nothing guarantee.
 * Two concurrent checkouts for the final unit therefore cannot both match.
 *
 * `$inc` only touches array entries the filters prove are genuinely finite, so a
 * merchant flipping a product to unlimited between read and write cannot cause a
 * decrement of a quantity that no longer means anything.
 */
export function buildStockReservation({ businessId, lines }) {
  const finiteLines = lines.filter((line) => line.finite);

  const filter = {
    _id: businessId,
    isActive: true,
    $and: lines.map((line) => ({
      products: {
        $elemMatch: {
          _id: line.product._id,
          isActive: true,
          ...(line.finite
            ? { unlimitedStock: false, stockQuantity: { $gte: line.quantity } }
            : {})
        }
      }
    }))
  };

  if (finiteLines.length === 0) {
    // Nothing to consume. The filter still runs so an order is never accepted
    // against a business or product that stopped being active mid-checkout.
    return { filter, update: null, arrayFilters: [] };
  }

  const set = {};
  const arrayFilters = finiteLines.map((line, index) => {
    const alias = `line${index}`;
    set[`products.$[${alias}].stockQuantity`] = -line.quantity;

    return {
      [`${alias}._id`]: line.product._id,
      [`${alias}.unlimitedStock`]: false,
      [`${alias}.stockQuantity`]: { $gte: line.quantity }
    };
  });

  return { filter, update: { $inc: set }, arrayFilters };
}

/**
 * The compensating update for a reservation that was taken but whose order
 * could not be persisted.
 *
 * Only finite lines are released, and only by the exact amount reserved, so a
 * release can never invent inventory a merchant did not have.
 */
export function buildStockRelease({ businessId, lines }) {
  const finiteLines = lines.filter((line) => line.finite);

  if (finiteLines.length === 0) {
    return { filter: { _id: businessId }, update: null, arrayFilters: [] };
  }

  const set = {};
  const arrayFilters = finiteLines.map((line, index) => {
    const alias = `line${index}`;
    set[`products.$[${alias}].stockQuantity`] = line.quantity;

    return {
      [`${alias}._id`]: line.product._id,
      [`${alias}.unlimitedStock`]: false
    };
  });

  return {
    filter: { _id: businessId },
    update: { $inc: set },
    arrayFilters
  };
}
