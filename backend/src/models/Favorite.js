import mongoose from 'mongoose';

const favoriteSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    itemType: {
      type: String,
      enum: ['business', 'product'],
      required: true,
      index: true
    },
    business: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true
    },
    productId: {
      type: mongoose.Schema.Types.ObjectId,
      default: null
    }
  },
  { timestamps: true }
);

favoriteSchema.pre('validate', function validateFavorite(next) {
  if (this.itemType === 'product' && !this.productId) {
    this.invalidate('productId', 'Product favorites require a product id');
  }

  if (this.itemType === 'business') {
    this.productId = null;
  }

  next();
});

favoriteSchema.index(
  { user: 1, business: 1 },
  {
    unique: true,
    partialFilterExpression: { itemType: 'business' },
    name: 'unique_business_favorite_per_user'
  }
);

favoriteSchema.index(
  { user: 1, business: 1, productId: 1 },
  {
    unique: true,
    partialFilterExpression: { itemType: 'product' },
    name: 'unique_product_favorite_per_user'
  }
);

favoriteSchema.index({ user: 1, itemType: 1, createdAt: -1 });

export const Favorite = mongoose.model('Favorite', favoriteSchema);
