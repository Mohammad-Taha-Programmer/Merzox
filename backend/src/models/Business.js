import mongoose from 'mongoose';

import {
  RESERVATION_STATES,
  RESERVATION_STATES_LIST
} from '../policies/checkout-intent.policy.js';

import {
  finalPriceFor,
  isProductInStock,
  LEGACY_UNLIMITED_STOCK_DEFAULT,
  PRODUCT_LIMITS
} from '../policies/product.policy.js';

const contactSchema = new mongoose.Schema(
  {
    name: { type: String, trim: true, maxlength: 80 },
    phone: { type: String, trim: true },
    email: { type: String, trim: true, lowercase: true }
  },
  { _id: false }
);

const locationSchema = new mongoose.Schema(
  {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: {
      type: [Number],
      validate: {
        validator(value) {
          return value.length === 2;
        },
        message: 'Location requires [longitude, latitude]'
      }
    }
  },
  { _id: false }
);

const productSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, maxlength: 120 },
    description: { type: String, trim: true, maxlength: 500 },
    price: { type: Number, min: 0 },
    // Merchant-internal margin data. It is never placed on a public serializer
    // - see productToJSON below - so it must not be added there by habit.
    costPrice: { type: Number, min: 0, default: null },
    // Stock is a pair: `unlimitedStock` decides whether `stockQuantity` means
    // anything. There is deliberately no -1 sentinel.
    stockQuantity: {
      type: Number,
      min: 0,
      max: PRODUCT_LIMITS.maxStockQuantity,
      default: 0
    },
    // Defaults to true so products created before inventory existed stay
    // purchasable instead of silently reading as out of stock.
    unlimitedStock: {
      type: Boolean,
      default: LEGACY_UNLIMITED_STOCK_DEFAULT
    },
    // A bounded percentage, never a free-text badge: the final price is derived
    // from it so a discount cannot describe a price the server did not compute.
    discountPercent: { type: Number, min: 0, max: 100, default: 0 },
    keywords: {
      type: [String],
      default: [],
      validate: {
        validator(value) {
          return (
            value.length <= PRODUCT_LIMITS.maxKeywords &&
            value.every(
              (keyword) =>
                typeof keyword === 'string' &&
                keyword.trim().length > 0 &&
                keyword.length <= PRODUCT_LIMITS.keywordMax
            )
          );
        },
        message: 'Product keywords are invalid'
      }
    },
    imageUrl: { type: String, trim: true },
    imageUrls: {
      type: [String],
      default: [],
      validate: {
        validator(value) {
          return value.length <= 8;
        },
        message: 'A product can have up to 8 images'
      }
    },
    classification: {
      type: String,
      enum: ['new', 'bestSelling', 'offers'],
      default: 'new',
      index: true
    },
    ratingAverage: { type: Number, min: 0, max: 5, default: 0 },
    ratingCount: { type: Number, min: 0, default: 0 },
    likeCount: { type: Number, min: 0, default: 0 },
    isService: { type: Boolean, default: false },
    isActive: { type: Boolean, default: true }
  },
  { timestamps: true }
);

const socialLinksSchema = new mongoose.Schema(
  {
    instagram: { type: String, trim: true, maxlength: 200, default: '' },
    whatsapp: { type: String, trim: true, maxlength: 20, default: '' },
    mobile: { type: String, trim: true, maxlength: 20, default: '' },
    facebook: { type: String, trim: true, maxlength: 200, default: '' }
  },
  { _id: false }
);

/**
 * One outstanding reservation, and exactly what it consumed.
 *
 * The consumption lives here rather than only on the CheckoutIntent because
 * this document is written in the SAME atomic update as the decrement. A crash
 * immediately afterwards therefore cannot leave inventory consumed with no
 * durable record of what to give back.
 */
const stockReservationSchema = new mongoose.Schema(
  {
    intent: { type: mongoose.Schema.Types.ObjectId, required: true },
    /**
     * What this entry asserts about its checkout.
     *
     * `reserved` holds stock. `failed` holds nothing: it is the durable record
     * that this checkout's reservation was refused, and it exists so that the
     * refusal and a successful reservation compete for the SAME single-document
     * predicate. Whoever pushes an entry for the intent first wins, and the
     * loser's write matches nothing - which is the only way to make the two
     * outcomes mutually exclusive without a transaction.
     *
     * Absent means `reserved`: entries written before this field existed only
     * ever recorded live reservations.
     */
    state: {
      type: String,
      enum: RESERVATION_STATES_LIST,
      default: RESERVATION_STATES.reserved
    },
    /** Set on a `failed` entry only, so a retry answers the same way. */
    failureCode: { type: String, default: null },
    lines: {
      type: [
        new mongoose.Schema(
          {
            productId: { type: mongoose.Schema.Types.ObjectId, required: true },
            quantity: { type: Number, required: true, min: 1 }
          },
          { _id: false }
        )
      ],
      default: []
    }
  },
  { _id: false }
);

