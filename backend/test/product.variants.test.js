import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import {
  validateBusinessProductCreate,
  validateBusinessProductPatch
} from '../src/middleware/validate.js';
import { Business } from '../src/models/Business.js';
import {
  buildProductWrite,
  PRODUCT_VARIANT_ERRORS,
  productVariantSummary
} from '../src/policies/product.policy.js';

function businessWithProduct(product) {
  return new Business({
    owner: new mongoose.Types.ObjectId(),
    publicId: 'MXB-VARIANT-TEST',
    name: 'Variant Test Store',
    category: 'Retail',
    products: [product]
  });
}

function validateCreate(body) {
  let called = false;

  validateBusinessProductCreate(
    { body },
    undefined,
    () => {
      called = true;
    }
  );

  assert.equal(called, true);
}

function validatePatch(body) {
  let called = false;

  validateBusinessProductPatch(
    { body },
    undefined,
    () => {
      called = true;
    }
  );

  assert.equal(called, true);
}

test('V01 - variants get server identities and public facts hide private inventory', () => {
  const business = businessWithProduct({
    name: 'Variant Shirt',
    price: 100,
    discountPercent: 10,
    unlimitedStock: true,
    variants: [
      {
        label: 'Black / M',
        priceOverride: 120,
        costPrice: 50,
        unlimitedStock: false,
        stockQuantity: 3,
        isActive: true
      },
      {
        label: 'White / M',
        costPrice: 40,
        unlimitedStock: false,
        stockQuantity: 0,
        isActive: true
      },
      {
        label: 'Hidden / XL',
        priceOverride: 80,
        costPrice: 20,
        unlimitedStock: false,
        stockQuantity: 9,
        isActive: false
      }
    ]
  });

  assert.equal(business.validateSync(), undefined);

  const product = business.products[0];
  const firstId = String(product.variants[0]._id);

  assert.match(firstId, /^[a-f\d]{24}$/i);

  const publicProduct = business.productToJSON(product);

  assert.equal(publicProduct.hasVariants, true);
  assert.equal(publicProduct.variants.length, 2);
  assert.equal(publicProduct.inStock, true);
  assert.equal(publicProduct.minPrice, 100);
  assert.equal(publicProduct.maxPrice, 120);
  assert.equal(publicProduct.minFinalPrice, 90);
  assert.equal(publicProduct.maxFinalPrice, 108);

  const black = publicProduct.variants.find(
    (variant) => variant.label === 'Black / M'
  );
  const white = publicProduct.variants.find(
    (variant) => variant.label === 'White / M'
  );

  assert.ok(black);
  assert.ok(white);

  assert.equal(black.id, firstId);
  assert.equal(black.price, 120);
  assert.equal(black.finalPrice, 108);
  assert.equal(black.inStock, true);

  assert.equal(white.price, 100);
  assert.equal(white.finalPrice, 90);
  assert.equal(white.inStock, false);

  for (const variant of publicProduct.variants) {
    assert.equal(Object.hasOwn(variant, 'costPrice'), false);
    assert.equal(Object.hasOwn(variant, 'stockQuantity'), false);
    assert.equal(Object.hasOwn(variant, 'unlimitedStock'), false);
  }

  const ownerProduct = business.productToOwnerJSON(product);
  assert.equal(ownerProduct.variants.length, 3);

  const ownerBlack = ownerProduct.variants.find(
    (variant) => variant.id === firstId
  );

  assert.ok(ownerBlack);
  assert.equal(ownerBlack.costPrice, 50);
  assert.equal(ownerBlack.stockQuantity, 3);
  assert.equal(ownerBlack.unlimitedStock, false);
  assert.equal(ownerBlack.priceOverride, 120);

  assert.equal(
    business.productToJSON(product).variants[0].id,
    firstId
  );
});

test('V01B - null inherits parent price while explicit zero remains a real override', () => {
  const business = businessWithProduct({
    name: 'Price Semantics',
    price: 80,
    discountPercent: 25,
    variants: [
      {
        label: 'Inherited',
        priceOverride: null,
        unlimitedStock: true
      },
      {
        label: 'Free',
        priceOverride: 0,
        unlimitedStock: true
      }
    ]
  });

  const product = business.products[0];
  const publicProduct = business.productToJSON(product);

  const inherited = publicProduct.variants.find(
    (variant) => variant.label === 'Inherited'
  );
  const free = publicProduct.variants.find(
    (variant) => variant.label === 'Free'
  );

  assert.ok(inherited);
  assert.ok(free);

  assert.equal(inherited.price, 80);
  assert.equal(inherited.finalPrice, 60);

  // Zero is intentionally different from null: it is an explicit merchant
  // price override and must never be mistaken for inheritance.
  assert.equal(free.price, 0);
  assert.equal(free.finalPrice, 0);
});

