import mongoose from 'mongoose';

const productReviewSchema = new mongoose.Schema(
  {
    business: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true
    },
    productId: { type: String, required: true, trim: true, index: true },
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true
    },
    userName: { type: String, required: true, trim: true, maxlength: 80 },
    rating: { type: Number, required: true, min: 1, max: 5 },
    comment: { type: String, trim: true, maxlength: 750, default: '' }
  },
  { timestamps: true }
);

productReviewSchema.index(
  { business: 1, productId: 1, user: 1 },
  { unique: true }
);

productReviewSchema.methods.toJSONView = function toJSONView() {
  return {
    id: this._id.toString(),
    business: this.business.toString(),
    productId: this.productId,
    userName: this.userName,
    rating: this.rating,
    comment: this.comment,
    createdAt: this.createdAt
  };
};

export const ProductReview = mongoose.model(
  'ProductReview',
  productReviewSchema
);
