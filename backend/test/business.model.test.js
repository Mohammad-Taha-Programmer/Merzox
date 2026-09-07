import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Business } from '../src/models/Business.js';

test('business keeps merchant registration fields private and filters inactive products', () => {
  const business = new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-TEST-0001',
    name: 'متجر الاختبار',
    englishName: 'Test Store',
    category: 'Groceries',
    description: 'Test description',
    address: 'Test address',
    attachmentUrl: 'https://example.test/document.pdf',
    products: [
      {
        name: 'Test product',
        price: 12,
        isActive: false
      }
    ]
  });

  assert.equal(business.validateSync(), undefined);

  const detail = business.toDetailJSON();
  const owner = business.toOwnerJSON();
  const product = business.productToJSON(business.products[0]);
  assert.equal(detail.englishName, 'Test Store');
  assert.equal(detail.attachmentUrl, undefined);
  assert.equal(detail.contacts, undefined);
  assert.deepEqual(detail.products, []);
  assert.equal(detail.productCount, 0);
  assert.equal(owner.attachmentUrl, 'https://example.test/document.pdf');
  assert.equal(detail.viewCount, 0);
  assert.equal(product.isActive, false);
});

test('a shop keeps its own ways of being reached, not the owner number', () => {
  // `socialLinks.mobile` was a plain phone number on the shop. The one a shop
  // would print is the owner's, which the account holds already, so this was
  // a third copy of it - and the screen that collected it asked for the same
  // number a third time.
  assert.equal(Business.schema.path('socialLinks.mobile'), undefined);
  assert.ok(Business.schema.path('socialLinks.whatsapp'));

  const business = new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-TEST-0003',
    name: 'متجر',
    category: 'Groceries',
    socialLinks: { whatsapp: '+970599000000', mobile: '+970599000000' }
  });

  assert.equal(business.socialLinks.mobile, undefined);
  assert.equal(business.socialLinks.whatsapp, '+970599000000');
  assert.equal(business.toDetailJSON().socialLinks.mobile, undefined);
  assert.equal(business.toDetailJSON().socialLinks.whatsapp, '+970599000000');
});

test('a shop carries no copy of the person who owns it', () => {
  // It used to. `contacts` was a name, a phone and an email taken from the
  // owner at enrolment and never written again, so the day they changed
  // either one the shop still held the old value - and nothing in the app
  // ever read it. Those details belong to the account, which is where they
  // are edited and where every screen reads them.
  assert.equal(Business.schema.path('contacts'), undefined);

  const business = new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-TEST-0002',
    name: 'متجر بلا نسخة',
    category: 'Groceries',
    contacts: [{ name: 'someone', phone: '+970599000000', email: 'a@b.test' }]
  });

  // Handed one anyway, it keeps nothing: the field is gone from the schema,
  // so there is no half-alive copy to drift.
  assert.equal(business.get('contacts'), undefined);
  assert.equal(business.toOwnerJSON().contacts, undefined);
  assert.equal(business.toDetailJSON().contacts, undefined);
});