test('V02 - variant product never falls back to parent inventory', () => {
  const business = businessWithProduct({
    name: 'Unavailable Variant Product',
    price: 75,
    unlimitedStock: true,
    variants: [
      {
        label: 'Sold out',
        unlimitedStock: false,
        stockQuantity: 0,
        isActive: true
      },
      {
        label: 'Inactive but stocked',
        unlimitedStock: false,
        stockQuantity: 10,
        isActive: false
      }
    ]
  });

  const product = business.products[0];
  const summary = productVariantSummary(product);
  const publicProduct = business.productToJSON(product);

  assert.equal(summary.hasVariants, true);
  assert.equal(summary.variants.length, 1);
  assert.equal(summary.inStock, false);
  assert.equal(publicProduct.inStock, false);
});

test('V03 - legacy simple product keeps parent price and stock semantics', () => {
  const business = businessWithProduct({
    name: 'Simple Product',
    price: 50,
    discountPercent: 10,
    unlimitedStock: false,
    stockQuantity: 2
  });

  const product = business.products[0];
  const publicProduct = business.productToJSON(product);

  assert.equal(publicProduct.hasVariants, false);
  assert.deepEqual(publicProduct.variants, []);
  assert.equal(publicProduct.inStock, true);
  assert.equal(publicProduct.minPrice, 50);
  assert.equal(publicProduct.maxPrice, 50);
  assert.equal(publicProduct.minFinalPrice, 45);
  assert.equal(publicProduct.maxFinalPrice, 45);
});

test('V04 - merchant variant validation accepts only bounded truthful payloads', () => {
  const valid = {
    name: 'Variant Product',
    price: 100,
    variants: [
      {
        label: 'Black / M',
        priceOverride: 120,
        costPrice: 60,
        unlimitedStock: false,
        stockQuantity: 4,
        isActive: true
      }
    ]
  };

  validateCreate(valid);

  assert.throws(
    () =>
      validateCreate({
        ...valid,
        variants: [
          {
            ...valid.variants[0],
            id: new mongoose.Types.ObjectId().toString()
          }
        ]
      }),
    (error) => error.code === 'INVALID_PRODUCT_VARIANT_ID'
  );

  assert.throws(
    () =>
      validateCreate({
        ...valid,
        variants: [
          { label: 'Black / M', unlimitedStock: true },
          { label: 'black / m', unlimitedStock: true }
        ]
      }),
    (error) => error.code === 'INVALID_PRODUCT_VARIANT_LABEL'
  );

  assert.throws(
    () =>
      validateCreate({
        ...valid,
        variants: [
          {
            label: 'Black / M',
            unlimitedStock: true,
            serverPrice: 1
          }
        ]
      }),
    (error) => error.code === 'INVALID_PRODUCT_VARIANT_FIELDS'
  );

  assert.throws(
    () =>
      validateCreate({
        ...valid,
        variants: [
          {
            label: 'Black / M',
            unlimitedStock: false,
            stockQuantity: -1
          }
        ]
      }),
    (error) => error.code === 'INVALID_PRODUCT_VARIANT_STOCK'
  );

  assert.throws(
    () =>
      validateCreate({
        ...valid,
        variants: [
          {
            label: 'Missing stock mode',
            stockQuantity: 5
          }
        ]
      }),
    (error) => error.code === 'INVALID_PRODUCT_VARIANT_STOCK_MODE'
  );

  validatePatch({
    variants: [
      {
        id: new mongoose.Types.ObjectId().toString(),
        label: 'Black / M',
        unlimitedStock: true
      }
    ]
  });
});

test('V05 - writes preserve only variant identities already owned by product', () => {
  const business = businessWithProduct({
    name: 'Identity Product',
    price: 100,
    variants: [
      {
        label: 'Black / M',
        priceOverride: 110,
        unlimitedStock: false,
        stockQuantity: 5
      }
    ]
  });

  const product = business.products[0];
  const existing = product.variants[0];
  const existingId = String(existing._id);

  const write = buildProductWrite(
    {
      variants: [
        {
          id: existingId,
          label: 'Black / L',
          priceOverride: 125,
          costPrice: null,
          unlimitedStock: false,
          stockQuantity: 2,
          isActive: true
        },
        {
          label: 'White / M',
          unlimitedStock: true,
          isActive: true
        }
      ]
    },
    {
      variants: product.variants,
      unlimitedStock: product.unlimitedStock,
      stockQuantity: product.stockQuantity
    }
  );

  assert.equal(String(write.variants[0]._id), existingId);
  assert.equal(write.variants[0].label, 'Black / L');
  assert.equal(write.variants[0].priceOverride, 125);
  assert.equal(write.variants[0].stockQuantity, 2);
  assert.equal(write.variants[0].unlimitedStock, false);

  assert.equal(Object.hasOwn(write.variants[1], '_id'), false);

  const foreignId = new mongoose.Types.ObjectId().toString();

  assert.throws(
    () =>
      buildProductWrite(
        {
          variants: [
            {
              id: foreignId,
              label: 'Invented identity',
              unlimitedStock: true
            }
          ]
        },
        { variants: product.variants }
      ),
    (error) => error.code === PRODUCT_VARIANT_ERRORS.unknownId
  );
});
