import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { Order } from '../src/models/Order.js';

function validOrder(overrides = {}) {
  const businessId = new mongoose.Types.ObjectId();
  const productId = new mongoose.Types.ObjectId();

  return new Order({
    user: new mongoose.Types.ObjectId(),
    customerName: 'Test Customer',
    customerPhone: '+972590000003',
    business: businessId,
    businessName: 'Merzox Test Business',
    businessAddress: 'Test address',
    items: [
      {
        productId,
        name: 'Test product',
        unitPrice: 35,
        quantity: 1
      }
    ],
    subtotal: 35,
    deliveryFee: 10,
    total: 45,
    deliveryAddress: 'Customer address',
    ...overrides
  });
}

test('order exposes a safe client snapshot', () => {
  const order = validOrder();

  assert.equal(order.validateSync(), undefined);
  assert.match(order.publicId, /^MX-[A-Z0-9]+-[A-F0-9]{8}$/);

  const json = order.toClientJSON();
  assert.equal(json.business.name, 'Merzox Test Business');
  assert.equal(json.items[0].name, 'Test product');
  assert.equal(json.items[0].unitPrice, 35);
  assert.equal(json.total, 45);
  assert.equal(json.statusGroup, 'current');
  assert.equal(json.statusHistory[0].status, 'pending');
});

test('order rejects quantities outside the server limit', () => {
  const order = validOrder();
  order.items[0].quantity = 101;

  const validationError = order.validateSync();
  assert.ok(validationError);
  assert.ok(validationError.errors['items.0.quantity']);
});

test('order exposes customer details only in its merchant view', () => {
  const order = validOrder();

  const client = order.toClientJSON();
  const merchant = order.toMerchantJSON();

  assert.equal(client.customerName, undefined);
  assert.equal(client.customerPhone, undefined);
  assert.equal(merchant.customerName, 'Test Customer');
  assert.equal(merchant.customerPhone, '+972590000003');
  assert.equal(merchant.items[0].name, 'Test product');
});
