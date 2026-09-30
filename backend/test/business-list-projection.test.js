import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import {
  Business,
  BUSINESS_LIST_FIELDS,
  BUSINESS_LIST_PROJECTION,
  businessListJSON
} from '../src/models/Business.js';

/**
 * What a listed shop costs to read.
 *
 * A shop document is mostly its goods - every product's description, price,
 * pictures, variants and stock - and a listed shop is a name, a logo and six
 * product names. The catalogue used to read the whole document and hydrate it
 * into a Mongoose object, then throw nine tenths of it away before writing the
 * response: on the home screen's own data, 109KB out of the database to write
 * 7.5KB to the app, and two and a half times the time at fifty shops a page.
 *
 * The projection is what fixes that, and the only way it can be wrong is by
 * being short of a field the view reads - which would show up as a null in the
 * app and nowhere else. That is what the first test below is for.
 */

function shop() {
  return new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: '93872',
    name: 'البتول كوزماتيكس',
    englishName: 'Batool Cosmatics',
    logoUrl: 'https://images.test/logo.png',
    category: 'مستحضرات تجميل',
    address: 'سرطة سلفيت',
    location: { type: 'Point', coordinates: [35.2, 32.1] },
    ratingAverage: 4.5,
    ratingCount: 12,
    followerCount: 30,
    viewCount: 113,
    discountLabel: '20%',
    colorValue: 4292800248,
    subscribedAt: new Date('2026-09-04T17:18:57.094Z'),
    products: [
      {
        name: 'مسكارا',
        description: 'وصف طويل لا يظهر في القائمة',
        price: 7.5,
        isActive: true,
        images: ['https://images.test/one.png']
      },
      {
        name: 'أحمر شفاه',
        description: 'وصف آخر',
        price: 12,
        isActive: true,
        images: []
      },
      { name: 'منتج موقوف', price: 1, isActive: false }
    ]
  });
}

/**
 * As it reaches the app.
 *
 * A hydrated `location` is a subdocument and a lean one is a plain object, so
 * the two are not the same object to `deepEqual` while being the same three
 * lines of JSON. The response is what is being compared, so it is the response
 * shape that is compared.
 */
function asSent(view) {
  return JSON.parse(JSON.stringify(view));
}

/** What the database would hand back for [BUSINESS_LIST_PROJECTION]. */
function asProjected(business) {
  const whole = business.toObject();
  const projected = { _id: whole._id };

  for (const field of BUSINESS_LIST_FIELDS) projected[field] = whole[field];

  projected.products = whole.products.map((product) => ({
    name: product.name,
    isActive: product.isActive
  }));

  return projected;
}

test('the projection carries every field the listed shape reads', () => {
  // The failure this guards against is silent: a field added to the shape and
  // not to the projection reads as null in the app, with nothing on the server
  // to say so.
  const business = shop();

  assert.deepEqual(
    asSent(businessListJSON(asProjected(business))),
    asSent(business.toListJSON())
  );
});

test('a document and a plain object give the same answer', () => {
  // Which is the whole reason the view is a function rather than only a
  // method: the fast read is `lean()`, and hydrating each plain object back
  // into a document to call a method on it would give the time straight back.
  const business = shop();

  assert.deepEqual(
    asSent(businessListJSON(business)),
    asSent(business.toListJSON())
  );
});

test('the projection asks for no product field the shape does not read', () => {
  // The goods are nine tenths of the document. Anything asked for here is
  // carried for every shop on every page of the catalogue.
  const productFields = Object.keys(BUSINESS_LIST_PROJECTION).filter((key) =>
    key.startsWith('products.')
  );

  assert.deepEqual(productFields.sort(), ['products.isActive', 'products.name']);
});

test('the projection is the list of fields, kept in step with it', () => {
  for (const field of BUSINESS_LIST_FIELDS) {
    assert.equal(
      BUSINESS_LIST_PROJECTION[field],
      1,
      `${field} is read by the listed shape but not asked for`
    );
  }
});

test('a shop with no goods lists as a shop with no goods', () => {
  const business = shop();
  business.products = [];

  const view = businessListJSON(asProjected(business));

  assert.deepEqual(view.products, []);
  assert.equal(view.productCount, 0);
});

test('only the shop’s live goods are counted', () => {
  const view = businessListJSON(asProjected(shop()));

  assert.deepEqual(view.products, ['مسكارا', 'أحمر شفاه']);
  assert.equal(view.productCount, 2);
});
