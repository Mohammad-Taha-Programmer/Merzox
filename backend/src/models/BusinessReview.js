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

/**
 * The reviewer's account, whether or not the caller populated it.
 *
 * Populating a reference replaces the id on the path with the document, so
 * `this.user.toString()` stops being an id the moment somebody asks for the
 * picture - it becomes a document's own printed form, silently, in a field
 * every caller reads as an id. Both of these read around that: the id comes
 * from `populated`, which keeps the original, and the picture from the
 * document when there is one.
 */
function userIdOf(doc) {
  const value = doc.populated('user') ?? doc.user;

  return value && value._id ? value._id.toString() : String(value);
}

/**
 * The picture is not stored on the review, and deliberately so.
 *
 * `userName` is a snapshot of what the reader chose to publish under and must
 * not change under them later. A picture is the opposite: there is one per
 * account, replaced rather than versioned, and a review showing the picture an
 * account had a year ago beside the picture it has now would look like two
 * people.
 */
function avatarOf(doc, handed) {
  if (typeof handed === 'string') return handed;

  const user = doc.user;
  if (!user || typeof user !== 'object') return '';

  return typeof user.avatarUrl === 'string' ? user.avatarUrl : '';
}

businessReviewSchema.methods.toJSONView = function toJSONView(
  { avatarUrl } = {}
) {
  return {
    id: this._id.toString(),
    business: this.business.toString(),
    user: userIdOf(this),
    userName: this.userName,
    // The caller may hand it over instead: the account that just wrote a
    // review is already loaded on the request, and populating it again would
    // be a second read of a document this process is holding.
    userAvatarUrl: avatarOf(this, avatarUrl),
    rating: this.rating,
    comment: this.comment,
    createdAt: this.createdAt,
    updatedAt: this.updatedAt
  };
};

export const BusinessReview = mongoose.model('BusinessReview', businessReviewSchema);
