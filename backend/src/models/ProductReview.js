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

/**
 * The reviewer's picture, which is not stored here.
 *
 * `userName` is a snapshot taken when the review was written - a name the
 * reader chose to publish under, which should not change under them later. A
 * picture is the opposite: there is one of it per account, it is replaced
 * rather than versioned, and a review showing the picture an account had a
 * year ago beside the picture it has now would look like two people.
 *
 * So it is read through the reference instead, when the caller populated it.
 * An unpopulated `user` is an ObjectId and answers with nothing, which is what
 * every caller that never asked for the picture already drew.
 */
function avatarOf(user) {
  if (!user || typeof user !== 'object') return '';

  return typeof user.avatarUrl === 'string' ? user.avatarUrl : '';
}

productReviewSchema.methods.toJSONView = function toJSONView(
  { avatarUrl } = {}
) {
  return {
    id: this._id.toString(),
    business: this.business.toString(),
    productId: this.productId,
    userName: this.userName,
    // The caller may hand it over directly: the account that just wrote a
    // review is already loaded on the request, and populating it again would
    // be a second read of a document this process is holding.
    userAvatarUrl: typeof avatarUrl === 'string' ? avatarUrl : avatarOf(this.user),
    rating: this.rating,
    comment: this.comment,
    createdAt: this.createdAt
  };
};

export const ProductReview = mongoose.model(
  'ProductReview',
  productReviewSchema
);