const businessSchema = new mongoose.Schema(
  {
    owner: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    logoUrl: { type: String, trim: true, maxlength: 1000, default: '' },
    socialLinks: { type: socialLinksSchema, default: () => ({}) },
    publicId: { type: String, required: true, unique: true, index: true },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    englishName: { type: String, trim: true, maxlength: 120, default: '' },
    category: { type: String, required: true, trim: true, maxlength: 80 },
    description: { type: String, trim: true, maxlength: 1500, default: '' },
    address: { type: String, trim: true, maxlength: 250, default: '' },
    attachmentUrl: { type: String, trim: true, maxlength: 1000, default: '' },
    location: { type: locationSchema, index: '2dsphere' },
    contacts: { type: [contactSchema], default: [] },
    products: { type: [productSchema], default: [] },

    /**
     * Outstanding stock reservations, by CheckoutIntent id.
     *
     * The marker is added in the same single-document update that decrements
     * the stock, so "inventory was consumed" and "this checkout consumed it"
     * are one atomic fact rather than two writes with a gap between them. A
     * replay of the same reservation is refused because the id is already
     * present, and a release is refused unless it still is - which is what
     * makes both operations idempotent.
     *
     * Entries are removed when the checkout finalizes or releases, so the set
     * only ever holds checkouts that are genuinely in flight. It is internal
     * and appears on no serializer.
     *
     * The array arbitrates the immediate reservation outcome for one checkout.
     * `reservationFence` adds the permanent fence: terminal failure advances
     * this Business-wide generation, so workers authorized under an older
     * generation remain invalid even after their temporary `failed` entry is
     * cleaned up.
     *
     * The generation is one bounded scalar for the whole Business. It does not
     * grow with the number of failed checkouts and is never serialized.
     */
     reservationFence: {
       type: Number,
       default: 0,
       min: 0,
       select: false
     },

    stockReservations: {
      type: [stockReservationSchema],
      default: [],
      select: false
    },

    ratingAverage: { type: Number, min: 0, max: 5, default: 0 },
    ratingCount: { type: Number, min: 0, default: 0 },
    followerCount: { type: Number, min: 0, default: 0 },
    viewCount: { type: Number, min: 0, default: 0 },
    discountLabel: { type: String, trim: true, maxlength: 20 },
    colorValue: { type: Number, default: 0xffdeeef8 },
    isActive: { type: Boolean, default: true },
    subscribedAt: { type: Date, default: Date.now, index: true }
  },
  { timestamps: true }
);

businessSchema.index(
  { owner: 1 },
  { unique: true, sparse: true, name: 'unique_business_owner' }
);

businessSchema.index({
  name: 'text',
  category: 'text',
  'products.name': 'text',
  description: 'text'
});

businessSchema.methods.toListJSON = function toListJSON() {
  const activeProducts = this.products.filter((product) => product.isActive);

  return {
    id: this._id.toString(),
    publicId: this.publicId,
    name: this.name,
    englishName: this.englishName,
    logoUrl: this.logoUrl,
    category: this.category,
    products: activeProducts.slice(0, 6).map((product) => product.name),
    productCount: activeProducts.length,
    rating: this.ratingAverage,
    ratingCount: this.ratingCount,
    followerCount: this.followerCount,
    viewCount: this.viewCount,
    discount: this.discountLabel ?? null,
    colorValue: this.colorValue,
    address: this.address,
    location: this.location ?? null,
    subscribedAt: this.subscribedAt
  };
};

businessSchema.methods.toDetailJSON = function toDetailJSON() {
  return {
    ...this.toListJSON(),
    description: this.description,
    socialLinks: {
      instagram: this.socialLinks?.instagram ?? '',
      whatsapp: this.socialLinks?.whatsapp ?? '',
      mobile: this.socialLinks?.mobile ?? '',
      facebook: this.socialLinks?.facebook ?? ''
    },
    location: this.location ?? null,
    products: this.products
      .filter((product) => product.isActive)
      .map((product) => this.productToJSON(product))
  };
};

businessSchema.methods.toOwnerJSON = function toOwnerJSON() {
  return {
    ...this.toDetailJSON(),
    attachmentUrl: this.attachmentUrl,
    contacts: this.contacts
  };
};

/**
 * The PUBLIC product shape. `costPrice`, exact `stockQuantity`, and `keywords`
 * are intentionally absent: they are merchant-internal, and this serializer is
 * what reaches the catalog, search, favorites, and product detail responses.
 *
 * If a new merchant-only field is added to the schema, it belongs in
 * productToOwnerJSON below - never here.
 */
businessSchema.methods.productToJSON = function productToJSON(product) {
  const imageUrls = Array.from(
    new Set([...(product.imageUrls ?? []), product.imageUrl].filter(Boolean))
  );
  const discountPercent = product.discountPercent ?? 0;

  return {
    discountPercent,
    // Derived here rather than accepted from a client, so a displayed price
    // always follows from the stored base price and discount.
    finalPrice: finalPriceFor({
      price: product.price ?? 0,
      discountPercent
    }),
    inStock: isProductInStock(product),
    id: product._id.toString(),
    business: this._id.toString(),
    name: product.name,
    description: product.description ?? '',
    price: product.price ?? 0,
    imageUrl: imageUrls[0] ?? '',
    imageUrls,
    classification: product.classification ?? 'new',
    rating: product.ratingAverage ?? 0,
    ratingCount: product.ratingCount ?? 0,
    likeCount: product.likeCount ?? 0,
    isService: product.isService,
    isActive: product.isActive,
    createdAt: product.createdAt,
    updatedAt: product.updatedAt
  };
};

/**
 * The MERCHANT-OWNER product shape: everything public, plus the commercial
 * fields only the owning business may see. Reached exclusively through
 * owner-authenticated routes.
 */
businessSchema.methods.productToOwnerJSON = function productToOwnerJSON(
  product
) {
  return {
    ...this.productToJSON(product),
    costPrice: product.costPrice ?? null,
    stockQuantity: product.stockQuantity ?? 0,
    unlimitedStock: product.unlimitedStock ?? LEGACY_UNLIMITED_STOCK_DEFAULT,
    keywords: [...(product.keywords ?? [])]
  };
};

export const Business = mongoose.model('Business', businessSchema);
