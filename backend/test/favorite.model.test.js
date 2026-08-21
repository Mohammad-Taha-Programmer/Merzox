import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Favorite } from '../src/models/Favorite.js';

test('product favorite requires a product id', async () => {
  const favorite = new Favorite({
    user: new mongoose.Types.ObjectId(),
    itemType: 'product',
    business: new mongoose.Types.ObjectId()
  });

  await assert.rejects(favorite.validate(), /Product favorites require/);
});

test('business favorite never stores a product id', async () => {
  const favorite = new Favorite({
    user: new mongoose.Types.ObjectId(),
    itemType: 'business',
    business: new mongoose.Types.ObjectId(),
    productId: new mongoose.Types.ObjectId()
  });

  await favorite.validate();
  assert.equal(favorite.productId, null);
});
