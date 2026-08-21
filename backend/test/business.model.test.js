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
  assert.equal(owner.attachmentUrl, 'https://example.test/document.pdf');
  assert.equal(detail.viewCount, 0);
  assert.equal(product.isActive, false);
});
