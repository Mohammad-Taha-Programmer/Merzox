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
  'variants',
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
  maxVariants: 50,
  variantLabelMax: 80,
  maxStockQuantity: 1000000,
  maxPrice: 10000000
};

export const PRODUCT_VARIANT_ERRORS = {
  unknownId: 'INVALID_PRODUCT_VARIANT_ID'
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
 * A product enters variant mode as soon as it owns at least one variant.
 *
 * Inactive variants still keep the product in variant mode. If all variants
 * become inactive, the parent stock must never silently become sellable.
 */
export function hasProductVariants(product) {
  return Array.isArray(product?.variants) && product.variants.length > 0;
}

/** The effective list price represented by this exact variant. */
export function variantListPriceFor(product, variant) {
  const rawOverride = variant?.priceOverride;

  // `null` means inherit the product price. It must be handled before
  // `finiteNumber`, because JavaScript's Number(null) is 0 and would otherwise
  // turn an inherited price into an invented free variant.
  const override =
    rawOverride === null || rawOverride === undefined || rawOverride === ''
      ? null
      : finiteNumber(rawOverride);

  return roundMoney(
    override === null ? product?.price ?? 0 : Math.max(0, override)
  );
}

/** Product discount remains server-owned and applies to the variant price. */
export function variantFinalPriceFor(product, variant) {
  return finalPriceFor({
    price: variantListPriceFor(product, variant),
    discountPercent: product?.discountPercent ?? 0
  });
}

/**
 * Customer-visible truth for one variant.
 *
 * Cost and exact stock deliberately remain private.
 */
export function variantCommerceFacts(product, variant) {
  const identity = variant?._id ?? variant?.id;

  return {
    id: identity ? String(identity) : '',
    label: String(variant?.label ?? '').trim(),
    price: variantListPriceFor(product, variant),
    finalPrice: variantFinalPriceFor(product, variant),
    inStock: isProductInStock(variant)
  };
}

/**
 * Product-level public commerce summary.
 *
 * Simple products retain their existing parent price and inventory semantics.
 * Variant products derive availability and price ranges only from active
 * variants.
 */
export function productVariantSummary(product) {
  const basePrice = roundMoney(product?.price ?? 0);
  const baseFinalPrice = finalPriceFor({
    price: basePrice,
    discountPercent: product?.discountPercent ?? 0
  });

  if (!hasProductVariants(product)) {
    return {
      hasVariants: false,
      variants: [],
      inStock: isProductInStock(product),
      minPrice: basePrice,
      maxPrice: basePrice,
      minFinalPrice: baseFinalPrice,
      maxFinalPrice: baseFinalPrice
    };
  }

  const variants = (product.variants ?? [])
    .filter((variant) => variant?.isActive !== false)
    .map((variant) => variantCommerceFacts(product, variant));

  if (variants.length === 0) {
    return {
      hasVariants: true,
      variants: [],
      inStock: false,
      minPrice: null,
      maxPrice: null,
      minFinalPrice: null,
      maxFinalPrice: null
    };
  }

  const prices = variants.map((variant) => variant.price);
  const finalPrices = variants.map((variant) => variant.finalPrice);

  return {
    hasVariants: true,
    variants,
    inStock: variants.some((variant) => variant.inStock),
    minPrice: Math.min(...prices),
    maxPrice: Math.max(...prices),
    minFinalPrice: Math.min(...finalPrices),
    maxFinalPrice: Math.max(...finalPrices)
  };
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
 * Converts a merchant variant array into persistent variant state.
 *
 * Existing ids may only preserve ids already owned by this exact product.
 * New variants carry no id here; Mongoose owns generation of their identities.
 */
export function normalizeVariants(variants, currentVariants = []) {
  if (variants === undefined) return undefined;

  const currentById = new Map(
    (currentVariants ?? [])
      .filter((variant) => variant?._id)
      .map((variant) => [String(variant._id), variant])
  );

  return variants.map((variant) => {
    const id = String(variant?.id ?? '').trim();
    const current = id ? currentById.get(id) : undefined;

    if (id && !current) {
      const error = new Error('Product variant id is invalid');
      error.code = PRODUCT_VARIANT_ERRORS.unknownId;
      throw error;
    }

    const priceOverride =
      variant.priceOverride === undefined
        ? current?.priceOverride ?? null
        : variant.priceOverride === null || variant.priceOverride === ''
          ? null
          : roundMoney(variant.priceOverride);

    const costPrice =
      variant.costPrice === undefined
        ? current?.costPrice ?? null
        : variant.costPrice === null || variant.costPrice === ''
          ? null
          : roundMoney(variant.costPrice);

    const stock = normalizeStock(
      {
        unlimitedStock: variant.unlimitedStock,
        stockQuantity: variant.stockQuantity
      },
      current ?? {}
    );

    return {
      ...(current?._id ? { _id: current._id } : {}),
      label: String(variant.label ?? '').trim(),
      priceOverride,
      costPrice,
      ...stock,
      isActive:
        variant.isActive === undefined
          ? current?.isActive ?? true
          : variant.isActive === true
    };
  });
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
  if (body.variants !== undefined) {
    write.variants = normalizeVariants(body.variants, current.variants ?? []);
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
