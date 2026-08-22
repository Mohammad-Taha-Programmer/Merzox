import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveIntegrationDatabase } from './test-environment.js';

/**
 * MERZOX-GAP-002-R1 inventory truth, against a real MongoDB server.
 *
 * The unit suites prove the shape of the guards. Only a real server proves the
 * driver honours them, so everything that depends on genuine concurrency,
 * genuine persistence, or genuine crash state lives here.
 *
 * SAFETY. This suite starts its own Express app on an ephemeral LOOPBACK port
 * and connects it to an explicitly declared disposable database. It refuses to
 * run unless `resolveIntegrationDatabase` agrees the target is opt-in, loopback
 * and disposable. It never reads MONGODB_URI as a fallback; in fact it shadows
 * that variable inside this process with the test URI before the application is
 * imported, so even an accidental `connectDatabase()` could not reach the
 * configured application database. `backend/.env` is never written or read for
 * a connection target here.
 *
 * Required environment:
 *   MERZOX_INTEGRATION_TESTS=true
 *   MERZOX_TEST_MONGODB_URI=mongodb://127.0.0.1:27017/merzox_integration
 *
 * Cleanup removes exactly the documents this run created, by id. There is no
 * dropDatabase, no deleteMany({}), and no collection-wide operation anywhere.
 */

const environment = resolveIntegrationDatabase();

