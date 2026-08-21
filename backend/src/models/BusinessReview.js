import mongoose from 'mongoose';

const businessReviewSchema = new mongoose.Schema(
  {
    business: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Business',
      required: true,
      index: true
    },
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

businessReviewSchema.index({ business: 1, user: 1 }, { unique: true });

businessReviewSchema.methods.toJSONView = function toJSONView() {
  return {
    id: this._id.toString(),
    business: this.business.toString(),
    user: this.user.toString(),
    userName: this.userName,
    rating: this.rating,
    comment: this.comment,
    createdAt: this.createdAt,
    updatedAt: this.updatedAt
  };
};

export const BusinessReview = mongoose.model('BusinessReview', businessReviewSchema);
