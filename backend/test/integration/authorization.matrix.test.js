import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import { fixtureId, resolveIntegrationEnvironment } from './test-environment.js';

/**
 * Tracked cross-account authorization matrix.
 *
 * This is the reproducible form of the checks that were previously only run by
 * hand. It seeds its own throwaway accounts through the public API, asserts
 * that every cross-account read and write is refused, and then deletes exactly
 * the rows it created.
 *
 * It runs only against an explicitly declared disposable database - see
 * `test-environment.js`. When that is absent the suite reports a SKIP naming
 * the missing prerequisite; it never falls back to the application database.
 *
 * Required environment:
 *   MERZOX_INTEGRATION_TESTS=true
 *   MERZOX_TEST_API_URL=http://localhost:4100/api/v1
 *   MERZOX_TEST_DB_URI=mongodb://127.0.0.1:27017/merzox_test
 *
 * The API at MERZOX_TEST_API_URL must be serving MERZOX_TEST_DB_URI.
 */

const environment = resolveIntegrationEnvironment();
const PASSWORD = 'IntegrationPass123';

if (!environment.enabled) {
  test(
    'INTEGRATION_AUTHZ cross-account matrix',
    { skip: `INTEGRATION_AUTHZ=SKIPPED - ${environment.reason}` },
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
    await call('POST', '/auth/signup', { body: { name, phone, password: PASSWORD } });
    const login = await call('POST', '/auth/login', {
      body: { identifier: phone, password: PASSWORD }
    });
    assert.equal(login.status, 200, `could not authenticate fixture ${name}`);

    const id = login.json.data?.user?.id;
    if (id) created.userIds.push(id);
    return { token: login.json.data.token, id };
  }

  test('cross-account authorization matrix', async (t) => {
    // A single timestamped identity ties every row back to this run.
    const stamp = `${Date.now()}`.slice(-9);
    const identity = fixtureId(stamp);
    const phone = (suffix) => `+9725${stamp}${suffix}`;

    let customerA;
    let customerB;
    let merchantA;
    let merchantB;

    try {
      customerA = await seedAccount(phone('1'), `${identity}-customer-a`);
      customerB = await seedAccount(phone('2'), `${identity}-customer-b`);
      merchantA = await seedAccount(phone('3'), `${identity}-merchant-a`);
      merchantB = await seedAccount(phone('4'), `${identity}-merchant-b`);

      // ---- merchant fixtures -------------------------------------------
      for (const [merchant, suffix] of [
        [merchantA, '3'],
        [merchantB, '4']
      ]) {
        const enroll = await call('POST', '/businesses/enroll', {
          token: merchant.token,
          body: {
            phone: phone(suffix),
            email: `${identity}-${suffix}@merzox.test`,
            currentPassword: PASSWORD,
            name: `${identity}-store-${suffix}`,
            category: 'Integration',
            description: 'integration fixture',
            address: 'Integration address'
          }
        });
        assert.equal(enroll.status, 201, 'fixture business enrollment failed');

        // Enrollment upgrades the account, so the session is re-established.
        const relogin = await call('POST', '/auth/login', {
          body: { identifier: phone(suffix), password: PASSWORD }
        });
        merchant.token = relogin.json.data.token;

        const own = await call('GET', '/businesses/me', { token: merchant.token });
        merchant.businessId = own.json.data.business.id;
        created.businessIds.push(merchant.businessId);
      }

      const product = await call('POST', '/businesses/me/products', {
        token: merchantA.token,
        body: { name: `${identity}-product`, price: 25 }
      });
      assert.equal(product.status, 201, 'fixture product creation failed');
      const productId = product.json.data.product.id;

      const order = await call('POST', '/orders', {
        token: customerA.token,
        body: {
          businessId: merchantA.businessId,
          items: [{ productId, quantity: 1 }],
          deliveryAddress: 'Integration delivery address'
        }
      });
      assert.equal(order.status, 201, 'fixture order creation failed');
      const orderId = order.json.data.order.id;

      const conversation = await call('POST', '/conversations', {
        token: customerA.token,
        body: { businessId: merchantA.businessId }
      });
      assert.equal(conversation.status, 201, 'fixture conversation failed');
      const conversationId = conversation.json.data.conversation.id;

      await call('POST', `/conversations/${conversationId}/messages`, {
        token: customerA.token,
        body: { body: 'integration fixture message' }
      });

      const notifications = await call('GET', '/notifications', {
        token: customerA.token
      });
      const notificationId = notifications.json.data?.notifications?.[0]?.id;

      const GHOST = '000000000000000000000000';
      const denied = [401, 403, 404];

      // ---- unauthenticated ---------------------------------------------
      await t.test('unauthenticated access is refused', async () => {
        for (const [method, path] of [
          ['GET', '/orders'],
          ['GET', '/conversations'],
          ['GET', '/notifications'],
          ['GET', '/businesses/me/orders'],
          ['GET', '/businesses/me/conversations'],
          ['GET', '/businesses/me']
        ]) {
          const res = await call(method, path);
          assert.equal(res.status, 401, `${method} ${path}`);
        }
      });

      // ---- customer A vs customer B ------------------------------------
      await t.test('another customer cannot touch A resources', async () => {
        const cases = [
          ['GET', `/orders/${orderId}`, undefined],
          ['PATCH', `/orders/${orderId}/cancel`, { reason: 'x' }],
          ['PATCH', `/orders/${orderId}/address`, { deliveryAddress: 'Another address' }],
          ['GET', `/conversations/${conversationId}/messages`, undefined],
          ['POST', `/conversations/${conversationId}/messages`, { body: 'intrusion' }],
          ['POST', `/conversations/${conversationId}/read`, undefined]
        ];

        for (const [method, path, body] of cases) {
          const res = await call(method, path, { token: customerB.token, body });
          assert.ok(denied.includes(res.status), `${method} ${path} -> ${res.status}`);
        }

        if (notificationId) {
          const res = await call('POST', `/notifications/${notificationId}/read`, {
            token: customerB.token
          });
          assert.ok(denied.includes(res.status), `notification read -> ${res.status}`);
        }
      });

      // ---- customer vs merchant endpoints ------------------------------
      await t.test('a customer cannot use merchant endpoints', async () => {
        const cases = [
          ['GET', '/businesses/me/orders', undefined],
          ['GET', '/businesses/me/conversations', undefined],
          ['GET', '/businesses/me', undefined],
          ['PATCH', '/businesses/me', { logoUrl: '' }],
          ['PATCH', `/businesses/me/orders/${orderId}/status`, { status: 'delivered' }],
          ['PATCH', `/businesses/me/orders/${orderId}/courier`, { name: 'Intruder' }]
        ];

        for (const [method, path, body] of cases) {
          const res = await call(method, path, { token: customerA.token, body });
          assert.ok(denied.includes(res.status), `${method} ${path} -> ${res.status}`);
        }

        const feed = await call('GET', '/notifications?audience=business', {
          token: customerA.token
        });
        assert.equal(feed.status, 403);
      });

      // ---- merchant A vs merchant B ------------------------------------
      await t.test('a merchant cannot reach another merchant order', async () => {
        for (const [method, path, body] of [
          ['PATCH', `/businesses/me/orders/${orderId}/status`, { status: 'confirmed' }],
          ['PATCH', `/businesses/me/orders/${orderId}/courier`, { name: 'Intruder' }]
        ]) {
          const res = await call(method, path, { token: merchantB.token, body });
          assert.ok(denied.includes(res.status), `${method} ${path} -> ${res.status}`);
        }

        const threads = await call('GET', '/businesses/me/conversations', {
          token: merchantB.token
        });
        assert.equal(threads.status, 200);
        const ids = (threads.json.data?.conversations ?? []).map((c) => c.id);
        assert.equal(ids.includes(conversationId), false, 'thread leaked to merchant B');

        const peek = await call('GET', `/conversations/${conversationId}/messages`, {
          token: merchantB.token
        });
        assert.ok(denied.includes(peek.status), `thread read -> ${peek.status}`);
      });

      // ---- FIX4: merchant product mutations -----------------------------
      await t.test('product writes are owner-scoped', async () => {
        const productPayload = { name: `${identity}-intruder`, price: 5 };

        // Unauthenticated.
        const anonymous = await call('POST', '/businesses/me/products', {
          body: productPayload
        });
        assert.equal(anonymous.status, 401);

        // A customer has no merchant surface at all.
        for (const [method, path, body] of [
          ['POST', '/businesses/me/products', productPayload],
          ['PATCH', `/businesses/me/products/${productId}`, { price: 1 }],
          ['DELETE', `/businesses/me/products/${productId}`, undefined]
        ]) {
          const res = await call(method, path, {
            token: customerA.token,
            body
          });
          assert.ok(denied.includes(res.status), `${method} ${path} -> ${res.status}`);
        }

        // Merchant B may not touch merchant A's product. `/me/` resolves to the
        // caller's own business, so A's product id is simply not found there.
        for (const [method, body] of [
          ['PATCH', { price: 1 }],
          ['DELETE', undefined]
        ]) {
          const res = await call(
            method,
            `/businesses/me/products/${productId}`,
            { token: merchantB.token, body }
          );
          assert.equal(res.status, 404, `${method} -> ${res.status}`);
        }

        // A malformed id and a well-formed unknown id are distinguishable, and
        // neither is authorization.
        const unknown = await call(
          'PATCH',
          `/businesses/me/products/${GHOST}`,
          { token: merchantA.token, body: { price: 1 } }
        );
        assert.equal(unknown.status, 404);

        // Server-controlled fields cannot be injected by the rightful owner.
        for (const body of [
          { name: 'x', price: 1, ratingCount: 99 },
          { name: 'x', price: 1, _id: GHOST },
          { name: 'x', price: 1, finalPrice: 0 }
        ]) {
          const res = await call('POST', '/businesses/me/products', {
            token: merchantA.token,
            body
          });
          assert.equal(res.status, 400, JSON.stringify(Object.keys(body)));
        }
      });

      await t.test('cost price never reaches a public response', async () => {
        // Give the product a cost, then read it back through every public path.
        const priced = await call(
          'PATCH',
          `/businesses/me/products/${productId}`,
          { token: merchantA.token, body: { costPrice: 19 } }
        );
        assert.equal(priced.status, 200);
        assert.equal(priced.json.data.product.costPrice, 19, 'owner sees it');

        for (const path of [
          `/businesses/${merchantA.businessId}`,
          `/businesses/${merchantA.businessId}/products`,
          `/businesses/${merchantA.businessId}/products/${productId}`
        ]) {
          const res = await call('GET', path);
          assert.equal(res.status, 200, path);
          assert.equal(
            JSON.stringify(res.json).includes('costPrice'),
            false,
            `${path} must not expose costPrice`
          );
        }
      });

      // ---- object id shape is not authorization -------------------------
      await t.test('a well-formed unknown id is not authorization', async () => {
        for (const [method, path] of [
          ['GET', `/orders/${GHOST}`],
          ['GET', `/conversations/${GHOST}/messages`],
          ['POST', `/notifications/${GHOST}/read`]
        ]) {
          const res = await call(method, path, { token: customerA.token });
          assert.equal(res.status, 404, `${method} ${path}`);
        }
      });

      // ---- server-owned input ------------------------------------------
      await t.test('the client cannot assign server-owned fields', async () => {
        const base = {
          businessId: merchantA.businessId,
          items: [{ productId, quantity: 1 }],
          deliveryAddress: 'Integration delivery address'
        };

        for (const body of [
          { ...base, user: GHOST },
          { ...base, total: 0 },
          { ...base, items: [{ productId, quantity: 1, unitPrice: 1 }] },
          { ...base, items: [{ productId, quantity: 1, variant: '01' }] }
        ]) {
          const res = await call('POST', '/orders', { token: customerA.token, body });
          assert.equal(res.status, 400, JSON.stringify(Object.keys(body)));
        }

        const sender = await call('POST', `/conversations/${conversationId}/messages`, {
          token: customerA.token,
          body: { body: 'x', senderType: 'business' }
        });
        assert.equal(sender.status, 400);

        for (const body of [{ owner: GHOST }, { ratingAverage: 5 }]) {
          const res = await call('PATCH', '/businesses/me', {
            token: merchantA.token,
            body
          });
          assert.equal(res.status, 400, JSON.stringify(body));
        }
      });
    } finally {
      // ---- narrowly scoped cleanup --------------------------------------
      // Only rows tied to this run's user ids are removed. No collection is
      // dropped and no filter is left open.
      let cleanupError;
      try {
        await mongoose.connect(environment.dbUri);
        const userIds = created.userIds.map((id) => new mongoose.Types.ObjectId(id));
        const businessIds = created.businessIds.map(
          (id) => new mongoose.Types.ObjectId(id)
        );

        if (userIds.length > 0) {
          const db = mongoose.connection.db;
          await db.collection('notifications').deleteMany({ user: { $in: userIds } });
          await db.collection('messages').deleteMany({ user: { $in: userIds } });
          await db.collection('conversations').deleteMany({ user: { $in: userIds } });
          await db.collection('orders').deleteMany({ user: { $in: userIds } });
          if (businessIds.length > 0) {
            await db.collection('businesses').deleteMany({ _id: { $in: businessIds } });
          }
          await db.collection('users').deleteMany({ _id: { $in: userIds } });
        }
      } catch (error) {
        cleanupError = error;
      } finally {
        try {
          await mongoose.disconnect();
        } catch {
          // disconnect failures must not mask a cleanup failure
        }
      }

      if (cleanupError) {
        // Reported loudly: leftover fixtures in a shared test database are a
        // problem for the next run.
        assert.fail(
          `integration fixture cleanup failed (${created.userIds.length} users may remain): ${cleanupError.name}`
        );
      }
    }
  });
}
