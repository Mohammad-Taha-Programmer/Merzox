import mongoose from 'mongoose';

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

const businessSchema = new mongoose.Schema(
  {
    owner: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
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
    category: this.category,
    products: activeProducts.slice(0, 6).map((product) => product.name),
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

businessSchema.methods.productToJSON = function productToJSON(product) {
  const imageUrls = Array.from(
    new Set([...(product.imageUrls ?? []), product.imageUrl].filter(Boolean))
  );

  return {
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

export const Business = mongoose.model('Business', businessSchema);
