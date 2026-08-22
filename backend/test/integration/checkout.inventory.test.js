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
  // This suite issues far more requests in a minute than a person could. Rate
  // limiting is not what is under test here, and a 429 would only mask the
  // assertions, so the limiter is lifted for this process only.
  process.env.RATE_LIMIT_MAX = '100000';

  const mongoose = (await import('mongoose')).default;
  const { default: app } = await import('../../src/app.js');
  const { Business } = await import('../../src/models/Business.js');
  const { CheckoutIntent } = await import('../../src/models/CheckoutIntent.js');
  const { Order } = await import('../../src/models/Order.js');
  const { User } = await import('../../src/models/User.js');
  const {
    buildAtomicInventoryUpdate,
    buildIdentifiedRelease,
    checkoutFingerprint,
    buildIdentifiedReservation,
    buildReservationSettlement,
    classifyInventoryConflict,
    inventoryConflictResponse
  } = await import('../../src/policies/checkout-intent.policy.js');
  const { normalizeRequestedItems, resolveOrderLines } = await import(
    '../../src/policies/checkout.policy.js'
  );
  const { reconcileIntent, reconcileStaleCheckouts } = await import(
    '../../src/services/checkout-reconciler.service.js'
  );
  const {
    claimFinalization,
    claimRelease,
    confirmFinalization,
    confirmRelease
  } = await import('../../src/services/checkout-claim.service.js');
  const {
    RESERVATION_OUTCOMES,
    attemptReservation,
    claimReservationFailure,
    reservationOutcome,
    resolveReservationFailure,
    withdrawReservationFailure
  } = await import('../../src/services/checkout-reservation.service.js');

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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);

      const resumed = await placeOrder(buyer.token, { ...store, clientOrderId: key });

      assert.equal(resumed.status, 201, 'the retry finalizes the reserved checkout');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'without decrementing a second time'
      );
      assert.equal(
        (await outstandingMarkers(store.businessId)).includes(String(intent._id)),
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);
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
      return (stored?.stockReservations ?? []).map((entry) => String(entry.intent));
    }

    /** The consumption an outstanding marker says it is holding. */
    async function markerLines(businessId, intentId) {
      const stored = await Business.findById(objectId(businessId)).select(
        '+stockReservations'
      );
      const entry = (stored?.stockReservations ?? []).find(
        (marker) => String(marker.intent) === String(intentId)
      );
      return entry
        ? entry.lines.map((line) => ({
            productId: String(line.productId),
            quantity: line.quantity
          }))
        : null;
    }

    /**
     * Re-attaches a reservation marker the way production does: the marker
     * carries what it consumed, so recovery never has to trust the intent.
     */
    function attachMarker(businessId, intentId, lines) {
      return Business.updateOne(
        { _id: objectId(businessId) },
        {
          $push: {
            stockReservations: { intent: objectId(intentId), lines: lines ?? [] }
          }
        }
      );
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);

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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);

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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);
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
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);

      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const untouched = await CheckoutIntent.findById(intent._id);
      assert.equal(untouched.phase, 'reserved', 'a live checkout is not stolen');
      assert.deepEqual(await outstandingMarkers(store.businessId), [
        String(intent._id)
      ]);
    });

    // ================================================================= R3 ===
    // The merchant inventory write and the reservation predicate are one
    // atomic MongoDB operation, so a checkout that reserves between a read and
    // a write can no longer be overwritten.

    // ---------------------------------------------------------------- M07 ---
    await t.test('M07 a stock rewrite racing a reservation has only two outcomes', async () => {
      const ROUNDS = 10;
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm07'
      );
      const buyer = await seedAccount('buyer-m07');

      for (let round = 0; round < ROUNDS; round += 1) {
        // Reset the product directly, so each round starts from the same 5
        // without spending API calls on fresh fixtures.
        await Business.updateOne(
          { _id: objectId(store.businessId) },
          {
            $set: {
              'products.$[p].stockQuantity': 5,
              'products.$[p].unlimitedStock': false
            }
          },
          { arrayFilters: [{ 'p._id': objectId(store.productId) }] }
        );

        // Fired together: whichever MongoDB serializes first decides.
        const [checkout, rewrite] = await Promise.all([
          placeOrder(buyer.token, {
            ...store,
            clientOrderId: `${stamp}-m07-${round}`,
            quantity: 2
          }),
          patchProduct(store.merchant.token, store.productId, {
            stockQuantity: 10
          })
        ]);

        assert.equal(checkout.status, 201, `round ${round}: the checkout must succeed`);

        const finalStock = await ownerStock(store.merchant.token, store.productId);

        if (rewrite.status === 200) {
          // OUTCOME A - the merchant landed first, the checkout reserved
          // against the NEW figure.
          assert.equal(
            finalStock,
            8,
            `round ${round}: merchant-first must leave 10 - 2`
          );
        } else {
          // OUTCOME B - the reservation was outstanding at write time.
          assert.equal(rewrite.status, 409, `round ${round}: unexpected ${rewrite.status}`);
          assert.equal(rewrite.code, 'PRODUCT_INVENTORY_RESERVED');
          assert.equal(
            finalStock,
            3,
            `round ${round}: checkout-first must leave 5 - 2`
          );
        }

        // The forbidden results, spelled out: a lost decrement, a corrupted
        // release, or anything negative.
        assert.ok(
          [3, 8].includes(finalStock),
          `round ${round}: illegal final stock ${finalStock}`
        );
        assert.ok(finalStock >= 0, `round ${round}: stock went negative`);
        assert.equal(
          await Order.countDocuments({ user: objectId(buyer.userId) }),
          round + 1,
          `round ${round}: one order per round, never two`
        );
        assert.deepEqual(
          await outstandingMarkers(store.businessId),
          [],
          `round ${round}: nothing left outstanding`
        );
      }
    });

    // ---------------------------------------------------------------- M08 ---
    await t.test('M08 an unlimited toggle racing a reservation stays truthful', async () => {
      const ROUNDS = 10;
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm08'
      );
      const buyer = await seedAccount('buyer-m08');

      for (let round = 0; round < ROUNDS; round += 1) {
        await Business.updateOne(
          { _id: objectId(store.businessId) },
          {
            $set: {
              'products.$[p].stockQuantity': 5,
              'products.$[p].unlimitedStock': false
            }
          },
          { arrayFilters: [{ 'p._id': objectId(store.productId) }] }
        );

        const [checkout, toggle] = await Promise.all([
          placeOrder(buyer.token, {
            ...store,
            clientOrderId: `${stamp}-m08-${round}`,
            quantity: 2
          }),
          patchProduct(store.merchant.token, store.productId, {
            unlimitedStock: true
          })
        ]);

        const stored = await Business.findById(objectId(store.businessId));
        const product = stored.products.find(
          (entry) => entry._id.toString() === store.productId
        );

        if (toggle.status === 200) {
          // The merchant won. Canonical normalization zeroes the meaningless
          // quantity, and no stale finite figure may survive to be resurrected.
          assert.equal(product.unlimitedStock, true, `round ${round}`);
          assert.equal(
            product.stockQuantity,
            0,
            `round ${round}: no hidden stale quantity`
          );
        } else {
          assert.equal(toggle.status, 409, `round ${round}: unexpected ${toggle.status}`);
          assert.equal(toggle.code, 'PRODUCT_INVENTORY_RESERVED');
          assert.equal(product.unlimitedStock, false, `round ${round}`);
          assert.equal(
            product.stockQuantity,
            3,
            `round ${round}: the finite remainder is correct`
          );
        }

        assert.equal(checkout.status, 201, `round ${round}: the checkout succeeds either way`);
        assert.deepEqual(await outstandingMarkers(store.businessId), []);
      }
    });

    // ---------------------------------------------------------------- M09 ---
    await t.test('M09 a blocked mixed payload changes nothing at all', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm09'
      );
      const buyer = await seedAccount('buyer-m09');
      const key = `${stamp}-m09`;

      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(placed.status, 201);

      // Hold the reservation open, as an in-flight checkout would.
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);

      const before = await Business.findById(objectId(store.businessId));
      const originalDescription = before.products.find(
        (entry) => entry._id.toString() === store.productId
      ).description;

      const mixed = await patchProduct(store.merchant.token, store.productId, {
        stockQuantity: 10,
        description: 'وصف جديد لا يجب أن يُحفظ'
      });

      assert.equal(mixed.status, 409);
      assert.equal(mixed.code, 'PRODUCT_INVENTORY_RESERVED');

      const blocked = await Business.findById(objectId(store.businessId));
      const blockedProduct = blocked.products.find(
        (entry) => entry._id.toString() === store.productId
      );
      assert.equal(blockedProduct.stockQuantity, 3, 'the stock is untouched');
      assert.equal(
        blockedProduct.description,
        originalDescription,
        'and so is the non-inventory field that rode along'
      );

      // No reservation identity may leak to the merchant.
      const body = JSON.stringify(mixed.json);
      assert.equal(body.includes(String(intent._id)), false);
      assert.equal(body.includes(String(buyer.userId)), false);
      assert.equal(body.includes(key), false);
      assert.equal(body.includes(intent.fingerprint), false);

      // Once the reservation settles, the very same request applies in full.
      await reconcileIntent(await CheckoutIntent.findById(intent._id));
      assert.deepEqual(await outstandingMarkers(store.businessId), []);

      const retried = await patchProduct(store.merchant.token, store.productId, {
        stockQuantity: 10,
        description: 'وصف جديد لا يجب أن يُحفظ'
      });

      assert.equal(retried.status, 200);
      assert.equal(retried.json.data.product.stockQuantity, 10);
      assert.equal(
        retried.json.data.product.description,
        'وصف جديد لا يجب أن يُحفظ'
      );

      // The response must report what MongoDB stored, not a stale subdocument.
      const persisted = await Business.findById(objectId(store.businessId));
      const persistedProduct = persisted.products.find(
        (entry) => entry._id.toString() === store.productId
      );
      assert.equal(persistedProduct.stockQuantity, 10);
      assert.equal(persistedProduct.description, 'وصف جديد لا يجب أن يُحفظ');
    });

    // ---------------------------------------------------------------- M10 ---
    await t.test('M10 a genuinely missing product is still a 404', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm10'
      );
      const ghost = new mongoose.Types.ObjectId();

      const response = await patchProduct(store.merchant.token, String(ghost), {
        stockQuantity: 4
      });

      assert.equal(response.status, 404);
      assert.equal(response.code, 'PRODUCT_NOT_FOUND');
      assert.notEqual(
        response.code,
        'PRODUCT_INVENTORY_RESERVED',
        'a missing product must not be reported as reserved'
      );
    });

    // ================================================================= R4 ===
    // The atomic write can miss for materially different reasons, and the
    // merchant is told which one.

    /**
     * A merchant inventory write whose OBSERVED pair is deliberately stale.
     *
     * The HTTP handler always reads the product immediately before writing, so
     * its observation is current by construction and the compare-and-set can
     * never miss through it. This drives the same production builder,
     * classifier and response mapping with the observation a merchant would
     * actually have been holding.
     */
    async function patchWithObservedStock(
      businessId,
      productId,
      write,
      observedStock
    ) {
      const owner = (await Business.findById(objectId(businessId))).owner;
      const atomic = buildAtomicInventoryUpdate({
        businessId: objectId(businessId),
        ownerId: owner,
        productId: objectId(productId),
        write,
        observedStock
      });

      const updated = await Business.findOneAndUpdate(atomic.filter, atomic.update, {
        arrayFilters: atomic.arrayFilters,
        new: true
      });

      if (updated) return { matched: true, status: 200 };

      const current = await Business.findOne({ _id: objectId(businessId), owner })
        .select('+stockReservations');
      const conflict = classifyInventoryConflict({
        business: current,
        product: current?.products?.id(objectId(productId)),
        observedStock
      });
      const failure = inventoryConflictResponse(conflict);

      return { matched: false, status: failure.status, code: failure.code };
    }

    // ---------------------------------------------------------------- M11 ---
    await t.test('M11 two edits from one observation cannot both apply', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm11'
      );

      // The deterministic half. Both writes were computed from the SAME
      // observed 5, which is the situation `Promise.all` over HTTP can only
      // sometimes produce: the server is free to serialize the two requests,
      // and then the second genuinely observes the first's result and is not
      // stale at all. Driving the observation explicitly makes the invariant
      // testable instead of timing-dependent.
      const first = await patchWithObservedStock(
        store.businessId,
        store.productId,
        { stockQuantity: 8 },
        { stockQuantity: 5, unlimitedStock: false }
      );
      const second = await patchWithObservedStock(
        store.businessId,
        store.productId,
        { stockQuantity: 12 },
        { stockQuantity: 5, unlimitedStock: false }
      );

      assert.equal(first.matched, true, 'the first edit applies against 5');
      assert.equal(second.matched, false, 'the second must not overwrite blindly');
      assert.equal(second.status, 409);
      assert.notEqual(
        second.code,
        'PRODUCT_INVENTORY_RESERVED',
        'no reservation exists, so this must not claim one'
      );
      assert.equal(second.code, 'PRODUCT_INVENTORY_CHANGED');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        8,
        'exactly the winning value, never the stale one'
      );

      // The concurrent half, over real HTTP. Whether the server serializes the
      // two or not, the outcome must stay inside the allowed set.
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $set: { 'products.$[p].stockQuantity': 5 } },
        { arrayFilters: [{ 'p._id': objectId(store.productId) }] }
      );

      const [raceA, raceB] = await Promise.all([
        patchProduct(store.merchant.token, store.productId, { stockQuantity: 8 }),
        patchProduct(store.merchant.token, store.productId, { stockQuantity: 12 })
      ]);

      for (const response of [raceA, raceB]) {
        assert.ok(
          [200, 409].includes(response.status),
          `unexpected status ${response.status}`
        );
        if (response.status === 409) {
          assert.equal(
            response.code,
            'PRODUCT_INVENTORY_CHANGED',
            'a merchant-vs-merchant conflict is never a reservation'
          );
        }
      }

      const finalStock = await ownerStock(store.merchant.token, store.productId);
      assert.ok(
        [8, 12].includes(finalStock),
        `final stock must be a value some request actually asked for, got ${finalStock}`
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), []);

      // Nothing unrelated was disturbed.
      const stored = await Business.findById(objectId(store.businessId));
      const product = stored.products.find(
        (entry) => entry._id.toString() === store.productId
      );
      assert.equal(product.price, 20);
      assert.equal(product.unlimitedStock, false);
    });

    // ---------------------------------------------------------------- M12 ---
    await t.test('M12 a finalized checkout makes a stale merchant write a change', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm12'
      );
      const buyer = await seedAccount('buyer-m12');

      // 1. what the merchant sees before deciding.
      const observed = await ownerStock(store.merchant.token, store.productId);
      assert.equal(observed, 5);

      // 2-4. a checkout consumes 2, finalizes, and its marker is settled.
      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: `${stamp}-m12`,
        quantity: 2
      });
      assert.equal(placed.status, 201);
      const orderId = placed.json.data.order.id;
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);
      assert.deepEqual(
        await outstandingMarkers(store.businessId),
        [],
        'the finalized reservation is already settled'
      );

      // 5. the merchant writes using the pair they observed at step 1.
      const stale = await patchWithObservedStock(
        store.businessId,
        store.productId,
        { stockQuantity: 10 },
        { stockQuantity: observed, unlimitedStock: false }
      );

      assert.equal(stale.matched, false, 'the stale CAS must not apply');
      assert.equal(stale.status, 409);
      assert.equal(stale.code, 'PRODUCT_INVENTORY_CHANGED');
      assert.notEqual(stale.code, 'PRODUCT_INVENTORY_RESERVED');

      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'the consumed inventory is not lost'
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
      const order = await Order.findById(orderId);
      assert.ok(order, 'the finalized order is untouched');
      assert.equal(order.items[0].quantity, 2);
    });

    // ---------------------------------------------------------------- M13 ---
    await t.test('M13 the same stale pair WITH a marker is still reserved', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm13'
      );
      const buyer = await seedAccount('buyer-m13');
      const key = `${stamp}-m13`;

      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(placed.status, 201);

      // Hold the reservation open: the stock pair is stale in exactly the same
      // way as M12, but this time something really is holding it.
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      await Order.deleteOne({ _id: intent.order });
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'reserved', order: null } }
      );
      await attachMarker(store.businessId, intent._id, [
        { productId: objectId(store.productId), quantity: intent.lines[0].quantity }
      ]);

      const blocked = await patchWithObservedStock(
        store.businessId,
        store.productId,
        { stockQuantity: 10 },
        { stockQuantity: 5, unlimitedStock: false }
      );

      assert.equal(blocked.status, 409);
      assert.equal(
        blocked.code,
        'PRODUCT_INVENTORY_RESERVED',
        'the new classification must not collapse both conflicts into one'
      );
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);
    });

    // ---------------------------------------------------------------- M14 ---
    await t.test('M14 a disabled business is not reported as an inventory conflict', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'm14'
      );

      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $set: { isActive: false } }
      );

      const response = await patchProduct(store.merchant.token, store.productId, {
        stockQuantity: 9
      });

      assert.equal(response.status, 403);
      assert.equal(response.code, 'BUSINESS_ACCOUNT_DISABLED');
      assert.notEqual(response.code, 'PRODUCT_INVENTORY_RESERVED');
      assert.notEqual(response.code, 'PRODUCT_INVENTORY_CHANGED');

      // Restored so the shared cleanup can find it by owner as usual.
      await Business.updateOne(
        { _id: objectId(store.businessId) },
        { $set: { isActive: true } }
      );
    });

    // ================================================================= R5 ===
    // Stock-mode symmetry: a line resolved as unlimited must prove the product
    // is STILL unlimited, exactly as a finite line proves it is still finite.

    /** Reads the stored product straight from the collection. */
    async function storedProduct(businessId, productId) {
      const stored = await Business.findById(objectId(businessId));
      return stored.products.find(
        (entry) => entry._id.toString() === productId
      );
    }

    /** Switches a product's stock mode the way a merchant edit would. */
    function setStockMode(businessId, productId, { unlimitedStock, stockQuantity }) {
      return Business.updateOne(
        { _id: objectId(businessId) },
        {
          $set: {
            'products.$[p].unlimitedStock': unlimitedStock,
            'products.$[p].stockQuantity': stockQuantity
          }
        },
        { arrayFilters: [{ 'p._id': objectId(productId) }] }
      );
    }

    /** Removes the field entirely, reproducing a pre-inventory document. */
    function makeLegacy(businessId, productId) {
      return Business.collection.updateOne(
        { _id: objectId(businessId) },
        { $unset: { 'products.$[p].unlimitedStock': '' } },
        { arrayFilters: [{ 'p._id': objectId(productId) }] }
      );
    }

    // ---------------------------------------------------------------- S01 ---
    await t.test('S01 a stale unlimited line cannot reserve a now-finite product', async () => {
      const store = await seedStore({ price: 20, unlimitedStock: true }, 's01');
      const businessId = objectId(store.businessId);
      const productId = objectId(store.productId);

      // 1-2. resolve the line while the product really is unlimited.
      const business = await Business.findById(businessId);
      const resolved = resolveOrderLines({
        products: business.products,
        items: [{ productId: store.productId, quantity: 2 }]
      });
      assert.equal(resolved.error, undefined);
      const [staleLine] = resolved.lines;
      assert.equal(staleLine.finite, false, 'the line was resolved as unlimited');

      // 3. the merchant makes it finite before the reservation runs.
      await setStockMode(store.businessId, store.productId, {
        unlimitedStock: false,
        stockQuantity: 5
      });

      // 4. execute the production reservation with the stale line.
      const intentId = new mongoose.Types.ObjectId();
      const reservation = buildIdentifiedReservation({
        businessId,
        intentId,
        lines: [staleLine]
      });
      const result = await Business.updateOne(
        reservation.filter,
        reservation.update,
        reservation.arrayFilters.length > 0
          ? { arrayFilters: reservation.arrayFilters }
          : undefined
      );

      assert.equal(
        result.matchedCount,
        0,
        'a stale unlimited line must not match a finite product'
      );

      const after = await storedProduct(store.businessId, store.productId);
      assert.equal(after.stockQuantity, 5, 'stock is untouched');
      assert.equal(after.unlimitedStock, false);
      assert.equal(
        (await outstandingMarkers(store.businessId)).includes(String(intentId)),
        false,
        'and no marker was added'
      );
    });

    // ---------------------------------------------------------------- S02 ---
    await t.test('S02 the stale line re-evaluates and consumes the new finite stock', async () => {
      const store = await seedStore({ price: 20, unlimitedStock: true }, 's02');
      const businessId = objectId(store.businessId);

      const business = await Business.findById(businessId);
      const items = [{ productId: store.productId, quantity: 2 }];
      const [staleLine] = resolveOrderLines({
        products: business.products,
        items
      }).lines;
      assert.equal(staleLine.finite, false);

      await setStockMode(store.businessId, store.productId, {
        unlimitedStock: false,
        stockQuantity: 5
      });

      // Attempt 1 - the stale line, exactly as reserveStock would try first.
      const intentId = new mongoose.Types.ObjectId();
      const first = buildIdentifiedReservation({
        businessId,
        intentId,
        lines: [staleLine]
      });
      const firstResult = await Business.updateOne(first.filter, first.update);
      assert.equal(firstResult.matchedCount, 0, 'attempt 1 misses');

      // reserveStock's own recovery path: nothing held, so re-read the truth.
      const held = await Business.exists({
        _id: businessId,
        stockReservations: intentId
      });
      assert.equal(held, null, 'nothing was held by the failed attempt');

      const recheck = await Business.findOne({ _id: businessId, isActive: true });
      const diagnosis = resolveOrderLines({ products: recheck.products, items });
      assert.equal(diagnosis.error, undefined, 'the basket is still purchasable');
      const [freshLine] = diagnosis.lines;
      assert.equal(freshLine.finite, true, 'and is now a finite line');
      assert.equal(freshLine.quantity, 2);

      // Attempt 2 - the rebuilt line reserves normally.
      const second = buildIdentifiedReservation({
        businessId,
        intentId,
        lines: [freshLine]
      });
      const secondResult = await Business.updateOne(
        second.filter,
        second.update,
        { arrayFilters: second.arrayFilters }
      );
      assert.equal(secondResult.matchedCount, 1, 'attempt 2 reserves');

      const reserved = await storedProduct(store.businessId, store.productId);
      assert.equal(reserved.stockQuantity, 3, '5 - 2, not left at 5');
      assert.deepEqual(await outstandingMarkers(store.businessId), [
        String(intentId)
      ]);

      // A release must give back exactly what the SUCCESSFUL attempt consumed.
      const release = buildIdentifiedRelease({
        businessId,
        intentId,
        lines: [{ productId: objectId(store.productId), quantity: 2, finite: true }]
      });
      const releaseResult = await Business.updateOne(
        release.filter,
        release.update,
        { arrayFilters: release.arrayFilters }
      );
      assert.equal(releaseResult.matchedCount, 1);
      assert.equal(
        (await storedProduct(store.businessId, store.productId)).stockQuantity,
        5,
        'restored exactly once'
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
    });

    // ---------------------------------------------------------------- S02b --
    await t.test('S02b the real checkout endpoint consumes the new finite stock', async () => {
      const store = await seedStore({ price: 20, unlimitedStock: true }, 's02b');
      const buyer = await seedAccount('buyer-s02b');

      // The merchant converts to finite BEFORE the request arrives, so the
      // whole two-attempt path runs inside the production controller.
      await setStockMode(store.businessId, store.productId, {
        unlimitedStock: false,
        stockQuantity: 5
      });

      const response = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: `${stamp}-s02b`,
        quantity: 2
      });

      assert.equal(response.status, 201);
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'the finite inventory was genuinely consumed'
      );

      // The intent recorded what was ACTUALLY reserved, so a later release can
      // only ever give back that.
      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: `${stamp}-s02b`
      });
      assert.equal(intent.phase, 'finalized');
      assert.equal(intent.lines.length, 1);
      assert.equal(intent.lines[0].finite, true);
      assert.equal(intent.lines[0].quantity, 2);
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
    });

    // ---------------------------------------------------------------- S03 ---
    await t.test('S03 legacy products keep unlimited semantics, then convert safely', async () => {
      const store = await seedStore({ price: 20, unlimitedStock: true }, 's03');
      const businessId = objectId(store.businessId);

      // A pre-inventory document: the field is absent entirely.
      await makeLegacy(store.businessId, store.productId);
      // Read through the raw driver: the Mongoose model would re-apply the
      // schema default on load and hide the very shape under test.
      const raw = await Business.collection.findOne(
        { _id: businessId },
        { projection: { products: 1 } }
      );
      const rawProduct = raw.products.find(
        (entry) => entry._id.toString() === store.productId
      );
      assert.equal(
        Object.hasOwn(rawProduct, 'unlimitedStock'),
        false,
        'the field is genuinely missing on disk'
      );

      const business = await Business.findById(businessId);
      const items = [{ productId: store.productId, quantity: 3 }];
      const [legacyLine] = resolveOrderLines({
        products: business.products,
        items
      }).lines;
      assert.equal(legacyLine.finite, false, 'legacy reads as unlimited');

      // Unchanged legacy product: the reservation still succeeds and consumes
      // nothing, so legacy compatibility is intact.
      const legacyIntent = new mongoose.Types.ObjectId();
      const legacyReservation = buildIdentifiedReservation({
        businessId,
        intentId: legacyIntent,
        lines: [legacyLine]
      });
      const legacyResult = await Business.updateOne(
        legacyReservation.filter,
        legacyReservation.update
      );
      assert.equal(legacyResult.matchedCount, 1, 'legacy unlimited still reserves');
      assert.equal(
        (await storedProduct(store.businessId, store.productId)).stockQuantity,
        0,
        'and decrements nothing'
      );

      // Settle that marker so it cannot interfere with the merchant edit.
      const settlement = buildReservationSettlement({
        businessId,
        intentId: legacyIntent
      });
      await Business.updateOne(settlement.filter, settlement.update);

      // Now the merchant converts it through the supported product update path.
      const converted = await patchProduct(store.merchant.token, store.productId, {
        unlimitedStock: false,
        stockQuantity: 5
      });
      assert.equal(converted.status, 200, `conversion should apply (${converted.code})`);
      assert.equal(converted.json.data.product.unlimitedStock, false);
      assert.equal(converted.json.data.product.stockQuantity, 5);

      // A stale pre-conversion unlimited line must now match nothing.
      const staleIntent = new mongoose.Types.ObjectId();
      const stale = buildIdentifiedReservation({
        businessId,
        intentId: staleIntent,
        lines: [legacyLine]
      });
      const staleResult = await Business.updateOne(stale.filter, stale.update);

      assert.equal(
        staleResult.matchedCount,
        0,
        'a stale legacy-unlimited line cannot reserve a converted product'
      );
      assert.equal(
        (await storedProduct(store.businessId, store.productId)).stockQuantity,
        5
      );

      // And re-evaluation sees the finite truth.
      const recheck = await Business.findOne({ _id: businessId, isActive: true });
      const [freshLine] = resolveOrderLines({
        products: recheck.products,
        items
      }).lines;
      assert.equal(freshLine.finite, true);
    });

    // ================================================================= R6 ===
    // Recovery must know what a reservation ACTUALLY consumed, and
    // finalization and release must be mutually exclusive.

    /**
     * Reserves through the production builders and then stops, reproducing a
     * crash in the window between the Business write and the CheckoutIntent
     * metadata write. The intent is deliberately left saying `prepared` with
     * whatever lines it was created with.
     */
    async function reserveThenCrash({ businessId, intentId, lines }) {
      const reservation = buildIdentifiedReservation({
        businessId: objectId(businessId),
        intentId: objectId(intentId),
        lines
      });

      return Business.updateOne(
        reservation.filter,
        reservation.update,
        reservation.arrayFilters.length > 0
          ? { arrayFilters: reservation.arrayFilters }
          : undefined
      );
    }

    /** Creates an intent in the exact shape the pre-reservation code writes. */
    function seedIntent({
      userId,
      clientOrderId,
      businessId,
      lines,
      phase = 'prepared',
      fingerprint
    }) {
      return CheckoutIntent.create({
        user: objectId(userId),
        clientOrderId,
        fingerprint: fingerprint ?? `seed-${clientOrderId}`,
        business: objectId(businessId),
        phase,
        lines
      });
    }

    /**
     * The exact fingerprint the checkout endpoint derives for this basket.
     *
     * A seeded intent needs it whenever the test then drives the REAL endpoint:
     * without it the request is refused as a reused key and never reaches the
     * behaviour under test.
     */
    const CHECKOUT_ADDRESS = 'عنوان التوصيل للاختبار';

    function realFingerprint({ businessId, productId, quantity }) {
      const normalized = normalizeRequestedItems([
        { productId: String(productId), quantity }
      ]);
      return checkoutFingerprint({
        businessId: String(businessId),
        items: normalized.items,
        deliveryAddress: CHECKOUT_ADDRESS,
        paymentMethod: 'cash'
      });
    }

    /**
     * A server-authoritative order draft, frozen the way production freezes one
     * at the finalization decision.
     */
    function finalizationSnapshot({
      key,
      buyer,
      store,
      productId,
      name,
      unitPrice,
      quantity
    }) {
      const subtotal = unitPrice * quantity;
      return {
        orderDraft: {
          clientOrderId: key,
          user: objectId(buyer.userId),
          customerName: `buyer-${key}`,
          customerPhone: buyer.phone,
          business: objectId(store.businessId),
          businessName: `store-${key}`,
          businessAddress: 'عنوان الاختبار',
          items: [
            {
              productId: objectId(productId),
              name,
              imageUrl: '',
              unitPrice,
              quantity,
              variant: ''
            }
          ],
          subtotal,
          deliveryFee: 10,
          total: subtotal + 10,
          deliveryAddress: CHECKOUT_ADDRESS,
          paymentMethod: 'cash'
        }
      };
    }

    // ---------------------------------------------------------------- X01 ---
    await t.test('X01 recovery compensates re-evaluated semantics, not stale ones', async () => {
      const store = await seedStore({ price: 20, unlimitedStock: true }, 'x01');
      const buyer = await seedAccount('buyer-x01');
      const productId = objectId(store.productId);

      // The line as first resolved: the product really was unlimited.
      const business = await Business.findById(objectId(store.businessId));
      const items = [{ productId: store.productId, quantity: 2 }];
      const [staleLine] = resolveOrderLines({
        products: business.products,
        items
      }).lines;
      assert.equal(staleLine.finite, false);

      // The intent stores that stale, pre-reservation shape - exactly what the
      // production code persists before it ever touches inventory.
      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: `${stamp}-x01`,
        businessId: store.businessId,
        lines: [{ productId, quantity: 2, finite: false }]
      });

      // The merchant makes it finite.
      await setStockMode(store.businessId, store.productId, {
        unlimitedStock: false,
        stockQuantity: 5
      });

      // Attempt 1 misses; re-evaluation produces a finite line; attempt 2 wins.
      const first = await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines: [staleLine]
      });
      assert.equal(first.matchedCount, 0, 'the stale unlimited attempt misses');

      const recheck = await Business.findOne({ _id: objectId(store.businessId) });
      const [freshLine] = resolveOrderLines({
        products: recheck.products,
        items
      }).lines;
      assert.equal(freshLine.finite, true);

      const second = await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines: [freshLine]
      });
      assert.equal(second.matchedCount, 1, 'the fresh finite attempt reserves');
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);

      // CRASH: the intent still says prepared, with finite:false lines.
      const crashed = await CheckoutIntent.findById(intent._id);
      assert.equal(crashed.phase, 'prepared');
      assert.equal(crashed.lines[0].finite, false, 'the intent metadata is stale');

      // The marker, however, knows exactly what was taken.
      assert.deepEqual(await markerLines(store.businessId, intent._id), [
        { productId: store.productId, quantity: 2 }
      ]);

      // No customer retry. The reconciler acts alone.
      await makeStale(intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const settled = await CheckoutIntent.findById(intent._id);
      assert.equal(settled.phase, 'released');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        5,
        'the finite consumption is given back despite the stale intent lines'
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 0);
    });

    // ---------------------------------------------------------------- X02 ---
    await t.test('X02 the opposite transition invents no stock', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'x02'
      );
      const buyer = await seedAccount('buyer-x02');
      const productId = objectId(store.productId);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: `${stamp}-x02`,
        businessId: store.businessId,
        // Stale the other way round: the intent believes it is finite.
        lines: [{ productId, quantity: 2, finite: true }]
      });

      const business = await Business.findById(objectId(store.businessId));
      const items = [{ productId: store.productId, quantity: 2 }];
      const [staleFinite] = resolveOrderLines({
        products: business.products,
        items
      }).lines;
      assert.equal(staleFinite.finite, true);

      // The merchant wins and makes it unlimited.
      await setStockMode(store.businessId, store.productId, {
        unlimitedStock: true,
        stockQuantity: 0
      });

      const first = await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines: [staleFinite]
      });
      assert.equal(first.matchedCount, 0, 'the stale finite attempt misses');

      const recheck = await Business.findOne({ _id: objectId(store.businessId) });
      const [freshLine] = resolveOrderLines({
        products: recheck.products,
        items
      }).lines;
      assert.equal(freshLine.finite, false);

      const second = await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines: [freshLine]
      });
      assert.equal(second.matchedCount, 1);
      assert.deepEqual(
        await markerLines(store.businessId, intent._id),
        [],
        'an unlimited reservation holds nothing'
      );

      await makeStale(intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const stored = await Business.findById(objectId(store.businessId));
      const product = stored.products.find(
        (entry) => entry._id.toString() === store.productId
      );
      assert.equal(
        product.stockQuantity,
        0,
        'no quantity is invented for an unlimited product'
      );
      assert.equal(product.unlimitedStock, true);
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
      assert.equal(
        (await CheckoutIntent.findById(intent._id)).phase,
        'released'
      );
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 0);
    });

    // ---------------------------------------------------------------- X03 ---
    await t.test('X03 a multi-line crash is compensated completely', async () => {
      const merchant = await seedAccount('merchant-x03');
      const businessId = await enrollStore(merchant, `store-x03-${stamp}`);
      const buyer = await seedAccount('buyer-x03');

      const p1 = await call('POST', '/api/v1/businesses/me/products', {
        token: merchant.token,
        body: { name: `x03-p1-${stamp}`, price: 10, unlimitedStock: true }
      });
      const p2 = await call('POST', '/api/v1/businesses/me/products', {
        token: merchant.token,
        body: {
          name: `x03-p2-${stamp}`,
          price: 10,
          unlimitedStock: false,
          stockQuantity: 9
        }
      });
      const p1Id = p1.json.data.product.id;
      const p2Id = p2.json.data.product.id;

      const items = [
        { productId: p1Id, quantity: 2 },
        { productId: p2Id, quantity: 3 }
      ];
      const business = await Business.findById(objectId(businessId));
      const staleLines = resolveOrderLines({
        products: business.products,
        items
      }).lines;
      assert.equal(staleLines.find((l) => String(l.product._id) === p1Id).finite, false);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: `${stamp}-x03`,
        businessId,
        lines: [
          { productId: objectId(p1Id), quantity: 2, finite: false },
          { productId: objectId(p2Id), quantity: 3, finite: true }
        ]
      });

      // P1 becomes finite underneath the checkout.
      await setStockMode(businessId, p1Id, {
        unlimitedStock: false,
        stockQuantity: 6
      });

      const first = await reserveThenCrash({
        businessId,
        intentId: intent._id,
        lines: staleLines
      });
      assert.equal(first.matchedCount, 0);

      const recheck = await Business.findOne({ _id: objectId(businessId) });
      const freshLines = resolveOrderLines({
        products: recheck.products,
        items
      }).lines;
      assert.equal(freshLines.every((line) => line.finite), true);

      const second = await reserveThenCrash({
        businessId,
        intentId: intent._id,
        lines: freshLines
      });
      assert.equal(second.matchedCount, 1);
      assert.equal(await ownerStock(merchant.token, p1Id), 4);
      assert.equal(await ownerStock(merchant.token, p2Id), 6);

      await makeStale(intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.equal(await ownerStock(merchant.token, p1Id), 6, 'P1 fully restored');
      assert.equal(await ownerStock(merchant.token, p2Id), 9, 'P2 fully restored');
      assert.deepEqual(await outstandingMarkers(businessId), []);
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 0);
    });

    // ---------------------------------------------------------------- X04 ---
    await t.test('X04 finalize and reconcile can never both win', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'x04'
      );
      const buyer = await seedAccount('buyer-x04');
      const key = `${stamp}-x04`;
      const productId = objectId(store.productId);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: key,
        businessId: store.businessId,
        lines: [{ productId, quantity: 2, finite: true }],
        phase: 'reserved'
      });
      await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines: [{ productId, quantity: 2, finite: true }]
      });
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);
      await makeStale(intent._id);

      // The dangerous interleaving, forced: the reconciler establishes "no
      // order yet", THEN a finalizer runs, THEN the reconciler tries to refund.
      const seenOrder = await Order.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      assert.equal(seenOrder, null, 'R observed no order');

      const finalizeWon = await CheckoutIntent.findOneAndUpdate(
        { _id: intent._id, phase: { $in: ['prepared', 'reserved'] } },
        { $set: { phase: 'finalizing' } },
        { new: true }
      );
      assert.ok(finalizeWon, 'F acquired the finalization claim');
      const order = await Order.create({
        clientOrderId: key,
        user: objectId(buyer.userId),
        customerName: 'x04',
        customerPhone: '0590000000',
        business: objectId(store.businessId),
        businessName: 'x04',
        businessAddress: 'x04',
        items: [{ productId, name: 'x04', unitPrice: 20, quantity: 2 }],
        subtotal: 40,
        deliveryFee: 10,
        total: 50,
        deliveryAddress: 'x04 address'
      });

      // R now attempts what used to refund unconditionally.
      const action = await reconcileIntent(await CheckoutIntent.findById(intent._id));

      const settled = await CheckoutIntent.findById(intent._id);
      const finalStock = await ownerStock(store.merchant.token, store.productId);
      const orderCount = await Order.countDocuments({ user: objectId(buyer.userId) });

      // Only the two whole outcomes are permitted.
      if (settled.phase === 'finalized' || finalizeWon) {
        assert.equal(orderCount, 1, 'exactly one order');
        assert.equal(finalStock, 3, 'stock stays consumed');
        assert.notEqual(settled.phase, 'released', 'a durable order is never released');
      }

      // The forbidden combinations, stated directly.
      assert.equal(
        orderCount === 1 && finalStock === 5,
        false,
        'FORBIDDEN: order exists and stock was restored'
      );
      assert.equal(
        orderCount === 1 && settled.phase === 'released',
        false,
        'FORBIDDEN: order exists and the intent says released'
      );
      assert.equal(
        orderCount === 0 && finalStock === 3 && settled.phase === 'released',
        false,
        'FORBIDDEN: stock consumed with no order and a released intent'
      );
      assert.ok(action, 'the reconciler reported an action');
      void order;
    });

    // ---------------------------------------------------------------- X05 ---
    await t.test('X05 once release owns the checkout, no order may appear', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'x05'
      );
      const buyer = await seedAccount('buyer-x05');
      const key = `${stamp}-x05`;
      const productId = objectId(store.productId);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: key,
        businessId: store.businessId,
        lines: [{ productId, quantity: 2, finite: true }],
        phase: 'reserved'
      });
      await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines: [{ productId, quantity: 2, finite: true }]
      });
      await makeStale(intent._id);

      // Release wins first.
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      const released = await CheckoutIntent.findById(intent._id);
      assert.equal(released.phase, 'released');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        5,
        'restored exactly once'
      );

      // The customer now retries the same key through the real endpoint.
      const retry = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });

      assert.equal(retry.status, 409, 'a released checkout answers a stable failure');
      assert.equal(
        await Order.countDocuments({ user: objectId(buyer.userId) }),
        0,
        'no order may be created for a released checkout'
      );
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        5,
        'and no second reservation is taken'
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
    });

    // ---------------------------------------------------------------- X06 ---
    await t.test('X06 once finalization owns the checkout, no refund may happen', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'x06'
      );
      const buyer = await seedAccount('buyer-x06');
      const key = `${stamp}-x06`;

      // A real, completed checkout: finalization owns it.
      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });
      assert.equal(placed.status, 201);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);

      const intent = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      });
      assert.equal(intent.phase, 'finalized');

      // The reconciler runs over it.
      await makeStale(intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'the reconciler cannot refund a finalized checkout'
      );
      assert.equal(await Order.countDocuments({ user: objectId(buyer.userId) }), 1);
      assert.equal(
        (await CheckoutIntent.findById(intent._id)).phase,
        'finalized'
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
    });

    // ---------------------------------------------------------------- X07 ---
    await t.test('X07 a lost claim is never treated as ownership', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'x07'
      );
      const buyer = await seedAccount('buyer-x07');
      const key = `${stamp}-x07`;
      const productId = objectId(store.productId);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: key,
        businessId: store.businessId,
        lines: [{ productId, quantity: 2, finite: true }],
        phase: 'reserved'
      });
      await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines: [{ productId, quantity: 2, finite: true }]
      });

      // Somebody else already owns the outcome.
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'releasing' } }
      );

      // A finalization claim from this state must match nothing...
      const lost = await CheckoutIntent.findOneAndUpdate(
        { _id: intent._id, phase: { $in: ['prepared', 'reserved'] } },
        { $set: { phase: 'finalizing' } },
        { new: true }
      );
      assert.equal(lost, null, 'the claim was not acquired');

      // ...and the production endpoint must refuse rather than proceed.
      const attempt = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 2
      });

      assert.equal(attempt.status, 409);
      assert.equal(
        await Order.countDocuments({ user: objectId(buyer.userId) }),
        0,
        'no order may be written without ownership'
      );
      assert.equal(
        (await CheckoutIntent.findById(intent._id)).phase,
        'releasing',
        'and the losing worker did not overwrite the owner'
      );
    });

    // ---------------------------------------------------------------- X08 ---
    await t.test('X08 a live finalizer is never robbed by the reconciler', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'x08'
      );
      const buyer = await seedAccount('buyer-x08');
      const key = `${stamp}-x08`;
      const productId = objectId(store.productId);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: key,
        businessId: store.businessId,
        lines: [{ productId, quantity: 2, finite: true }],
        phase: 'reserved'
      });
      await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines: [{ productId, quantity: 2, finite: true }]
      });
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);

      // A finalizer takes the claim and is still working - no order yet.
      const claimed = await claimFinalization({
        intentId: intent._id,
        snapshot: finalizationSnapshot({
          key,
          buyer,
          store,
          productId: store.productId,
          name: 'x08',
          unitPrice: 20,
          quantity: 2
        })
      });
      assert.ok(claimed, 'the finalizer owns the checkout');
      assert.equal(claimed.phase, 'finalizing');
      assert.equal(
        await Order.countDocuments({ user: objectId(buyer.userId) }),
        0,
        'and has not written its order yet'
      );

      // The reconciler runs over a checkout whose claim is fresh.
      const action = await reconcileIntent(
        await CheckoutIntent.findById(intent._id)
      );

      assert.equal(action, 'skipped', 'a fresh claim must not be taken over');
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'and the finalizer inventory must not be refunded underneath it'
      );
      assert.equal(
        (await CheckoutIntent.findById(intent._id)).phase,
        'finalizing',
        'the claim still stands'
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), [
        String(intent._id)
      ]);

      // Once it goes quiet past the lease, takeover is allowed - but only in
      // the SAME direction. R7: an abandoned finalization is FINISHED, never
      // refunded, because a paused finalizer could still land its order.
      await makeStale(intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        3,
        'an abandoned finalization keeps the stock it decided to sell'
      );
      assert.equal((await CheckoutIntent.findById(intent._id)).phase, 'finalized');
      assert.equal(
        await Order.countDocuments({ user: objectId(buyer.userId) }),
        1,
        'and is settled by completing exactly one order'
      );
      assert.deepEqual(await outstandingMarkers(store.businessId), []);
    });

    // ---------------------------------------------------------------- X09 ---
    await t.test('X09 a lost claim is reported, never assumed', async () => {
      const store = await seedStore(
        { price: 20, unlimitedStock: false, stockQuantity: 5 },
        'x09'
      );
      const buyer = await seedAccount('buyer-x09');
      const key = `${stamp}-x09`;
      const productId = objectId(store.productId);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: key,
        businessId: store.businessId,
        lines: [{ productId, quantity: 2, finite: true }],
        phase: 'reserved'
      });

      // The worker acquires the claim...
      const claimed = await claimFinalization({
        intentId: intent._id,
        snapshot: finalizationSnapshot({
          key,
          buyer,
          store,
          productId: store.productId,
          name: 'x09',
          unitPrice: 20,
          quantity: 2
        })
      });
      assert.ok(claimed);

      // ...then stalls long enough that a reconciler takes the checkout over
      // and settles it, exactly as X08's second half does.
      await CheckoutIntent.updateOne(
        { _id: intent._id },
        { $set: { phase: 'released', failureCode: 'CHECKOUT_ABANDONED' } }
      );

      // The stalled worker's order lands and it asks whether it still owns the
      // outcome. It does not, and it must be told so rather than assuming.
      const confirmed = await confirmFinalization({
        intentId: intent._id,
        orderId: new mongoose.Types.ObjectId(),
        claimToken: claimed.claimToken
      });

      assert.equal(confirmed.owned, false, 'a lost claim reports not-owned');
      assert.equal(
        (await CheckoutIntent.findById(intent._id)).phase,
        'released',
        'and the owner is not overwritten'
      );

      // A release claim likewise cannot be taken from a terminal checkout.
      const releaseAttempt = await claimRelease({ intentId: intent._id });
      assert.equal(releaseAttempt, null, 'a terminal checkout is unclaimable');
    });

    // ================================================================= R7 ===
    // The checkout decision is MONOTONIC. A lease lets another worker CONTINUE
    // a decision; it never lets one reverse it. Everything below is a real race
    // against a real server, because the whole claim is a claim about what the
    // database does under concurrency.

    /**
     * Reserves finite stock and then leaves the checkout mid-flight, exactly as
     * a crashed worker would: the marker is attached, the intent says
     * `reserved`, and its fingerprint matches what the real endpoint derives so
     * a later customer retry is not turned away as a reused key.
     */
    async function stagedCheckout({ label, quantity, stock, price = 20 }) {
      const store = await seedStore(
        { price, unlimitedStock: false, stockQuantity: stock },
        label
      );
      const buyer = await seedAccount(`buyer-${label}`);
      const key = `${stamp}-${label}`;
      const productId = objectId(store.productId);
      const lines = [{ productId, quantity, finite: true }];

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: key,
        businessId: store.businessId,
        lines,
        phase: 'reserved',
        fingerprint: realFingerprint({
          businessId: store.businessId,
          productId: store.productId,
          quantity
        })
      });
      await reserveThenCrash({
        businessId: store.businessId,
        intentId: intent._id,
        lines
      });
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        stock - quantity,
        'the reservation actually consumed stock'
      );

      return { store, buyer, key, productId, intent, quantity, price };
    }

    function snapshotFor(staged, { name, unitPrice }) {
      return finalizationSnapshot({
        key: staged.key,
        buyer: staged.buyer,
        store: staged.store,
        productId: staged.productId,
        name,
        unitPrice: unitPrice ?? staged.price,
        quantity: staged.quantity
      });
    }

    // ---------------------------------------------------------------- Y01 ---
    await t.test('Y01 an abandoned finalization is finished, never refunded', async () => {
      const staged = await stagedCheckout({ label: 'y01', quantity: 2, stock: 5 });

      // The decision to sell is taken, and the draft is frozen with it.
      const claimed = await claimFinalization({
        intentId: staged.intent._id,
        snapshot: snapshotFor(staged, { name: 'y01 product' })
      });
      assert.ok(claimed, 'the finalization decision stands');
      assert.equal(claimed.phase, 'finalizing');
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        0,
        'and no order exists yet - this is the dangerous window'
      );

      // The worker never comes back.
      await makeStale(staged.intent._id);
      const summary = await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      assert.equal(summary.released, 0, 'nothing may be released');
      assert.equal(summary.finalized, 1, 'the decision is carried out');

      const settled = await CheckoutIntent.findById(staged.intent._id);
      assert.equal(settled.phase, 'finalized');
      assert.ok(settled.order, 'the intent names the order it produced');
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        1,
        'exactly one order'
      );
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3,
        'the stock the decision sold is never given back'
      );
      assert.deepEqual(await outstandingMarkers(staged.store.businessId), []);
    });

    // ---------------------------------------------------------------- Y02 ---
    await t.test('Y02 recovery uses the frozen snapshot, not the merchant catalog', async () => {
      const staged = await stagedCheckout({ label: 'y02', quantity: 2, stock: 5 });

      const claimed = await claimFinalization({
        intentId: staged.intent._id,
        snapshot: snapshotFor(staged, { name: 'committed name', unitPrice: 20 })
      });
      assert.ok(claimed);

      // The merchant now rewrites the product underneath the decision.
      const edited = await patchProduct(
        staged.store.merchant.token,
        staged.store.productId,
        { name: 'renamed after the decision', price: 999, discountPercent: 50 }
      );
      assert.equal(edited.status, 200, `the merchant edit landed (${edited.code})`);

      await makeStale(staged.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const order = await Order.findOne({
        user: objectId(staged.buyer.userId),
        clientOrderId: staged.key
      });
      assert.ok(order, 'recovery completed the order');
      assert.equal(order.items[0].unitPrice, 20, 'the committed price survives');
      assert.equal(order.items[0].name, 'committed name');
      assert.equal(order.subtotal, 40);
      assert.equal(order.total, 50);
      // Explicitly NOT the merchant's newer truth.
      assert.notEqual(order.items[0].unitPrice, 999);
      assert.notEqual(order.items[0].unitPrice, 499.5);
      assert.notEqual(order.items[0].name, 'renamed after the decision');
    });

    // ---------------------------------------------------------------- Y03 ---
    await t.test('Y03 an abandoned release is refunded, and can never finalize', async () => {
      const staged = await stagedCheckout({ label: 'y03', quantity: 2, stock: 5 });

      // The decision to give the stock back is taken - and then the worker dies
      // before the refund itself.
      const claimed = await claimRelease({ intentId: staged.intent._id });
      assert.ok(claimed, 'the release decision stands');
      assert.equal(claimed.phase, 'releasing');
      await makeStale(staged.intent._id);

      // The customer retries the very same key through the real endpoint. It
      // must NOT be able to turn the decision back into a sale.
      const retry = await placeOrder(staged.buyer.token, {
        ...staged.store,
        clientOrderId: staged.key,
        quantity: 2
      });
      assert.equal(retry.status, 409);
      assert.equal(
        retry.code,
        'CHECKOUT_CLAIM_LOST',
        'refused for the right reason: the outcome is already owned'
      );
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        0,
        'no order may be created for a releasing checkout'
      );
      assert.equal(
        (await CheckoutIntent.findById(staged.intent._id)).phase,
        'releasing',
        'and the retry did not reverse the decision'
      );

      await makeStale(staged.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        5,
        'the reservation went back exactly once'
      );
      assert.equal((await CheckoutIntent.findById(staged.intent._id)).phase, 'released');
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        0
      );
      assert.deepEqual(await outstandingMarkers(staged.store.businessId), []);
    });

    // ---------------------------------------------------------------- Y04 ---
    await t.test('Y04 a stalled finalizer and its successor converge on one order', async () => {
      const staged = await stagedCheckout({ label: 'y04', quantity: 2, stock: 5 });

      // F1 takes the decision, then stalls past its lease.
      const f1 = await claimFinalization({
        intentId: staged.intent._id,
        snapshot: snapshotFor(staged, { name: 'y04 product' })
      });
      assert.ok(f1);
      await makeStale(staged.intent._id);

      // No release is reachable from a finalization, stale or not.
      const releaseAttempt = await claimRelease({
        intentId: staged.intent._id,
        staleAfterMs: 60 * 1000
      });
      assert.equal(
        releaseAttempt,
        null,
        'a stale finalization can never be claimed for release'
      );

      // F2 resumes the SAME decision and completes it.
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      const afterF2 = await CheckoutIntent.findById(staged.intent._id);
      assert.equal(afterF2.phase, 'finalized');
      const successorOrderId = String(afterF2.order);

      // F1 finally wakes up and finishes its own work, exactly as production
      // would: it writes its order, then asks whether it still owns the claim.
      const stored = await CheckoutIntent.findById(staged.intent._id).select(
        '+finalization'
      );
      let f1Order = null;
      try {
        f1Order = await Order.create(stored.finalization.orderDraft);
      } catch {
        f1Order = await Order.findOne({
          user: objectId(staged.buyer.userId),
          clientOrderId: staged.key
        });
      }
      assert.equal(
        String(f1Order._id),
        successorOrderId,
        'the unique key converges both workers on ONE physical order'
      );

      const confirmed = await confirmFinalization({
        intentId: staged.intent._id,
        orderId: f1Order._id,
        claimToken: f1.claimToken
      });
      assert.equal(confirmed.owned, false, 'F1 knows its claim was superseded');

      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        1,
        'exactly one order, and none of them deleted'
      );
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3,
        'the stock stays sold throughout'
      );
      assert.equal(
        (await CheckoutIntent.findById(staged.intent._id)).phase,
        'finalized'
      );
      assert.deepEqual(await outstandingMarkers(staged.store.businessId), []);
    });

    // ---------------------------------------------------------------- Y05 ---
    await t.test('Y05 a stalled releaser and its successor refund exactly once', async () => {
      const staged = await stagedCheckout({ label: 'y05', quantity: 2, stock: 5 });

      // R1 takes the release decision, then stalls past its lease.
      const r1 = await claimRelease({ intentId: staged.intent._id });
      assert.ok(r1);
      await makeStale(staged.intent._id);

      // Neither R1's successor nor anybody else may turn this into a sale.
      const finalizeAttempt = await claimFinalization({
        intentId: staged.intent._id,
        snapshot: snapshotFor(staged, { name: 'y05 product' }),
        staleAfterMs: 60 * 1000
      });
      assert.equal(
        finalizeAttempt,
        null,
        'a stale release can never be claimed for finalization'
      );

      // R2 resumes the same decision and completes the refund.
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        5,
        'restored once'
      );

      // R1 wakes up and tries to finish. Its fencing token is gone, and the
      // refund it would repeat is guarded by the marker that no longer exists.
      const repeat = buildIdentifiedRelease({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id,
        lines: [
          { productId: staged.productId, quantity: staged.quantity, finite: true }
        ]
      });
      const repeated = await Business.updateOne(
        repeat.filter,
        repeat.update,
        repeat.arrayFilters.length > 0
          ? { arrayFilters: repeat.arrayFilters }
          : undefined
      );
      assert.equal(repeated.matchedCount, 0, 'a second refund matches nothing');

      const confirmed = await confirmRelease({
        intentId: staged.intent._id,
        failureCode: 'CHECKOUT_ABANDONED',
        claimToken: r1.claimToken
      });
      assert.equal(confirmed.owned, false, 'R1 knows its claim was superseded');

      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        5,
        'and the stock is exact, not doubled'
      );
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        0,
        'a released checkout never produces an order'
      );
      assert.equal(
        (await CheckoutIntent.findById(staged.intent._id)).phase,
        'released'
      );
      assert.deepEqual(await outstandingMarkers(staged.store.businessId), []);
    });

    // ---------------------------------------------------------------- Y06 ---
    await t.test('Y06 staleness never changes a claim direction', async () => {
      const staged = await stagedCheckout({ label: 'y06', quantity: 1, stock: 5 });
      const intentId = staged.intent._id;
      const snapshot = snapshotFor(staged, { name: 'y06 product' });
      const lease = 60 * 1000;

      async function setPhase(phase) {
        await CheckoutIntent.updateOne({ _id: intentId }, { $set: { phase } });
      }

      // --- fresh finalizing -------------------------------------------------
      await setPhase('finalizing');
      assert.equal(
        await claimRelease({ intentId, staleAfterMs: lease }),
        null,
        'fresh finalizing -> claimRelease must not match'
      );
      assert.equal(
        await claimFinalization({ intentId, staleAfterMs: lease }),
        null,
        'and a fresh claim is not resumable either'
      );

      // --- stale finalizing -------------------------------------------------
      await makeStale(intentId);
      assert.equal(
        await claimRelease({ intentId, staleAfterMs: lease }),
        null,
        'stale finalizing -> claimRelease must STILL not match'
      );
      const resumedFinalize = await claimFinalization({ intentId, staleAfterMs: lease });
      assert.ok(resumedFinalize, 'only the same direction may resume it');
      assert.equal(resumedFinalize.phase, 'finalizing');

      // --- fresh releasing --------------------------------------------------
      await setPhase('releasing');
      assert.equal(
        await claimFinalization({ intentId, snapshot, staleAfterMs: lease }),
        null,
        'fresh releasing -> claimFinalization must not match'
      );
      assert.equal(
        await claimRelease({ intentId, staleAfterMs: lease }),
        null,
        'and a fresh release claim is not resumable either'
      );

      // --- stale releasing --------------------------------------------------
      await makeStale(intentId);
      assert.equal(
        await claimFinalization({ intentId, snapshot, staleAfterMs: lease }),
        null,
        'stale releasing -> claimFinalization must STILL not match'
      );
      const resumedRelease = await claimRelease({ intentId, staleAfterMs: lease });
      assert.ok(resumedRelease, 'only the same direction may resume it');
      assert.equal(resumedRelease.phase, 'releasing');

      // --- terminal ---------------------------------------------------------
      for (const terminal of ['finalized', 'released']) {
        await setPhase(terminal);
        await makeStale(intentId);
        assert.equal(
          await claimFinalization({ intentId, snapshot, staleAfterMs: lease }),
          null,
          `${terminal} is unclaimable for finalization`
        );
        assert.equal(
          await claimRelease({ intentId, staleAfterMs: lease }),
          null,
          `${terminal} is unclaimable for release`
        );
      }
    });

    // ---------------------------------------------------------------- Y07 ---
    await t.test('Y07 an order written just before a crash is adopted, not undone', async () => {
      const staged = await stagedCheckout({ label: 'y07', quantity: 2, stock: 5 });

      const claimed = await claimFinalization({
        intentId: staged.intent._id,
        snapshot: snapshotFor(staged, { name: 'y07 product' })
      });
      assert.ok(claimed);

      // The order lands...
      const stored = await CheckoutIntent.findById(staged.intent._id).select(
        '+finalization'
      );
      const order = await Order.create(stored.finalization.orderDraft);
      // ...and the process dies before the phase or the marker can be updated.
      assert.equal(
        (await CheckoutIntent.findById(staged.intent._id)).phase,
        'finalizing'
      );

      await makeStale(staged.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const settled = await CheckoutIntent.findById(staged.intent._id);
      assert.equal(settled.phase, 'finalized');
      assert.equal(String(settled.order), String(order._id), 'the same order, adopted');
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        1,
        'no second order, and no compensating delete'
      );
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3,
        'the stock is not refunded'
      );
      assert.deepEqual(await outstandingMarkers(staged.store.businessId), []);
    });

    // ---------------------------------------------------------------- Y08 ---
    await t.test('Y08 a refund that landed before a crash is not repeated', async () => {
      const staged = await stagedCheckout({ label: 'y08', quantity: 2, stock: 5 });

      const claimed = await claimRelease({ intentId: staged.intent._id });
      assert.ok(claimed);

      // The refund lands...
      const release = buildIdentifiedRelease({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id,
        lines: [
          { productId: staged.productId, quantity: staged.quantity, finite: true }
        ]
      });
      const refunded = await Business.updateOne(
        release.filter,
        release.update,
        release.arrayFilters.length > 0
          ? { arrayFilters: release.arrayFilters }
          : undefined
      );
      assert.equal(refunded.matchedCount, 1, 'the refund landed');
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        5
      );
      // ...and the process dies before `released` is written.
      assert.equal(
        (await CheckoutIntent.findById(staged.intent._id)).phase,
        'releasing'
      );

      await makeStale(staged.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        5,
        'the second pass changes nothing'
      );
      assert.equal(
        (await CheckoutIntent.findById(staged.intent._id)).phase,
        'released'
      );
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        0,
        'a release never produces an order'
      );
      assert.deepEqual(await outstandingMarkers(staged.store.businessId), []);

      // And running it again is still a no-op.
      await makeStale(staged.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        5
      );
    });

    // ---------------------------------------------------------------- Y09 ---
    await t.test('Y09 the finalization snapshot never reaches any client', async () => {
      const store = await seedStore(
        { price: 30, unlimitedStock: false, stockQuantity: 4 },
        'y09'
      );
      const buyer = await seedAccount('buyer-y09');
      const key = `${stamp}-y09`;

      const placed = await placeOrder(buyer.token, {
        ...store,
        clientOrderId: key,
        quantity: 1
      });
      assert.equal(placed.status, 201);

      // The snapshot is real and durable...
      const stored = await CheckoutIntent.findOne({
        user: objectId(buyer.userId),
        clientOrderId: key
      }).select('+finalization');
      assert.ok(stored.finalization?.orderDraft, 'the decision was snapshotted');
      assert.equal(stored.finalization.orderDraft.items[0].unitPrice, 30);

      // ...and it is not selected by an ordinary read.
      const ordinary = await CheckoutIntent.findById(stored._id);
      assert.equal(ordinary.finalization, undefined);

      // Nothing a customer or a merchant can ask for contains it.
      const orderId = placed.json.data.order.id;
      const surfaces = [
        await call('GET', '/api/v1/orders/mine', { token: buyer.token }),
        await call('GET', `/api/v1/orders/mine/${orderId}`, { token: buyer.token }),
        await call('GET', '/api/v1/businesses/me/orders', {
          token: store.merchant.token
        }),
        await call('GET', '/api/v1/businesses/me/products', {
          token: store.merchant.token
        }),
        await call('GET', `/api/v1/businesses/${store.businessId}`)
      ];

      for (const surface of surfaces) {
        const body = JSON.stringify(surface.json ?? {});
        assert.equal(body.includes('finalization'), false, 'no snapshot field');
        assert.equal(body.includes('claimToken'), false, 'no fencing token');
        assert.equal(body.includes('stockReservations'), false, 'no markers');
      }

      // The checkout response itself, too.
      const body = JSON.stringify(placed.json);
      assert.equal(body.includes('finalization'), false);
      assert.equal(body.includes('claimToken'), false);
    });

    // ================================================================= R8 ===
    // A checkout's RESERVATION outcome is exclusive too. A worker may not
    // conclude "the stock is not there" from an earlier read: both the
    // reservation and the terminal refusal are a `$push` guarded by the same
    // "no entry for this intent yet" predicate, so exactly one can land.

    /**
     * A checkout parked at `prepared` with no reservation of any kind, and a
     * fingerprint matching what the real endpoint derives - so the same key can
     * be driven through the real controller afterwards.
     */
    async function pendingCheckout({ label, quantity, product }) {
      const store = await seedStore(product, label);
      const buyer = await seedAccount(`buyer-${label}`);
      const key = `${stamp}-${label}`;
      const productId = objectId(store.productId);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: key,
        businessId: store.businessId,
        lines: [{ productId, quantity, finite: true }],
        phase: 'prepared',
        fingerprint: realFingerprint({
          businessId: store.businessId,
          productId: store.productId,
          quantity
        })
      });

      return { store, buyer, key, productId, intent, quantity };
    }

    /** Every entry recorded against a business, refusals included. */
    async function reservationEntries(businessId) {
      const stored = await Business.findById(objectId(businessId)).select(
        '+stockReservations'
      );
      return (stored?.stockReservations ?? []).map((entry) => ({
        intent: String(entry.intent),
        state: entry.state,
        failureCode: entry.failureCode ?? null,
        lines: (entry.lines ?? []).length
      }));
    }

    /**
     * The forbidden state, asserted directly: a checkout that terminally failed
     * while a live reservation for it still holds stock.
     */
    async function assertNoOrphanConsumption(staged, initialStock) {
      const intent = await CheckoutIntent.findById(staged.intent._id);
      const entries = await reservationEntries(staged.store.businessId);
      const live = entries.filter(
        (entry) =>
          entry.intent === String(staged.intent._id) && entry.state !== 'failed'
      );
      const stock = await ownerStock(
        staged.store.merchant.token,
        staged.store.productId
      );

      assert.equal(
        intent.phase === 'released' && live.length > 0,
        false,
        'FORBIDDEN: released intent with a live reservation'
      );
      assert.equal(
        intent.phase === 'released' && stock !== initialStock,
        false,
        'FORBIDDEN: released intent with consumed stock'
      );
      return { intent, entries, live, stock };
    }

    // ---------------------------------------------------------------- Z01 ---
    await t.test('Z01 terminal failure and reservation cannot both land', async () => {
      const staged = await pendingCheckout({
        label: 'z01',
        quantity: 2,
        product: { price: 20, unlimitedStock: false, stockQuantity: 1 }
      });

      // Worker A asks for 2 against a stock of 1 and is refused...
      const aAttempt = await attemptReservation({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id,
        lines: [{ productId: staged.productId, quantity: 2, finite: true }]
      });
      assert.equal(aAttempt.matched, false);

      // ...and observes that nothing is recorded. THIS is the stale
      // observation the old code used to act on several operations later.
      const aObserved = await reservationOutcome({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id
      });
      assert.equal(aObserved.state, RESERVATION_OUTCOMES.open);

      // A is paused here. The merchant restocks, and worker B - the same
      // checkout, taken over after the convergence timeout - reserves.
      const restock = await patchProduct(
        staged.store.merchant.token,
        staged.store.productId,
        { stockQuantity: 5 }
      );
      assert.equal(restock.status, 200, `restock landed (${restock.code})`);

      const bAttempt = await attemptReservation({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id,
        lines: [{ productId: staged.productId, quantity: 2, finite: true }]
      });
      assert.equal(bAttempt.matched, true, 'B reserved');
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3
      );

      // A now wakes up and tries to commit its terminal failure. It must lose.
      const aClaim = await claimReservationFailure({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id,
        failureCode: 'INSUFFICIENT_STOCK'
      });
      assert.equal(
        aClaim.owned,
        false,
        'a terminal failure cannot be declared over a live reservation'
      );

      // And what it must do instead: converge on the reservation.
      const settled = await reservationOutcome({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id
      });
      assert.equal(settled.state, RESERVATION_OUTCOMES.reserved);
      assert.deepEqual(
        settled.lines.map((line) => line.quantity),
        [2]
      );

      const state = await assertNoOrphanConsumption(staged, 5);
      assert.notEqual(state.intent.phase, 'released');
      assert.equal(state.live.length, 1, 'exactly one live reservation');
      assert.equal(state.stock, 3, 'consumed exactly once');

      // The real endpoint then converges on that reservation and sells it.
      const finished = await placeOrder(staged.buyer.token, {
        ...staged.store,
        clientOrderId: staged.key,
        quantity: 2
      });
      assert.equal(finished.status, 201, `converged (${finished.code})`);
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3,
        'and did not consume a second time'
      );
      assert.deepEqual(await outstandingMarkers(staged.store.businessId), []);
    });

    // ---------------------------------------------------------------- Z02 ---
    await t.test('Z02 a stale reserver is fenced out after the failure decision', async () => {
      const staged = await pendingCheckout({
        label: 'z02',
        quantity: 2,
        product: { price: 20, unlimitedStock: false, stockQuantity: 1 }
      });

      // Worker B has decided what it will reserve, but has not written yet.
      const bLines = [{ productId: staged.productId, quantity: 2, finite: true }];

      // Worker A wins the terminal failure first.
      const aClaim = await claimReservationFailure({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id,
        failureCode: 'INSUFFICIENT_STOCK'
      });
      assert.equal(aClaim.owned, true, 'A owns the refusal');
      await CheckoutIntent.updateOne(
        { _id: staged.intent._id, phase: { $in: ['prepared', 'reserved'] } },
        { $set: { phase: 'released', failureCode: 'INSUFFICIENT_STOCK' } }
      );

      // The merchant even restocks, so the ONLY thing that can stop B is the
      // fence itself - not a lack of inventory.
      const restock = await patchProduct(
        staged.store.merchant.token,
        staged.store.productId,
        { stockQuantity: 9 }
      );
      assert.equal(restock.status, 200, `restock landed (${restock.code})`);

      // B finally writes. This is the fencing proof.
      const bAttempt = await attemptReservation({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id,
        lines: bLines
      });

      assert.equal(bAttempt.matched, false, 'B matched zero documents');
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        9,
        'no decrement'
      );

      const entries = await reservationEntries(staged.store.businessId);
      const mine = entries.filter(
        (entry) => entry.intent === String(staged.intent._id)
      );
      assert.equal(mine.length, 1, 'exactly one recorded outcome');
      assert.equal(mine[0].state, 'failed');
      assert.equal(mine[0].lines, 0, 'a refusal holds nothing');
      assert.equal(
        (await CheckoutIntent.findById(staged.intent._id)).phase,
        'released'
      );

      // A merchant is not frozen by a refusal record: it holds no stock.
      assert.equal(restock.status, 200);

      // And the sweep eventually clears the record without inventing stock.
      await makeStale(staged.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      assert.deepEqual(await reservationEntries(staged.store.businessId), []);
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        9,
        'clearing a refusal never refunds'
      );
    });

    // ---------------------------------------------------------------- Z03 ---
    await t.test('Z03 when the reservation wins first, the loser converges', async () => {
      const staged = await pendingCheckout({
        label: 'z03',
        quantity: 2,
        product: { price: 25, unlimitedStock: false, stockQuantity: 5 }
      });

      // B reserves successfully first.
      await reserveThenCrash({
        businessId: staged.store.businessId,
        intentId: staged.intent._id,
        lines: [{ productId: staged.productId, quantity: 2, finite: true }]
      });
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3
      );

      // A's failure path now runs through the REAL endpoint on the same key.
      const attempt = await placeOrder(staged.buyer.token, {
        ...staged.store,
        clientOrderId: staged.key,
        quantity: 2
      });

      assert.equal(attempt.status, 201, `A converged, not failed (${attempt.code})`);
      assert.equal(attempt.json.data.order.items[0].unitPrice, 25);

      const state = await assertNoOrphanConsumption(staged, 5);
      assert.notEqual(state.intent.phase, 'released');
      assert.equal(
        state.stock,
        3,
        'the held reservation was sold, never consumed twice'
      );
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        1
      );
      assert.deepEqual(await outstandingMarkers(staged.store.businessId), []);
    });

    // ---------------------------------------------------------------- Z04 ---
    await t.test('Z04 a stock-mode re-evaluation cannot race a stale refusal', async () => {
      const store = await seedStore({ price: 30, unlimitedStock: true }, 'z04');
      const buyer = await seedAccount('buyer-z04');
      const key = `${stamp}-z04`;
      const productId = objectId(store.productId);

      const intent = await seedIntent({
        userId: buyer.userId,
        clientOrderId: key,
        businessId: store.businessId,
        // The stale line, read while the product was still unlimited.
        lines: [{ productId, quantity: 2, finite: false }],
        phase: 'prepared',
        fingerprint: realFingerprint({
          businessId: store.businessId,
          productId: store.productId,
          quantity: 2
        })
      });
      const staged = { store, buyer, key, productId, intent, quantity: 2 };

      // The merchant converts the product to finite stock.
      const converted = await patchProduct(store.merchant.token, store.productId, {
        unlimitedStock: false,
        stockQuantity: 5
      });
      assert.equal(converted.status, 200, `converted (${converted.code})`);

      // Worker A's stale unlimited line can no longer reserve (R5/S01).
      const stale = await attemptReservation({
        businessId: objectId(store.businessId),
        intentId: intent._id,
        lines: [{ productId, quantity: 2, finite: false }]
      });
      assert.equal(stale.matched, false, 'a stale unlimited line reserves nothing');

      // Worker B re-evaluates against the finite truth and reserves.
      const reEvaluated = await attemptReservation({
        businessId: objectId(store.businessId),
        intentId: intent._id,
        lines: [{ productId, quantity: 2, finite: true }]
      });
      assert.equal(reEvaluated.matched, true);
      assert.equal(await ownerStock(store.merchant.token, store.productId), 3);

      // A, still holding its stale diagnosis, tries to fail terminally.
      const aClaim = await claimReservationFailure({
        businessId: objectId(store.businessId),
        intentId: intent._id,
        failureCode: 'PRODUCT_OUT_OF_STOCK'
      });
      assert.equal(aClaim.owned, false, 'the re-evaluated reservation already won');

      const state = await assertNoOrphanConsumption(staged, 5);
      assert.notEqual(state.intent.phase, 'released');
      assert.equal(state.stock, 3);

      // Recovery still compensates the ACTUAL finite consumption, not the
      // stale `finite: false` line the intent was created with (R6/X01).
      assert.deepEqual(await markerLines(store.businessId, intent._id), [
        { productId: String(productId), quantity: 2 }
      ]);
      await makeStale(intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      assert.equal(
        await ownerStock(store.merchant.token, store.productId),
        5,
        'restored exactly what was taken'
      );
    });

    // ---------------------------------------------------------------- Z05 ---
    await t.test('Z05 insufficient stock then a restock resolves to one outcome', async () => {
      const staged = await pendingCheckout({
        label: 'z05',
        quantity: 2,
        product: { price: 40, unlimitedStock: false, stockQuantity: 1 }
      });

      // A diagnoses insufficient stock and pauses before its decision.
      const aAttempt = await attemptReservation({
        businessId: objectId(staged.store.businessId),
        intentId: staged.intent._id,
        lines: [{ productId: staged.productId, quantity: 2, finite: true }]
      });
      assert.equal(aAttempt.matched, false);

      // The merchant restocks, and B drives the SAME key through the real
      // endpoint - which reserves and sells.
      const restock = await patchProduct(
        staged.store.merchant.token,
        staged.store.productId,
        { stockQuantity: 5 }
      );
      assert.equal(restock.status, 200, `restock landed (${restock.code})`);

      const bResult = await placeOrder(staged.buyer.token, {
        ...staged.store,
        clientOrderId: staged.key,
        quantity: 2
      });
      assert.equal(bResult.status, 201, `B sold it (${bResult.code})`);
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3
      );

      // A resumes and drives its own terminal-failure path through the real
      // endpoint. The checkout it wanted to fail has already been sold, so it
      // must report the ORDER, not a stock error.
      const aResult = await placeOrder(staged.buyer.token, {
        ...staged.store,
        clientOrderId: staged.key,
        quantity: 2
      });
      assert.ok(
        [200, 201].includes(aResult.status),
        `a sold checkout is never failed retroactively (${aResult.code})`
      );
      assert.equal(
        aResult.json.data.order.id,
        bResult.json.data.order.id,
        'both converge on the same physical order'
      );

      // And no refusal record survives for a checkout that succeeded.
      const records = await reservationEntries(staged.store.businessId);
      assert.deepEqual(
        records.filter((entry) => entry.intent === String(staged.intent._id)),
        [],
        'no refusal record for a sold checkout'
      );

      const intent = await CheckoutIntent.findById(staged.intent._id);
      assert.equal(intent.phase, 'finalized');
      assert.equal(
        await Order.countDocuments({ user: objectId(staged.buyer.userId) }),
        1,
        'exactly one order'
      );
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3,
        'no orphan consumption'
      );
    });

    // ---------------------------------------------------------------- Z06 ---
    await t.test('Z06 recovery is unchanged, and an orphan now self-heals', async () => {
      // Part 1: the exact R6/R7 state - prepared intent, successful marker and
      // decrement, no customer retry. Recovery must be untouched by R8.
      const staged = await pendingCheckout({
        label: 'z06',
        quantity: 2,
        product: { price: 15, unlimitedStock: false, stockQuantity: 5 }
      });
      await reserveThenCrash({
        businessId: staged.store.businessId,
        intentId: staged.intent._id,
        lines: [{ productId: staged.productId, quantity: 2, finite: true }]
      });
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        3
      );

      await makeStale(staged.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        5,
        'authoritative-marker recovery still restores exactly'
      );
      assert.equal(
        (await CheckoutIntent.findById(staged.intent._id)).phase,
        'released'
      );
      assert.deepEqual(await reservationEntries(staged.store.businessId), []);

      // Part 2: the state the OLD bug produced - a released intent standing
      // against a live reservation. Before R8 the sweep never even looked at a
      // released intent, so this leaked a unit of stock permanently.
      const orphan = await pendingCheckout({
        label: 'z06b',
        quantity: 2,
        product: { price: 15, unlimitedStock: false, stockQuantity: 5 }
      });
      await CheckoutIntent.updateOne(
        { _id: orphan.intent._id },
        { $set: { phase: 'released', failureCode: 'INSUFFICIENT_STOCK' } }
      );
      await reserveThenCrash({
        businessId: orphan.store.businessId,
        intentId: orphan.intent._id,
        lines: [{ productId: orphan.productId, quantity: 2, finite: true }]
      });
      assert.equal(
        await ownerStock(orphan.store.merchant.token, orphan.store.productId),
        3,
        'the orphan consumption exists'
      );

      await makeStale(orphan.intent._id);
      const summary = await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      assert.ok(summary.inspected > 0, 'a released intent is no longer invisible');
      assert.equal(
        await ownerStock(orphan.store.merchant.token, orphan.store.productId),
        5,
        'the orphan consumption is given back'
      );
      assert.deepEqual(await reservationEntries(orphan.store.businessId), []);

      // Idempotent: a second sweep invents nothing.
      await makeStale(orphan.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });
      assert.equal(
        await ownerStock(orphan.store.merchant.token, orphan.store.productId),
        5
      );
    });

    // ---------------------------------------------------------------- Z07 ---
    await t.test('Z07 a refusal record blocks nothing a merchant may do', async () => {
      const staged = await pendingCheckout({
        label: 'z07',
        quantity: 2,
        product: { price: 20, unlimitedStock: false, stockQuantity: 4 }
      });

      // A LIVE reservation still freezes merchant inventory (M01 unchanged)...
      await reserveThenCrash({
        businessId: staged.store.businessId,
        intentId: staged.intent._id,
        lines: [{ productId: staged.productId, quantity: 2, finite: true }]
      });
      const blocked = await patchProduct(
        staged.store.merchant.token,
        staged.store.productId,
        { stockQuantity: 50 }
      );
      assert.equal(blocked.status, 409, 'a live reservation still blocks');
      assert.equal(blocked.code, 'PRODUCT_INVENTORY_RESERVED');

      // ...and the response still leaks nothing.
      const blockedBody = JSON.stringify(blocked.json);
      assert.equal(blockedBody.includes('stockReservations'), false);
      assert.equal(blockedBody.includes(String(staged.intent._id)), false);

      // Clear it, then record a refusal for a DIFFERENT checkout instead.
      await makeStale(staged.intent._id);
      await reconcileStaleCheckouts({ staleAfterMs: 60 * 1000 });

      const other = await seedIntent({
        userId: staged.buyer.userId,
        clientOrderId: `${staged.key}-b`,
        businessId: staged.store.businessId,
        lines: [{ productId: staged.productId, quantity: 99, finite: true }],
        phase: 'prepared'
      });
      const refused = await claimReservationFailure({
        businessId: objectId(staged.store.businessId),
        intentId: other._id,
        failureCode: 'INSUFFICIENT_STOCK'
      });
      assert.equal(refused.owned, true);

      // A refusal holds no stock, so the merchant is free.
      const allowed = await patchProduct(
        staged.store.merchant.token,
        staged.store.productId,
        { stockQuantity: 50 }
      );
      assert.equal(
        allowed.status,
        200,
        `a refusal record must not freeze inventory (${allowed.code})`
      );
      assert.equal(
        await ownerStock(staged.store.merchant.token, staged.store.productId),
        50
      );

      // And nothing about the record reaches any client.
      const surfaces = [
        await call('GET', '/api/v1/businesses/me/products', {
          token: staged.store.merchant.token
        }),
        await call('GET', `/api/v1/businesses/${staged.store.businessId}`),
        await call('GET', '/api/v1/businesses/me/orders', {
          token: staged.store.merchant.token
        })
      ];
      for (const surface of surfaces) {
        const body = JSON.stringify(surface.json ?? {});
        assert.equal(body.includes('stockReservations'), false);
        assert.equal(body.includes(String(other._id)), false);
        assert.equal(body.includes('failureCode'), false);
      }
    });

    // ---------------------------------------------------------------- Z08 ---
    await t.test('Z08 the terminal-failure decision is what production obeys', async () => {
      // `resolveReservationFailure` is the single operation the checkout
      // controller uses to decide a terminal reservation failure, so the whole
      // guarantee can be driven deterministically here: inject the concurrent
      // reservation at the exact instant the old code was vulnerable, and
      // assert what the decision permits - not what the worker wanted.
      const businessId = (staged) => objectId(staged.store.businessId);

      // --- the outcome is still open: the refusal is granted ---------------
      const open = await pendingCheckout({
        label: 'z08a',
        quantity: 2,
        product: { price: 20, unlimitedStock: false, stockQuantity: 1 }
      });
      const granted = await resolveReservationFailure({
        businessId: businessId(open),
        intentId: open.intent._id,
        failureCode: 'INSUFFICIENT_STOCK'
      });
      assert.equal(granted.owned, true, 'nothing else owns it, so it is granted');
      assert.equal(granted.converge, null);
      assert.equal(
        await ownerStock(open.store.merchant.token, open.store.productId),
        1,
        'a refusal never touches stock'
      );

      // --- a reservation landed first: the refusal is REFUSED --------------
      const raced = await pendingCheckout({
        label: 'z08b',
        quantity: 2,
        product: { price: 20, unlimitedStock: false, stockQuantity: 5 }
      });
      const injected = await attemptReservation({
        businessId: businessId(raced),
        intentId: raced.intent._id,
        lines: [{ productId: raced.productId, quantity: 2, finite: true }]
      });
      assert.equal(injected.matched, true, 'the concurrent worker reserved');

      const refused = await resolveReservationFailure({
        businessId: businessId(raced),
        intentId: raced.intent._id,
        failureCode: 'INSUFFICIENT_STOCK'
      });
      assert.equal(refused.owned, false, 'the refusal is NOT granted');
      assert.equal(
        refused.converge,
        RESERVATION_OUTCOMES.reserved,
        'and the worker is told to converge on the reservation'
      );
      assert.deepEqual(
        refused.lines.map((line) => line.quantity),
        [2],
        'with the quantities that were actually consumed'
      );
      assert.equal(
        (await CheckoutIntent.findById(raced.intent._id)).phase,
        'prepared',
        'no terminal state was written'
      );
      assert.equal(
        await ownerStock(raced.store.merchant.token, raced.store.productId),
        3,
        'and the reservation still holds exactly what it took'
      );

      // --- a refusal landed first: converge on THAT refusal ----------------
      const already = await pendingCheckout({
        label: 'z08c',
        quantity: 2,
        product: { price: 20, unlimitedStock: false, stockQuantity: 1 }
      });
      await claimReservationFailure({
        businessId: businessId(already),
        intentId: already.intent._id,
        failureCode: 'PRODUCT_OUT_OF_STOCK'
      });
      const second = await resolveReservationFailure({
        businessId: businessId(already),
        intentId: already.intent._id,
        failureCode: 'INSUFFICIENT_STOCK'
      });
      assert.equal(second.owned, false, 'a refusal is decided once');
      assert.equal(second.converge, RESERVATION_OUTCOMES.failed);
      assert.equal(
        second.failureCode,
        'PRODUCT_OUT_OF_STOCK',
        'and every later worker answers with the recorded reason'
      );

      // --- withdrawing a refusal can never remove a live reservation -------
      await withdrawReservationFailure({
        businessId: businessId(raced),
        intentId: raced.intent._id
      });
      assert.equal(
        await ownerStock(raced.store.merchant.token, raced.store.productId),
        3,
        'the live reservation survived a withdrawal aimed at a refusal'
      );
      const survivors = await reservationEntries(raced.store.businessId);
      assert.equal(survivors.length, 1);
      assert.equal(survivors[0].state, 'reserved');

      await withdrawReservationFailure({
        businessId: businessId(already),
        intentId: already.intent._id
      });
      assert.deepEqual(
        await reservationEntries(already.store.businessId),
        [],
        'but its own refusal is withdrawn'
      );
    });
  });
}
