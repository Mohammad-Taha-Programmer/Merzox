/**
 * The canonical merchant product contract.
 *
 * One module owns the field list, the normalization, and the derived pricing so
 * the validator, the controller, and the model cannot drift apart. Every rule
 * here is about a field a merchant may actually write; anything server-owned
 * (identity, ratings, likes, timestamps) is deliberately absent.
 */

/** Fields a merchant may send on create or update. Nothing else is accepted. */
export const merchantWritableProductFields = [
  'name',
  'description',
  'price',
  'costPrice',
  'stockQuantity',
  'unlimitedStock',
  'discountPercent',
  'keywords',
  'imageUrl',
  'imageUrls',
  'classification',
  'isService',
  'isActive'
];

export const productClassifications = ['new', 'bestSelling', 'offers'];

export const PRODUCT_LIMITS = {
  nameMin: 2,
  nameMax: 120,
  descriptionMax: 500,
  imageUrlMax: 1000,
  maxImages: 8,
  maxKeywords: 20,
  keywordMax: 40,
  maxStockQuantity: 1000000,
  maxPrice: 10000000
};

/**
 * Legacy compatibility, and the single most consequential default in FIX4.
 *
 * Products created before inventory existed carry no stock fields at all. If
 * they defaulted to a finite stock of zero every historical product would read
 * as out of stock and the existing catalog would stop being purchasable. They
 * are therefore treated as unlimited until a merchant explicitly says otherwise
 * - which is exactly the behaviour those documents already had.
 */
export const LEGACY_UNLIMITED_STOCK_DEFAULT = true;

function finiteNumber(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/** Rounds money to two decimals without accumulating float error. */
export function roundMoney(value) {
  return Math.round((finiteNumber(value) ?? 0) * 100) / 100;
}

/**
 * The price a customer actually pays. Derived on the server from the stored
 * base price and discount so a client can never submit an authoritative
 * final/sale price of its own.
 */
export function finalPriceFor({ price, discountPercent }) {
  const base = Math.max(0, finiteNumber(price) ?? 0);
  const percent = clampDiscountPercent(discountPercent);

  if (percent === 0) return roundMoney(base);

  return roundMoney(base * (1 - percent / 100));
}

export function clampDiscountPercent(value) {
  const parsed = finiteNumber(value);
  if (parsed === null) return 0;

  return Math.min(100, Math.max(0, parsed));
}

/**
 * Whether the product can currently be bought. Unlimited stock is always in
 * stock; a finite one needs a positive quantity. Legacy documents with neither
 * field fall back to the unlimited default above.
 */
export function isProductInStock(product) {
  const unlimited = product?.unlimitedStock;

  if (unlimited === undefined || unlimited === null) {
    return LEGACY_UNLIMITED_STOCK_DEFAULT;
  }
  if (unlimited === true) return true;

  return (finiteNumber(product?.stockQuantity) ?? 0) > 0;
}

/**
 * Normalizes keywords: trimmed, blanks dropped, case-insensitively deduplicated
 * while keeping the merchant's original casing and ordering for the first
 * occurrence. Returns null when the input is not an array of strings so the
 * validator can reject it rather than silently repairing it.
 */
export function normalizeKeywords(value) {
  if (value === undefined) return undefined;
  if (!Array.isArray(value)) return null;
  if (value.some((entry) => typeof entry !== 'string')) return null;

  const seen = new Set();
  const normalized = [];

  for (const entry of value) {
    const trimmed = entry.trim();
    if (trimmed.length === 0) continue;
    if (trimmed.length > PRODUCT_LIMITS.keywordMax) return null;

    const key = trimmed.toLocaleLowerCase();
    if (seen.has(key)) continue;

    seen.add(key);
    normalized.push(trimmed);
  }

  if (normalized.length > PRODUCT_LIMITS.maxKeywords) return null;

  return normalized;
}

/**
 * Resolves the stock pair into a state that cannot contradict itself.
 *
 * `unlimitedStock: true` makes any quantity meaningless, so it is stored as
 * zero rather than left as a stale number that a later toggle would resurrect.
 * `-1` is never used as an "unlimited" sentinel.
 */
export function normalizeStock({ unlimitedStock, stockQuantity }, current = {}) {
  const resolvedUnlimited =
    unlimitedStock === undefined
      ? current.unlimitedStock ?? LEGACY_UNLIMITED_STOCK_DEFAULT
      : unlimitedStock === true;

  if (resolvedUnlimited) {
    return { unlimitedStock: true, stockQuantity: 0 };
  }

  const resolvedQuantity =
    stockQuantity === undefined
      ? finiteNumber(current.stockQuantity) ?? 0
      : finiteNumber(stockQuantity) ?? 0;

  return {
    unlimitedStock: false,
    stockQuantity: Math.max(0, Math.trunc(resolvedQuantity))
  };
}

/**
 * Builds the exact set of fields to persist from an already-validated payload.
 *
 * This is the only place a merchant payload becomes product state; the caller
 * never assigns `req.body` to a document. Fields absent from a partial update
 * are simply not returned, so the stored value survives.
 */
export function buildProductWrite(body, current = {}) {
  const write = {};

  if (body.name !== undefined) write.name = String(body.name).trim();
  if (body.description !== undefined) {
    write.description = String(body.description).trim();
  }
  if (body.price !== undefined) write.price = roundMoney(body.price);
  if (body.costPrice !== undefined) {
    write.costPrice =
      body.costPrice === null || body.costPrice === ''
        ? null
        : roundMoney(body.costPrice);
  }
  if (body.discountPercent !== undefined) {
    write.discountPercent = clampDiscountPercent(body.discountPercent);
  }
  if (body.keywords !== undefined) {
    write.keywords = normalizeKeywords(body.keywords) ?? [];
  }
  if (body.imageUrl !== undefined) write.imageUrl = String(body.imageUrl).trim();
  if (body.imageUrls !== undefined) {
    write.imageUrls = body.imageUrls
      .map((url) => String(url).trim())
      .filter((url) => url.length > 0);
  }
  if (body.classification !== undefined) {
    write.classification = body.classification;
  }
  if (body.isService !== undefined) write.isService = body.isService === true;
  if (body.isActive !== undefined) write.isActive = body.isActive === true;

  // Stock is resolved as a pair so the two fields can never disagree, and only
  // when the payload actually mentions one of them.
  if (body.unlimitedStock !== undefined || body.stockQuantity !== undefined) {
    Object.assign(
      write,
      normalizeStock(
        {
          unlimitedStock: body.unlimitedStock,
          stockQuantity: body.stockQuantity
        },
        current
      )
    );
  }

  return write;
}
