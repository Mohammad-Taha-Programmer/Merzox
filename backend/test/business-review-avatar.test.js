import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { BusinessReview } from '../src/models/BusinessReview.js';
import { User } from '../src/models/User.js';

/**
 * The face beside a review of a shop.
 *
 * The same split the product's reviews carry: the name is a snapshot of what
 * the reader chose to publish under, the picture is read through the account,
 * because there is one picture per account and a review showing last year's
 * would look like somebody else.
 *
 * This list has one thing the product's does not - it publishes the reviewer's
 * id - and that is what makes populating it a trap worth a test of its own.
 */

function review({ user } = {}) {
  return new BusinessReview({
    business: new mongoose.Types.ObjectId(),
    user: user ?? new mongoose.Types.ObjectId(),
    userName: 'سلمى حدّاد',
    rating: 4,
    comment: 'خدمة ممتازة وأسعار منافسة.'
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

test('populating the account does not corrupt the id beside it', () => {
  // Populating a reference replaces the id on the path with the document, so
  // `user.toString()` stops being an id the moment somebody asks for the
  // picture - silently, in a field every caller reads as an id.
  const account = new User({
    name: 'سلمى حدّاد',
    avatarUrl: 'https://images.test/salma.png'
  });

  const view = review({ user: account }).toJSONView();

  assert.equal(view.user, account._id.toString());
  assert.ok(mongoose.Types.ObjectId.isValid(view.user));
});

test('a reference nobody populated answers with nothing', () => {
  const author = new mongoose.Types.ObjectId();
  const view = review({ user: author }).toJSONView();

  assert.equal(view.userAvatarUrl, '');
  assert.equal(view.user, author.toString());
});

test('an account with no picture of its own is not a broken link', () => {
  const account = new User({ name: 'رامي عبد الله' });

  assert.equal(review({ user: account }).toJSONView().userAvatarUrl, '');
});

test('the caller may hand the picture over instead', () => {
  const handed = review().toJSONView({
    avatarUrl: 'https://images.test/author.png'
  });

  assert.equal(handed.userAvatarUrl, 'https://images.test/author.png');
});

test('the name is still the one the review was written under', () => {
  const account = new User({
    name: 'سلمى حدّاد الجديدة',
    avatarUrl: 'https://images.test/salma.png'
  });

  assert.equal(review({ user: account }).toJSONView().userName, 'سلمى حدّاد');
});