if (!environment.enabled) {
  test(
    'INTEGRATION_INVENTORY oversell, idempotency and crash recovery',
    { skip: `INTEGRATION_INVENTORY=SKIPPED - ${environment.reason}` },
    () => {}
  );
} else {
  // Shadowed BEFORE the application is imported. env.js reads process.env at
  // import time, so from here on the app cannot name any other database.
  process.env.MONGODB_URI = environment.dbUri;
  process.env.NODE_ENV = 'test';

  const mongoose = (await import('mongoose')).default;
  const { default: app } = await import('../../src/app.js');
  const { Business } = await import('../../src/models/Business.js');
  const { CheckoutIntent } = await import('../../src/models/CheckoutIntent.js');
  const { Order } = await import('../../src/models/Order.js');
  const { User } = await import('../../src/models/User.js');
  const {
    buildIdentifiedRelease,
    buildIdentifiedReservation
  } = await import('../../src/policies/checkout-intent.policy.js');
  const { reconcileIntent, reconcileStaleCheckouts } = await import(
    '../../src/services/checkout-reconciler.service.js'
  );

  const PASSWORD = 'IntegrationPass123';
  const stamp = `${Date.now()}${Math.floor(Math.random() * 1000)}`;
  const created = { users: [], businesses: [] };

  let server;
  let baseUrl;

  /** Never logs headers or bodies: tokens would end up in test output. */
  async function call(method, path, { token, body } = {}) {
    const response = await fetch(baseUrl + path, {
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
    return { status: response.status, json, code: json?.error?.code };
  }

  // A monotonic counter, so no two fixtures can collide on a phone number.
  let accountSequence = 0;

  async function seedAccount(prefix) {
    accountSequence += 1;
    const phone = `${stamp.slice(-9)}${String(accountSequence).padStart(3, '0')}`;
    // Phone only. Signing up with an email would trigger a verification send,
    // and this suite must not reach out to any mail server.
    const email = `merzox.${stamp}.${accountSequence}@integration.test`;
    const signup = await call('POST', '/api/v1/auth/signup', {
      body: { name: `${prefix}-${stamp}`, phone, password: PASSWORD }
    });
    assert.equal(signup.status, 201, `${prefix} should sign up (${signup.code})`);

    // Tracked the instant it exists, BEFORE any later assertion can throw. A
    // fixture that is created but not recorded is a fixture cleanup cannot
    // find, which is how orphans survive a failing run.
    const signedUpId = signup.json?.data?.user?.id;
    if (signedUpId) created.users.push(signedUpId);

    const login = await call('POST', '/api/v1/auth/login', {
      body: { identifier: phone, password: PASSWORD }
    });
    assert.equal(login.status, 200, `${prefix} should log in (${login.code})`);

    const token = login.json?.data?.token;
    const userId = login.json?.data?.user?.id;
    assert.ok(token && userId, 'login should return a token and a user');
    if (!signedUpId) created.users.push(userId);

    return { token, userId, phone, email };
  }

  /** Enrollment needs the account's own identity confirmed back to it. */
  async function enrollStore(account, name) {
    const enrolled = await call('POST', '/api/v1/businesses/enroll', {
      token: account.token,
      body: {
        phone: account.phone,
        email: account.email,
        currentPassword: PASSWORD,
        name,
        category: 'اختبار',
        address: 'عنوان الاختبار'
      }
    });
    assert.equal(enrolled.status, 201, `merchant should enroll (${enrolled.code})`);

    const businessId = enrolled.json?.data?.business?.id;
    assert.ok(businessId, 'enrollment should return a business id');
    created.businesses.push(businessId);

    return businessId;
  }

  /** A merchant with one product, configured per test. */
  async function seedStore(product, index) {
    const merchant = await seedAccount(`merchant${index}`);
    const businessId = await enrollStore(merchant, `store-${index}-${stamp}`);

    const productResponse = await call('POST', '/api/v1/businesses/me/products', {
      token: merchant.token,
      body: { name: `product-${index}-${stamp}`, ...product }
    });
    assert.equal(
      productResponse.status,
      201,
      `merchant should create a product (${productResponse.code})`
    );

    return {
      merchant,
      businessId,
      productId: productResponse.json?.data?.product?.id
    };
  }

  function placeOrder(token, { businessId, productId, clientOrderId, quantity = 1, items, address }) {
    return call('POST', '/api/v1/orders', {
      token,
      body: {
        businessId,
        clientOrderId,
        deliveryAddress: address ?? 'عنوان التوصيل للاختبار',
        items: items ?? [{ productId, quantity }]
      }
    });
  }

  /** The merchant's own view, which is the only place exact stock is visible. */
  async function ownerStock(merchantToken, productId) {
    const response = await call('GET', '/api/v1/businesses/me/products', {
      token: merchantToken
    });
    const product = (response.json?.data?.products ?? []).find(
      (entry) => entry.id === productId
    );
    return product?.stockQuantity;
  }

  function objectId(value) {
    return new mongoose.Types.ObjectId(String(value));
  }

  test('INTEGRATION_INVENTORY oversell, idempotency and crash recovery', async (t) => {
    await mongoose.connect(environment.dbUri);
    server = app.listen(0, '127.0.0.1');
    await new Promise((resolve) => server.once('listening', resolve));
    baseUrl = `http://127.0.0.1:${server.address().port}`;

    t.after(async () => {
      const { connection } = mongoose;
      const userIds = created.users.map(objectId);
      const businessIds = created.businesses.map(objectId);

      // Scoped strictly to what this run created. No dropDatabase, no
      // deleteMany({}), no collection-wide operation.
      if (userIds.length > 0) {
        await connection.collection('orders').deleteMany({ user: { $in: userIds } });
        await connection
          .collection('checkoutintents')
          .deleteMany({ user: { $in: userIds } });
        await connection
          .collection('notifications')
          .deleteMany({ user: { $in: userIds } });
        await connection.collection('users').deleteMany({ _id: { $in: userIds } });
      }
      if (businessIds.length > 0) {
        await connection
          .collection('businesses')
          .deleteMany({ _id: { $in: businessIds } });
      }

      // A second pass scoped to this run's unique stamp, so a fixture created
      // before its id could be recorded still gets removed. It is still this
      // run's own data only - never a collection-wide delete.
      const ownFixtures = new RegExp(`-${stamp}$`);
      await connection.collection('businesses').deleteMany({ name: ownFixtures });
      const strays = await connection
        .collection('users')
        .find({ name: ownFixtures }, { projection: { _id: 1 } })
        .toArray();
      if (strays.length > 0) {
        const strayIds = strays.map((entry) => entry._id);
        await connection.collection('orders').deleteMany({ user: { $in: strayIds } });
        await connection
          .collection('checkoutintents')
          .deleteMany({ user: { $in: strayIds } });
        await connection
          .collection('notifications')
          .deleteMany({ user: { $in: strayIds } });
        await connection.collection('users').deleteMany({ _id: { $in: strayIds } });
      }

      await new Promise((resolve) => server.close(resolve));
      await mongoose.disconnect();
    });

    // ---------------------------------------------------------------- I01 ---
    await t.test('I01 different keys racing for the final unit', async () => {
      const store = await seedStore(
        { price: 100, discountPercent: 25, unlimitedStock: false, stockQuantity: 1 },
        1
      );
      const buyerA = await seedAccount('buyer-a');
      const buyerB = await seedAccount('buyer-b');

      const [first, second] = await Promise.all([
        placeOrder(buyerA.token, { ...store, clientOrderId: `${stamp}-i01-a` }),
        placeOrder(buyerB.token, { ...store, clientOrderId: `${stamp}-i01-b` })
      ]);

      const won = [first, second].filter((r) => r.status === 201);
      const lost = [first, second].filter((r) => r.status === 409);

      assert.equal(won.length, 1, 'exactly one checkout may win the last unit');
      assert.equal(lost.length, 1, 'the loser must be refused, not oversold');
      assert.ok(
        ['PRODUCT_OUT_OF_STOCK', 'INSUFFICIENT_STOCK'].includes(lost[0].code),
        `expected a stock code, got ${lost[0].code}`
      );
      // The winner paid the server-derived sale price.
      assert.equal(won[0].json.data.order.items[0].unitPrice, 75);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 0);

      const orders = await Order.countDocuments({ business: objectId(store.businessId) });
      assert.equal(orders, 1, 'exactly one order exists');
    });

    // ---------------------------------------------------------------- I02 ---
    await t.test('I02 the SAME key racing converges on one order', async () => {
      const store = await seedStore(
        { price: 60, unlimitedStock: false, stockQuantity: 1 },
        2
      );
      const buyer = await seedAccount('buyer-same');
      const key = `${stamp}-i02`;

      const [first, second] = await Promise.all([
        placeOrder(buyer.token, { ...store, clientOrderId: key }),
        placeOrder(buyer.token, { ...store, clientOrderId: key })
      ]);

      for (const response of [first, second]) {
        assert.ok(
          [200, 201].includes(response.status),
          `an identical idempotent request must not fail with ${response.code}`
        );
        assert.notEqual(response.code, 'PRODUCT_OUT_OF_STOCK');
        assert.notEqual(response.code, 'INSUFFICIENT_STOCK');
      }

      assert.equal(
        first.json.data.order.id,
        second.json.data.order.id,
        'both calls must converge on the same physical order'
      );
      assert.equal(
        await Order.countDocuments({ user: objectId(buyer.userId) }),
        1,
        'exactly one physical order'
      );
      assert.equal(await ownerStock(store.merchant.token, store.productId), 0);
    });

    // ---------------------------------------------------------------- I03 ---
    await t.test('I03 a sequential retry returns the same order', async () => {
      const store = await seedStore(
        { price: 40, unlimitedStock: false, stockQuantity: 5 },
        3
      );
      const buyer = await seedAccount('buyer-retry');
      const key = `${stamp}-i03`;

      const first = await placeOrder(buyer.token, { ...store, clientOrderId: key });
      assert.equal(first.status, 201);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 4);

      const retry = await placeOrder(buyer.token, { ...store, clientOrderId: key });
      assert.equal(retry.status, 200);
      assert.equal(retry.json.data.duplicated, true);
      assert.equal(retry.json.data.order.id, first.json.data.order.id);
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        4,
        'a retry must not consume a second unit'
      );
    });

    // ---------------------------------------------------------------- I04 ---
    await t.test('I04 the same key with a different basket is refused', async () => {
      const store = await seedStore(
        { price: 30, unlimitedStock: false, stockQuantity: 8 },
        4
      );
      const buyer = await seedAccount('buyer-conflict');
      const key = `${stamp}-i04`;

      const first = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 1
      });
      assert.equal(first.status, 201);
      const stockAfterFirst = await ownerStock(store.merchant.token, store.productId);

      const conflicting = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 3
      });

      assert.equal(conflicting.status, 409);
      assert.equal(conflicting.code, 'IDEMPOTENCY_KEY_REUSED');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        stockAfterFirst,
        'a conflicting reuse must reserve nothing'
      );
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 1);
    });

    // ---------------------------------------------------------------- I05 ---
    await t.test('I05 one short line consumes nothing from the others', async () => {
      const merchant = await seedAccount('merchant-multi');
      const businessId = await enrollStore(merchant, `store-5-${stamp}`);

      const plenty = await call('POST', '/api/v1/businesses/me/products', {
        token: merchant.token,
        body: {
          name: `plenty-${stamp}`,
          price: 20,
          unlimitedStock: false,
          stockQuantity: 10
        }
      });
      const scarce = await call('POST', '/api/v1/businesses/me/products', {
        token: merchant.token,
        body: {
          name: `scarce-${stamp}`,
          price: 20,
          unlimitedStock: false,
          stockQuantity: 1
        }
      });
      const plentyId = plenty.json.data.product.id;
      const scarceId = scarce.json.data.product.id;

      const buyer = await seedAccount('buyer-multi');
      const response = await placeOrder(buyer.token, {
        businessId,
        clientOrderId: `${stamp}-i05`,
        items: [
          { productId: plentyId, quantity: 2 },
          { productId: scarceId, quantity: 3 }
        ]
      });

      assert.equal(response.status, 409);
      assert.ok(['INSUFFICIENT_STOCK', 'PRODUCT_OUT_OF_STOCK'].includes(response.code));
      assert.equal(
        await ownerStock(merchant.token, plentyId),
        10,
        'the affordable line must be untouched'
      );
      assert.equal(await ownerStock(merchant.token, scarceId), 1);
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 0);
    });

    // ---------------------------------------------------------------- I06 ---
    await t.test('I06 an unlimited product is never decremented', async () => {
      const store = await seedStore({ price: 45, unlimitedStock: true }, 6);
      const buyer = await seedAccount('buyer-unlimited');

      const response = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: `${stamp}-i06`,
        quantity: 7
      });

      assert.equal(response.status, 201);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 0);

      const stored = await Business.findById(objectId(store.businessId));
      const product = stored.products.find((entry) => entry._id.toString() === store.productId);
      assert.equal(product.unlimitedStock, true);
      assert.equal(product.stockQuantity, 0, 'quantity storage is unchanged');
    });

    // ----------------------------------------------------------- I07 / I08 ---
    await t.test('I07/I08 a release restores once and only once', async () => {
      const store = await seedStore(
        { price: 50, unlimitedStock: false, stockQuantity: 6 },
        7
      );
      const businessId = objectId(store.businessId);
      const productId = objectId(store.productId);
      const intentId = new mongoose.Types.ObjectId();
      const lines = [{ productId, quantity: 2, finite: true }];

      // Reserve against the real server, exactly as the controller would.
      const reservation = buildIdentifiedReservation({ businessId, intentId, lines });
      const reserved = await Business.updateOne(
        reservation.filter,
        reservation.update,
        { arrayFilters: reservation.arrayFilters }
      );
      assert.equal(reserved.matchedCount, 1);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 4);

      // I07: a forced failure before finalization gives the stock back.
      const release = buildIdentifiedRelease({ businessId, intentId, lines });
      const firstRelease = await Business.updateOne(
        release.filter,
        release.update,
        { arrayFilters: release.arrayFilters }
      );
      assert.equal(firstRelease.matchedCount, 1);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 6);

      // I08: the second attempt cannot match, so it cannot invent inventory.
      const secondRelease = await Business.updateOne(
        release.filter,
        release.update,
        { arrayFilters: release.arrayFilters }
      );
      assert.equal(secondRelease.matchedCount, 0);
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        6,
        'a double release must not over-increment'
      );
    });

    // ---------------------------------------------------------------- I09 ---
    await t.test('I09 CRASH-01: intent durable, nothing reserved yet', async () => {
      const store = await seedStore(
        { price: 25, unlimitedStock: false, stockQuantity: 3 },
        9
      );
      const buyer = await seedAccount('buyer-crash1');
      const key = `${stamp}-i09`;

      // The exact durable state a crash right after intent creation leaves.
      await CheckoutIntent.create({
        user: objectId(buyer.userId),
        clientOrderId: key,
        fingerprint: 'seeded-by-the-request-below',
        business: objectId(store.businessId),
        phase: 'prepared',
        lines: [{ productId: objectId(store.productId), quantity: 1, finite: true }]
      });

      // A retry carrying a different fingerprint is a key conflict by design;
      // the honest CRASH-01 replay is the SAME request, so seed the real one.
      await CheckoutIntent.deleteOne({ user: objectId(buyer.userId), clientOrderId: key });

      const first = await placeOrder(buyer.token, { ...store, clientOrderId: key });
      assert.equal(first.status, 201);

      // Rewind the intent to `prepared` and give the stock back, reproducing a
      // crash that happened before the reservation landed.
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'prepared', order: null } }
      );
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $inc: { 'products.$[p].stockQuantity': 1 } },
        { arrayFilters: [{ 'p._id': objectId(store.productId) }] }
      );
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);

      const resumed = await placeOrder(buyer.token, { ...store, clientOrderId: key });
      assert.equal(resumed.status, 201, 'the retry completes the checkout');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        2,
        'and consumes exactly one unit'
      );
    });

    // ---------------------------------------------------------------- I10 ---
    await t.test('I10 CRASH-02: reserved, order not yet written', async () => {
      const store = await seedStore(
        { price: 25, unlimitedStock: false, stockQuantity: 4 },
        10
      );
      const buyer = await seedAccount('buyer-crash2');
      const key = `${stamp}-i10`;
      const businessId = objectId(store.businessId);
      const productId = objectId(store.productId);

      // Produce a genuine intent through the API, then rewind it to the exact
      // state a crash between reservation and order write would leave.
      const first = await placeOrder(buyer.token, { ...store, clientOrderId: key });
      assert.equal(first.status, 201);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);

      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      // The reservation marker is still outstanding, as it would be.
      await Business.updateOne(
        { _id: businessId },
        { $addToSet: { stockReservations: intent._id } }
      );

      const resumed = await placeOrder(buyer.token, { ...store, clientOrderId: key });

      assert.equal(resumed.status, 201, 'the retry finalizes the reserved checkout');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'without decrementing a second time'
      );
      const settled = await Business.findById(businessId).select('+stockReservations');
      assert.equal(
        (settled.stockReservations ?? []).map(String).includes(String(intent._id)),
        false,
        'and the reservation is settled'
      );
      assert.equal(
        await Order.countDocuments({ user: objectId(buyer.userId) }),
        1,
        'exactly one order'
      );
      void productId;
    });

    // ---------------------------------------------------------------- I11 ---
    await t.test('I11 CRASH-03: finalized, response lost', async () => {
      const store = await seedStore(
        { price: 25, unlimitedStock: false, stockQuantity: 4 },
        11
      );
      const buyer = await seedAccount('buyer-crash3');
      const key = `${stamp}-i11`;

      const first = await placeOrder(buyer.token, { ...store, clientOrderId: key });
      assert.equal(first.status, 201);
      const stockAfter = await ownerStock(store.merchant.token, store.productId);

      // The caller never saw the response, so it simply asks again.
      const retry = await placeOrder(buyer.token, { ...store, clientOrderId: key });

      assert.equal(retry.status, 200);
      assert.equal(retry.json.data.duplicated, true);
      assert.equal(retry.json.data.order.id, first.json.data.order.id);
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        stockAfter,
        'no inventory mutation on a replay'
      );
    });

    // ---------------------------------------------------------------- I12 ---
    await t.test('I12 CRASH-04: interrupted mid-recovery still converges', async () => {
      const store = await seedStore(
        { price: 25, unlimitedStock: false, stockQuantity: 4 },
        12
      );
      const buyer = await seedAccount('buyer-crash4');
      const key = `${stamp}-i12`;
      const businessId = objectId(store.businessId);

      const first = await placeOrder(buyer.token, { ...store, clientOrderId: key });
      assert.equal(first.status, 201);

      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Order.deleteOne({ _id: intent.order });

      // The nastiest interruption: stock WAS decremented and the marker set,
      // but the phase flip never happened, so the intent still reads `prepared`.
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'prepared', order: null } }
      );
      await Business.updateOne(
        { _id: businessId },
        { $addToSet: { stockReservations: intent._id } }
      );
      const stockBefore = await ownerStock(store.merchant.token, store.productId);

      const resumed = await placeOrder(buyer.token, { ...store, clientOrderId: key });

      assert.equal(resumed.status, 201);
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        stockBefore,
        'the replayed reservation must not decrement again'
      );
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 1);
    });

    // ---------------------------------------------------------------- I13 ---
    await t.test('I13 a post-finalization side effect cannot release stock', async () => {
      const store = await seedStore(
        { price: 25, unlimitedStock: false, stockQuantity: 3 },
        13
      );
      const buyer = await seedAccount('buyer-notify');

      // Remove the owner the notification is addressed to, so the best-effort
      // notification step runs against a user that no longer exists.
      await User.deleteOne({ _id: objectId(store.merchant.userId) });

      const response = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: `${stamp}-i13`
      });

      assert.equal(response.status, 201, 'the order is still created');
      const order = await Order.findById(response.json.data.order.id);
      assert.ok(order, 'and remains durable');

      const stored = await Business.findById(objectId(store.businessId));
      const product = stored.products.find(
        (entry) => entry._id.toString() === store.productId
      );
      assert.equal(product.stockQuantity, 2, 'stock stays consumed');
    });

    // ----------------------------------------------------------- I14 / I15 ---
    await t.test('I14/I15 an unfinished checkout is invisible everywhere', async () => {
      const store = await seedStore(
        { price: 25, unlimitedStock: false, stockQuantity: 4 },
        14
      );
      const buyer = await seedAccount('buyer-hidden');

      // Two unfinished checkouts, in both non-terminal phases.
      for (const phase of ['prepared', 'reserved']) {
        await CheckoutIntent.create({
          user: objectId(buyer.userId),
          clientOrderId: `${stamp}-i14-${phase}`,
          fingerprint: `fingerprint-${phase}`,
          business: objectId(store.businessId),
          phase,
          lines: [{ productId: objectId(store.productId), quantity: 1, finite: true }]
        });
      }

      const customerOrders = await call('GET', '/api/v1/orders', {
        token: buyer.token
      });
      assert.equal(customerOrders.status, 200);
      assert.equal(
        customerOrders.json.data.orders.length,
        0,
        'a customer must not see an unfinished checkout'
      );
      assert.equal(customerOrders.json.data.counts.total, 0);

      const merchantOrders = await call('GET', '/api/v1/businesses/me/orders', {
        token: store.merchant.token
      });
      assert.equal(merchantOrders.status, 200);
      assert.equal(
        merchantOrders.json.data.orders.length,
        0,
        'a merchant must not see one either'
      );

      const dashboard = await call('GET', '/api/v1/businesses/me/dashboard', {
        token: store.merchant.token
      });
      assert.equal(dashboard.status, 200);
      assert.equal(dashboard.json.data.dashboard.orderCount, 0);
      assert.equal(dashboard.json.data.dashboard.recentOrders.length, 0);

      // The structural reason: an unfinished checkout is not an order at all.
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 0);
      assert.equal(
        await CheckoutIntent.countDocuments({ user: objectId(buyer.userId) }),
        2
      );
    });

    // ----------------------------------------------------------- I16 / I17 ---
    await t.test('I16/I17 semantically identical baskets are one checkout', async () => {
      const merchant = await seedAccount('merchant-canon');
      const businessId = await enrollStore(merchant, `store-16-${stamp}`);

      const alpha = await call('POST', '/api/v1/businesses/me/products', {
        token: merchant.token,
        body: { name: `alpha-${stamp}`, price: 10, unlimitedStock: false, stockQuantity: 20 }
      });
      const beta = await call('POST', '/api/v1/businesses/me/products', {
        token: merchant.token,
        body: { name: `beta-${stamp}`, price: 10, unlimitedStock: false, stockQuantity: 20 }
      });
      const alphaId = alpha.json.data.product.id;
      const betaId = beta.json.data.product.id;

      // I16 - the same basket, sent in the other order.
      const buyerOrder = await seedAccount('buyer-canon-a');
      const keyOrder = `${stamp}-i16`;
      const sent = await placeOrder(buyerOrder.token, {
        businessId,
        clientOrderId: keyOrder,
        items: [
          { productId: alphaId, quantity: 2 },
          { productId: betaId, quantity: 1 }
        ]
      });
      assert.equal(sent.status, 201);

      const permuted = await placeOrder(buyerOrder.token, {
        businessId,
        clientOrderId: keyOrder,
        items: [
          { productId: betaId, quantity: 1 },
          { productId: alphaId, quantity: 2 }
        ]
      });
      assert.equal(permuted.status, 200, 'a permutation is the same request');
      assert.equal(permuted.json.data.order.id, sent.json.data.order.id);
      assert.equal(await ownerStock(merchant.token, alphaId), 18);

      // I17 - the same basket, expressed as repeated lines.
      const buyerRepeat = await seedAccount('buyer-canon-b');
      const keyRepeat = `${stamp}-i17`;
      const summed = await placeOrder(buyerRepeat.token, {
        businessId,
        clientOrderId: keyRepeat,
        items: [{ productId: alphaId, quantity: 3 }]
      });
      assert.equal(summed.status, 201);

      const repeated = await placeOrder(buyerRepeat.token, {
        businessId,
        clientOrderId: keyRepeat,
        items: [
          { productId: alphaId, quantity: 1 },
          { productId: alphaId, quantity: 2 }
        ]
      });
      assert.equal(repeated.status, 200, 'repeated lines normalize to the same basket');
      assert.equal(repeated.json.data.order.id, summed.json.data.order.id);
      assert.equal(
        await ownerStock(merchant.token, alphaId),
        15,
        'and consume nothing extra'
      );
    });

    // ================================================================= R2 ===
    // Reservation lifecycle: merchant edits, finalized-marker cleanup, and
    // autonomous recovery for a client that never comes back.

    function patchProduct(token, productId, body) {
      return call('PATCH', `/api/v1/businesses/me/products/${productId}`, {
        token,
        body
      });
    }

    async function outstandingMarkers(businessId) {
      const stored = await Business.findById(objectId(businessId)).select(
        '+stockReservations'
      );
      return (stored?.stockReservations ?? []).map(String);
    }

    /** Ages an intent so the reconciler treats it as abandoned. */
    async function makeStale(intentId, minutes = 30) {
      await CheckoutIntent.collection.updateOne(
        { _id: objectId(intentId) },
        { $set: { updatedAt: new Date(Date.now() - minutes * 60 * 1000) } }
      );
    }

    // ---------------------------------------------------------------- M01 ---
    await t.test('M01 a stock rewrite is refused while stock is reserved', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm01'
      );
      const buyer = await seedAccount('buyer-m01');
      const key = `${stamp}-m01`;

      // Reserve 2 and stop before finalization, exactly as an in-flight
      // checkout would leave it.
      const first = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(first.status, 201);
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);

      const rewrite = await patchProduct(store.merchant.token, store.productId, {
        stockQuantity: 10
      });

      assert.equal(rewrite.status, 409);
      assert.equal(rewrite.code, 'PRODUCT_INVENTORY_RESERVED');
      assert.equal(
        JSON.stringify(rewrite.json).includes(String(intent._id)),
        false,
        'the reservation id must not be disclosed to the merchant'
      );

      // The stock the merchant tried to set never landed, so the later release
      // cannot turn an intended 10 into 12.
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);
      await reconcileIntent(await CheckoutIntent.findById(intent._id));
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        5,
        'the release restores the original figure, not a corrupted one'
      );
    });

    // ---------------------------------------------------------------- M02 ---
    await t.test('M02 an unlimited toggle is refused while stock is reserved', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 4 },
        'm02'
      );
      const buyer = await seedAccount('buyer-m02');
      const key = `${stamp}-m02`;

      const first = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 1
      });
      assert.equal(first.status, 201);
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );

      const toggle = await patchProduct(store.merchant.token, store.productId, {
        unlimitedStock: true
      });

      assert.equal(toggle.status, 409);
      assert.equal(toggle.code, 'PRODUCT_INVENTORY_RESERVED');

      const stored = await Business.findById(objectId(store.businessId));
      const product = stored.products.find(
        (entry) => entry._id.toString() === store.productId
      );
      assert.equal(product.unlimitedStock, false, 'the toggle did not land');
      assert.equal(product.stockQuantity, 3, 'and no hidden stock was stranded');
    });

    // ---------------------------------------------------------------- M03 ---
    await t.test('M03 a non-inventory edit still succeeds while reserved', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 4 },
        'm03'
      );
      const buyer = await seedAccount('buyer-m03');
      const key = `${stamp}-m03`;

      const first = await placeOrder(buyer.token, { ...store, clientOrderId: key });
      assert.equal(first.status, 201);
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );

      // None of these can be corrupted by a release, so none of them is blocked.
      const edit = await patchProduct(store.merchant.token, store.productId, {
        description: 'وصف محدث أثناء الحجز',
        price: 33,
        discountPercent: 10
      });

      assert.equal(edit.status, 200, `expected a plain edit to pass (${edit.code})`);
      assert.equal(edit.json.data.product.price, 33);
      assert.equal(edit.json.data.product.discountPercent, 10);
    });

    // ----------------------------------------------------------- M04 / M05 ---
    await t.test('M04/M05 inventory edits work again once settled', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 6 },
        'm04'
      );
      const buyer = await seedAccount('buyer-m04');

      // M04 - a finalized checkout leaves nothing outstanding.
      const finalized = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: `${stamp}-m04`,
        quantity: 1
      });
      assert.equal(finalized.status, 201);
      assert.deepEqual(
        await outstandingMarkers(store.businessId),
        [],
        'a finalized checkout holds nothing'
      );

      const afterFinalized = await patchProduct(
        store.merchant.token,
        store.productId,
        { stockQuantity: 12 }
      );
      assert.equal(afterFinalized.status, 200);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 12);

      // M05 - a released checkout likewise.
      const buyerTwo = await seedAccount('buyer-m05');
      const releasedKey = `${stamp}-m05`;
      const placed = await placeOrder(buyerTwo.token, {
        ...store,
        clientOrderId: releasedKey,
        quantity: 2
      });
      assert.equal(placed.status, 201);
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyerTwo.userId),
        clientOrderId: releasedKey
      });
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );
      await reconcileIntent(await CheckoutIntent.findById(intent._id));

      assert.deepEqual(await outstandingMarkers(store.businessId), []);
      const afterReleased = await patchProduct(
        store.merchant.token,
        store.productId,
        { stockQuantity: 7 }
      );
      assert.equal(afterReleased.status, 200);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 7);
    });

    // -------------------------------------------------------- CRASH-FINAL ---
    await t.test('CRASH-FINAL-01 a lingering finalized marker is cleaned', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'cf01'
      );
      const buyer = await seedAccount('buyer-crashfinal');
      const key = `${stamp}-cf01`;

      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(placed.status, 201);
      const orderId = placed.json.data.order.id;
      const stockAfter = await ownerStock(store.merchant.token, store.productId);
      assert.equal(stockAfter, 3);

      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      assert.equal(intent.phase, 'finalized');

      // The exact state a crash between finalization and cleanup leaves.
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), [
        String(intent._id)
      ]);

      // A same-key retry both returns the order and clears the stale marker.
      const retry = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });

      assert.equal(retry.status, 200);
      assert.equal(retry.json.data.order.id, orderId, 'the same order');
      assert.deepEqual(
        await outstandingMarkers(store.businessId),
        [],
        'the stale marker is gone'
      );
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        stockAfter,
        'and no stock was returned'
      );
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 1);
    });

    // ---------------------------------------------------------------- M06 ---
    await t.test('M06 markers do not accumulate over many checkouts', async () => {
      const store = await seedStore(
        { price: 5, unlimitedStock: false, stockQuantity: 100 },
        'm06'
      );
      const buyer = await seedAccount('buyer-m06');

      for (let index = 0; index < 20; index += 1) {
        const response = await placeOrder(buyer.token, {
          ...store,
          clientOrderId: `${stamp}-m06-${index}`,
          quantity: (index % 3) + 1
        });
        assert.equal(response.status, 201, `checkout ${index} should succeed`);

        assert.deepEqual(
          await outstandingMarkers(store.businessId),
          [],
          `no marker may survive checkout ${index}`
        );
      }

      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 20);
      // 20 checkouts of 1..3 units, cycling: 1+2+3 repeated.
      const consumed = Array.from({ length: 20 }, (_, i) => (i % 3) + 1).reduce(
        (sum, q) => sum + q,
        0
      );
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        100 - consumed
      );
    });

    // ---------------------------------------------------------------- R01 ---
    await t.test('R01 a stale PREPARED intent is settled without a retry', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'r01'
      );
      const buyer = await seedAccount('buyer-r01');

      // Nothing was ever reserved: no marker, no order.
      const intent = await CheckoutIntent.create({
        user: objectId(buyer.userId),
        clientOrderId: `${stamp}-r01`,
        fingerprint: 'stale-prepared',
        business: objectId(store.businessId),
        phase: 'prepared',
        lines: [{ productId: objectId(store.productId), quantity: 2, finite: true }]
      });
      await makeStale(intent._id);

      const summary = await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const settled = await CheckoutIntent.findById(intent._id);
      assert.equal(settled.phase, 'released');
      assert.equal(settled.failureCode, 'CHECKOUT_ABANDONED');
      assert.ok(summary.released >= 1);
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        5,
        'nothing was consumed, so nothing changes'
      );
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 0);
    });

    // ---------------------------------------------------------------- R02 ---
    await t.test('R02 a stale RESERVED intent gives its stock back', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'r02'
      );
      const buyer = await seedAccount('buyer-r02');
      const key = `${stamp}-r02`;

      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(placed.status, 201);
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      // The customer's app closed before the order was written.
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );
      await makeStale(intent._id);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);

      // No same-key retry happens. The reconciler acts on its own.
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const settled = await CheckoutIntent.findById(intent._id);
      assert.equal(settled.phase, 'released');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        5,
        'the held stock is back on sale'
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 0);
    });

    // ---------------------------------------------------------------- R03 ---
    await t.test('R03 a stale RESERVED intent whose order exists converges', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'r03'
      );
      const buyer = await seedAccount('buyer-r03');
      const key = `${stamp}-r03`;

      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(placed.status, 201);
      const orderId = placed.json.data.order.id;
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });

      // The order is durable but the intent never recorded it.
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );
      await makeStale(intent._id);

      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const settled = await CheckoutIntent.findById(intent._id);
      assert.equal(settled.phase, 'finalized');
      assert.equal(String(settled.order), orderId);
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'the sold stock stays sold'
      );
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 1);
    });

    // ---------------------------------------------------------------- R04 ---
    await t.test('R04 a lingering finalized marker is cleaned, not refunded', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'r04'
      );
      const buyer = await seedAccount('buyer-r04');
      const key = `${stamp}-r04`;

      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(placed.status, 201);
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );
      await makeStale(intent._id);

      const summary = await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.ok(summary.markerCleaned >= 1);
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'cleanup must NOT restore stock'
      );
    });

    // ---------------------------------------------------------------- R05 ---
    await t.test('R05 reconciliation is idempotent', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 6 },
        'r05'
      );
      const buyer = await seedAccount('buyer-r05');
      const key = `${stamp}-r05`;

      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(placed.status, 201);
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );
      await makeStale(intent._id);

      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      const afterFirst = await ownerStock(store.merchant.token, store.productId);
      assert.equal(afterFirst, 6);

      // Age it again so the second sweep genuinely reconsiders it.
      await makeStale(intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        afterFirst,
        'a second pass must not over-increment'
      );
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 0);
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
    });

    // ---------------------------------------------------------------- R06 ---
    await t.test('R06 a fresh in-flight intent is left alone', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'r06'
      );
      const buyer = await seedAccount('buyer-r06');

      // Created just now: a checkout that is still legitimately in progress.
      const intent = await CheckoutIntent.create({
        user: objectId(buyer.userId),
        clientOrderId: `${stamp}-r06`,
        fingerprint: 'fresh-intent',
        business: objectId(store.businessId),
        phase: 'reserved',
        lines: [{ productId: objectId(store.productId), quantity: 2, finite: true }]
      });
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $addToSet: { stockReservations: intent._id } }
      );

      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const untouched = await CheckoutIntent.findById(intent._id);
      assert.equal(untouched.phase, 'reserved', 'a live checkout is not stolen');
      assert.deepEqual(await outstandingMarkers(store.businessId), [
        String(intent._id)
      ]);
    });
  });
}
