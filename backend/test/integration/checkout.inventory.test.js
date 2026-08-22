import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { fixtureId, resolveIntegrationEnvironment } from './test-environment.js';

/**
 * MERZOX-GAP-002 inventory truth, against a real database.
 *
 * The unit suite proves the reservation QUERY SHAPE is all-or-nothing. Only a
 * real server can prove the driver honours it, so the three claims that depend
 * on genuine concurrency and persistence live here:
 *
 *   - two simultaneous checkouts for the final unit: exactly one succeeds
 *   - a successful purchase consumes finite stock exactly once
 *   - a retry with the same clientOrderId returns the first order and consumes
 *     nothing further
 *
 * It runs ONLY against an explicitly declared disposable database - see
 * `test-environment.js`. When that is absent it reports a SKIP naming the
 * missing prerequisite; it never falls back to the application database, and it
 * never reads MONGODB_URI as a substitute.
 *
 * Required environment:
 *   MERZOX_INTEGRATION_TESTS=true
 *   MERZOX_TEST_API_URL=http://localhost:4100/api/v1
 *   MERZOX_TEST_DB_URI=mongodb://127.0.0.1:27017/merzox_test
 *
 * The operator must start that API against the same test database:
 *
 *   cd backend
 *   MONGODB_URI=mongodb://127.0.0.1:27017/merzox_test npm.cmd start
 */

const environment = resolveIntegrationEnvironment();
const PASSWORD = 'IntegrationPass123';

if (!environment.enabled) {
  test(
    'INTEGRATION_INVENTORY oversell and idempotency',
    { skip: `INTEGRATION_INVENTORY=SKIPPED - ${environment.reason}` },
    () => {}
  );
} else {
  const created = { userIds: [], businessIds: [] };

  /** Never logs headers or bodies: tokens would end up in CI output. */
  async function call(method, path, { token, body } = {}) {
    const response = await fetch(environment.apiUrl + path, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {})
      },
      body: body ? JSON.stringify(body) : undefined
    });
    const text = await response.text();
    let json;
    try {
      json = JSON.parse(text);
    } catch {
      json = {};
    }
    return { status: response.status, json };
  }

  async function seedAccount(phone, name) {
    await call('POST', '/auth/signup', {
      body: { name, phone, password: PASSWORD }
    });
    const login = await call('POST', '/auth/login', {
      body: { phone, password: PASSWORD }
    });
    assert.equal(login.status, 200, 'fixture account should log in');

    const token = login.json?.data?.token;
    const userId = login.json?.data?.user?.id;
    assert.ok(token && userId, 'login should return a token and a user');
    created.userIds.push(userId);

    return { token, userId };
  }

  test('INTEGRATION_INVENTORY oversell and idempotency', async (t) => {
    const stamp = fixtureId(Date.now());
    await mongoose.connect(environment.dbUri);

    t.after(async () => {
      // Scoped strictly to the rows this test created.
      const { connection } = mongoose;
      await connection
        .collection('orders')
        .deleteMany({ user: { $in: created.userIds.map((id) => new mongoose.Types.ObjectId(id)) } });
      await connection
        .collection('businesses')
        .deleteMany({ _id: { $in: created.businessIds.map((id) => new mongoose.Types.ObjectId(id)) } });
      await connection
        .collection('users')
        .deleteMany({ _id: { $in: created.userIds.map((id) => new mongoose.Types.ObjectId(id)) } });
      await mongoose.disconnect();
    });

    const merchant = await seedAccount(`059${stamp.slice(-7)}`, `merchant-${stamp}`);
    const enrolled = await call('POST', '/businesses/enroll', {
      token: merchant.token,
      body: {
        name: `store-${stamp}`,
        category: 'اختبار',
        address: 'عنوان الاختبار'
      }
    });
    assert.equal(enrolled.status, 201, 'merchant should enroll');
    const businessId = enrolled.json?.data?.business?.id;
    assert.ok(businessId, 'enrollment should return a business id');
    created.businessIds.push(businessId);

    const productResponse = await call('POST', '/businesses/me/products', {
      token: merchant.token,
      body: {
        name: `product-${stamp}`,
        price: 100,
        discountPercent: 25,
        unlimitedStock: false,
        stockQuantity: 1
      }
    });
    assert.equal(productResponse.status, 201, 'merchant should create a product');
    const productId = productResponse.json?.data?.product?.id;
    assert.ok(productId, 'product creation should return an id');

    const buyerOne = await seedAccount(`058${stamp.slice(-7)}`, `buyer-a-${stamp}`);
    const buyerTwo = await seedAccount(`057${stamp.slice(-7)}`, `buyer-b-${stamp}`);

    function order(token, clientOrderId) {
      return call('POST', '/orders', {
        token,
        body: {
          businessId,
          clientOrderId,
          deliveryAddress: 'عنوان التوصيل للاختبار',
          items: [{ productId, quantity: 1 }]
        }
      });
    }

    // ---- the final unit, contested simultaneously -------------------------
    const [first, second] = await Promise.all([
      order(buyerOne.token, `${stamp}-a`),
      order(buyerTwo.token, `${stamp}-b`)
    ]);

    const created201 = [first, second].filter((r) => r.status === 201);
    const refused = [first, second].filter((r) => r.status === 409);

    assert.equal(created201.length, 1, 'exactly one checkout may win the last unit');
    assert.equal(refused.length, 1, 'the loser must be refused, not oversold');
    assert.ok(
      ['PRODUCT_OUT_OF_STOCK', 'INSUFFICIENT_STOCK'].includes(
        refused[0].json?.error?.code ?? refused[0].json?.code
      ),
      'the refusal must carry a stock code'
    );

    // The winner paid the server-derived sale price, not the base price.
    assert.equal(created201[0].json?.data?.order?.items?.[0]?.unitPrice, 75);

    // ---- stock consumed exactly once -------------------------------------
    const publicProduct = await call(
      'GET',
      `/businesses/${businessId}/products/${productId}`
    );
    assert.equal(publicProduct.status, 200);
    assert.equal(
      publicProduct.json?.data?.product?.inStock,
      false,
      'the last unit must now be gone'
    );
    assert.equal(
      Object.hasOwn(publicProduct.json?.data?.product ?? {}, 'stockQuantity'),
      false,
      'the public product must not disclose the exact quantity'
    );

    const ownerProducts = await call('GET', '/businesses/me/products', {
      token: merchant.token
    });
    const ownerProduct = (ownerProducts.json?.data?.products ?? []).find(
      (entry) => entry.id === productId
    );
    assert.equal(ownerProduct?.stockQuantity, 0, 'exactly one unit was consumed');

    // ---- an idempotent retry consumes nothing further ---------------------
    const winnerToken =
      created201[0] === first ? buyerOne.token : buyerTwo.token;
    const winnerClientId = created201[0] === first ? `${stamp}-a` : `${stamp}-b`;

    const retry = await order(winnerToken, winnerClientId);
    assert.equal(retry.status, 200, 'a retry returns the existing order');
    assert.equal(retry.json?.data?.duplicated, true);
    assert.equal(
      retry.json?.data?.order?.id,
      created201[0].json?.data?.order?.id,
      'the retry must return the same order'
    );

    const afterRetry = await call('GET', '/businesses/me/products', {
      token: merchant.token
    });
    const afterRetryProduct = (afterRetry.json?.data?.products ?? []).find(
      (entry) => entry.id === productId
    );
    assert.equal(
      afterRetryProduct?.stockQuantity,
      0,
      'a duplicate must not consume stock a second time'
    );
  });
}
