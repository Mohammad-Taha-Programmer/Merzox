import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Business } from '../src/models/Business.js';
import { Message } from '../src/models/Message.js';
import {
  findShareableProduct,
  messageHasContent,
  readSharedProductId,
  SHARED_PRODUCT_CODES,
  sharedProductSnapshot
} from '../src/policies/shared-product.policy.js';
import { validateMessageCreate } from '../src/middleware/validate.js';

/**
 * Sharing a product into a conversation.
 *
 * The rule worth testing is not that a comparison rejects the wrong shop - it
 * is that there is no way to name one. A message carries a product id and
 * nothing else, and the id is looked up inside the shop the conversation
 * already belongs to.
 */

function shopWith(products) {
  return new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-SHARE-0001',
    name: 'متجر',
    category: 'Cosmetics',
    products
  });
}

function reject(handler, body) {
  try {
    handler({ body }, {}, () => {});
    return null;
  } catch (error) {
    return error.code;
  }
}

test('a message may be words, a product, or both - but not neither', () => {
  assert.equal(messageHasContent({ body: 'مرحبا' }), true);
  assert.equal(messageHasContent({ productId: 'p1' }), true);
  assert.equal(messageHasContent({ body: 'مرحبا', productId: 'p1' }), true);

  // A card on its own is a message; two absences are not.
  assert.equal(messageHasContent({ body: '   ' }), false);
  assert.equal(messageHasContent({}), false);
});

test('the door accepts a product id, and only alongside a known field', () => {
  assert.equal(reject(validateMessageCreate, { body: 'مرحبا' }), null);
  assert.equal(reject(validateMessageCreate, { productId: 'p1' }), null);
  assert.equal(
    reject(validateMessageCreate, { body: '', productId: 'p1' }),
    null
  );

  assert.equal(
    reject(validateMessageCreate, {}),
    'INVALID_MESSAGE_BODY'
  );
  assert.equal(
    reject(validateMessageCreate, { body: 'x', businessId: 'other-shop' }),
    'INVALID_MESSAGE_FIELDS'
  );
});

test('a product id that is not one is refused rather than dropped', () => {
  // Silently ignoring it would send a bare message where the reader meant to
  // send a product.
  assert.equal(readSharedProductId({}), null);
  assert.equal(readSharedProductId({ productId: null }), null);
  assert.equal(readSharedProductId({ productId: '  p1  ' }), 'p1');

  for (const value of ['', '   ', 7, {}, []]) {
    assert.equal(
      reject(validateMessageCreate, { productId: value }),
      SHARED_PRODUCT_CODES.invalid,
      `productId ${JSON.stringify(value)} should be refused`
    );
  }
});

test('only the shop the conversation belongs to can be searched', () => {
  const mine = shopWith([
    { name: 'أحمر الشفاه', price: 5, isActive: true },
    { name: 'مزال', price: 8, isActive: false }
  ]);
  const theirs = shopWith([{ name: 'منتج غيري', price: 9, isActive: true }]);

  const listed = mine.products[0];

  assert.equal(findShareableProduct(mine, listed._id.toString()).name, 'أحمر الشفاه');

  // Another shop's product, asked for by its real id. There is no shop
  // parameter to point elsewhere - the handler is given the conversation's
  // shop - so this is what a forged id looks like from in here.
  try {
    findShareableProduct(mine, theirs.products[0]._id.toString());
    assert.fail('a stranger product was accepted');
  } catch (error) {
    assert.equal(error.code, SHARED_PRODUCT_CODES.notFound);
    assert.equal(error.statusCode, 404);
  }

  // Withdrawn is refused too: the card would lead to a page that will not open.
  try {
    findShareableProduct(mine, mine.products[1]._id.toString());
    assert.fail('a withdrawn product was accepted');
  } catch (error) {
    assert.equal(error.code, SHARED_PRODUCT_CODES.notFound);
  }
});

test('the card keeps a copy, priced as the shop prices it today', () => {
  const shop = shopWith([
    {
      name: 'أحمر الشفاه',
      price: 20,
      discountPercent: 25,
      imageUrls: ['https://images.test/lip.png'],
      isActive: true
    }
  ]);
  const product = shop.products[0];

  const snapshot = sharedProductSnapshot(shop, product);

  assert.deepEqual(snapshot, {
    productId: product._id.toString(),
    businessId: shop._id.toString(),
    name: 'أحمر الشفاه',
    // The discounted price, which is what the shop is asking and what every
    // other surface shows. A card quoting 20 beside a page saying 15 would be
    // the app arguing with itself.
    price: 15,
    imageUrl: 'https://images.test/lip.png'
  });
});

test('a shared product travels to the app, and its absence is explicit', () => {
  const shop = shopWith([
    { name: 'أحمر الشفاه', price: 5, isActive: true }
  ]);
  const snapshot = sharedProductSnapshot(shop, shop.products[0]);

  const carried = new Message({
    conversation: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    user: new mongoose.Types.ObjectId(),
    senderType: 'business',
    body: '',
    sharedProduct: snapshot
  });

  assert.equal(carried.validateSync(), undefined);

  const view = carried.toClientJSON('business');
  assert.deepEqual(view.sharedProduct, snapshot);
  // A card without words is a message. The body used to be required, and a
  // schema cannot say "one of these two".
  assert.equal(view.body, '');

  const plain = new Message({
    conversation: new mongoose.Types.ObjectId(),
    business: new mongoose.Types.ObjectId(),
    user: new mongoose.Types.ObjectId(),
    senderType: 'customer',
    body: 'مرحبا'
  });

  assert.equal(plain.toClientJSON('customer').sharedProduct, null);
});
