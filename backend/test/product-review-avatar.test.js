import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { ProductReview } from '../src/models/ProductReview.js';
import { User } from '../src/models/User.js';

/**
 * The face beside a review.
 *
 * A review stores the name it was written under and nothing else, so the app
 * drew a blank disc beside every one of them and each reviewer looked like the
 * same anonymous person. The name stays a snapshot - it is what the reader
 * chose to publish under - but the picture is read through the account, since
 * there is one picture per account and a review showing last year's would look
 * like somebody else.
 */

function review({ user } = {}) {
  return new ProductReview({
    business: new mongoose.Types.ObjectId(),
    productId: new mongoose.Types.ObjectId().toString(),
    user: user ?? new mongoose.Types.ObjectId(),
    userName: 'سلمى حدّاد',
    rating: 4,
    comment: 'وصل سريعاً والتغليف ممتاز.'
  });
}

test('a populated account lends its picture', () => {
  const account = new User({
    name: 'سلمى حدّاد',
    avatarUrl: 'https://images.test/salma.png'
  });

  assert.equal(
    review({ user: account }).toJSONView().userAvatarUrl,
    'https://images.test/salma.png'
  );
});

test('a reference nobody populated answers with nothing', () => {
  // Every caller that never asked for the picture keeps drawing the figure,
  // rather than reading `avatarUrl` off an ObjectId and sending `undefined`.
  assert.equal(review().toJSONView().userAvatarUrl, '');
});

test('an account with no picture of its own is not a broken link', () => {
  const account = new User({ name: 'رامي عبد الله' });

  assert.equal(review({ user: account }).toJSONView().userAvatarUrl, '');
});

test('the caller may hand the picture over instead', () => {
  // Which is what the route that writes a review does: the account is already
  // loaded on the request, so populating it again would be a second read of a
  // document this process is holding.
  const handed = review().toJSONView({
    avatarUrl: 'https://images.test/author.png'
  });

  assert.equal(handed.userAvatarUrl, 'https://images.test/author.png');
});

test('the name is still the one the review was written under', () => {
  // The whole point of the split: the picture follows the account and the
  // name does not.
  const account = new User({
    name: 'سلمى حدّاد الجديدة',
    avatarUrl: 'https://images.test/salma.png'
  });

  assert.equal(review({ user: account }).toJSONView().userName, 'سلمى حدّاد');
});
