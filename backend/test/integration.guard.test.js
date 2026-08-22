import assert from 'node:assert/strict';
import test from 'node:test';

import {
  databaseNameFromUri,
  isDisposableDatabaseName,
  normalizedDatabaseTarget,
  resolveIntegrationEnvironment
} from './integration/test-environment.js';

/**
 * The integration harness mutates a real database, so its safety gate is unit
 * tested here and runs on every `npm test` - including on machines where the
 * harness itself can never run.
 */

const SAFE = {
  MERZOX_INTEGRATION_TESTS: 'true',
  MERZOX_TEST_API_URL: 'http://localhost:4100/api/v1',
  MERZOX_TEST_DB_URI: 'mongodb://127.0.0.1:27017/merzox_test'
};

test('a fully configured disposable environment is accepted', () => {
  const resolved = resolveIntegrationEnvironment(SAFE);

  assert.equal(resolved.enabled, true);
  assert.equal(resolved.dbName, 'merzox_test');
  assert.equal(resolved.apiUrl, 'http://localhost:4100/api/v1');
});

test('the harness stays off without an explicit opt-in', () => {
  for (const value of [undefined, '', 'false', '1', 'yes', 'TRUE ']) {
    const resolved = resolveIntegrationEnvironment({
      ...SAFE,
      MERZOX_INTEGRATION_TESTS: value
    });
    assert.equal(resolved.enabled, false, `opt-in ${JSON.stringify(value)}`);
    assert.match(resolved.reason, /MERZOX_INTEGRATION_TESTS/);
  }
});

test('a missing API url or database uri is refused with a named reason', () => {
  const noApi = resolveIntegrationEnvironment({ ...SAFE, MERZOX_TEST_API_URL: '' });
  assert.equal(noApi.enabled, false);
  assert.match(noApi.reason, /MERZOX_TEST_API_URL/);

  const noDb = resolveIntegrationEnvironment({ ...SAFE, MERZOX_TEST_DB_URI: '' });
  assert.equal(noDb.enabled, false);
  assert.match(noDb.reason, /MERZOX_TEST_DB_URI/);
});

test('the application database is refused even when named like a test one', () => {
  const shared = 'mongodb://127.0.0.1:27017/merzox_test';
  const resolved = resolveIntegrationEnvironment({
    ...SAFE,
    MERZOX_TEST_DB_URI: shared,
    MONGODB_URI: shared
  });

  assert.equal(resolved.enabled, false);
  assert.match(resolved.reason, /same database as MONGODB_URI/);
});

test('cosmetic URI differences cannot disguise the application database', () => {
  // Every pair below is textually different and points at the same database.
  const pairs = [
    [
      'mongodb://127.0.0.1:27017/merzox_test',
      'mongodb://127.0.0.1:27017/merzox_test?retryWrites=true'
    ],
    [
      'mongodb://127.0.0.1:27017/merzox_test',
      'mongodb://user:pass@127.0.0.1:27017/merzox_test'
    ],
    [
      'mongodb://127.0.0.1:27017/merzox_test',
      'mongodb://127.0.0.1:27017/MERZOX_TEST'
    ],
    [
      'mongodb://a:27017,b:27017/merzox_test',
      'mongodb://b:27017,a:27017/merzox_test?replicaSet=rs'
    ]
  ];

  for (const [appUri, testUri] of pairs) {
    const resolved = resolveIntegrationEnvironment({
      ...SAFE,
      MONGODB_URI: appUri,
      MERZOX_TEST_DB_URI: testUri
    });

    assert.equal(resolved.enabled, false, `${appUri} vs ${testUri}`);
    assert.match(resolved.reason, /same database as MONGODB_URI/);
  }
});

test('local host aliases cannot disguise the application database', () => {
  // R1 §4: these all denote the same local MongoDB server. Treating them as
  // different hosts would let a test URI point at the app's own database.
  const aliases = [
    'mongodb://localhost:27017/merzox_test',
    'mongodb://127.0.0.1:27017/merzox_test',
    'mongodb://localhost/merzox_test',
    'mongodb://127.0.0.1/merzox_test',
    'mongodb://0.0.0.0:27017/merzox_test',
    'mongodb://[::1]:27017/merzox_test',
    'mongodb://LOCALHOST:27017/merzox_test'
  ];

  for (const appUri of aliases) {
    for (const testUri of aliases) {
      const resolved = resolveIntegrationEnvironment({
        ...SAFE,
        MONGODB_URI: appUri,
        MERZOX_TEST_DB_URI: testUri
      });

      assert.equal(resolved.enabled, false, `${appUri} vs ${testUri}`);
      assert.match(resolved.reason, /same database as MONGODB_URI/);
    }
  }
});

test('an omitted port is treated as the MongoDB default', () => {
  assert.equal(
    normalizedDatabaseTarget('mongodb://example.net/merzox_test'),
    normalizedDatabaseTarget('mongodb://example.net:27017/merzox_test')
  );

  // A genuinely different port is still a different target.
  assert.notEqual(
    normalizedDatabaseTarget('mongodb://example.net:27017/merzox_test'),
    normalizedDatabaseTarget('mongodb://example.net:27018/merzox_test')
  );
});

test('a remote host is never folded into the local alias', () => {
  const resolved = resolveIntegrationEnvironment({
    ...SAFE,
    MONGODB_URI: 'mongodb://cluster.example.net:27017/merzox_test',
    MERZOX_TEST_DB_URI: 'mongodb://localhost:27017/merzox_test'
  });

  // Different servers, same database name: not a collision.
  assert.equal(resolved.enabled, true);
});

test('a genuinely different database is still accepted', () => {
  const resolved = resolveIntegrationEnvironment({
    ...SAFE,
    MONGODB_URI: 'mongodb://127.0.0.1:27017/merzox',
    MERZOX_TEST_DB_URI: 'mongodb://127.0.0.1:27017/merzox_test'
  });

  assert.equal(resolved.enabled, true);
  assert.equal(resolved.dbName, 'merzox_test');
});

test('the normalized target ignores credentials, options and host order', () => {
  assert.equal(
    normalizedDatabaseTarget('mongodb://u:p@host:27017/merzox_test?ssl=true'),
    'host:27017/merzox_test'
  );
  // Every host now carries an explicit port, so an omitted one folds to the
  // MongoDB default. For a +srv URI the real port comes from DNS, which this
  // guard deliberately does not resolve; normalizing both sides the same way
  // keeps the comparison conservative rather than accurate-but-unsafe.
  assert.equal(
    normalizedDatabaseTarget('mongodb+srv://u:p@Cluster.Example.NET/Merzox_Test'),
    'cluster.example.net:27017/merzox_test'
  );
  assert.equal(
    normalizedDatabaseTarget('mongodb://b:27017,a:27017/db'),
    'a:27017,b:27017/db'
  );

  // A URI naming no database normalizes to nothing, so it can never
  // accidentally compare equal to a real target.
  for (const uri of [
    'mongodb://127.0.0.1:27017',
    'mongodb://127.0.0.1:27017/',
    'mongodb://127.0.0.1:27017/?retryWrites=true',
    '',
    undefined
  ]) {
    assert.equal(normalizedDatabaseTarget(uri), '', String(uri));
  }
});

test('a database without a disposable marker is refused', () => {
  // The real Atlas shape: correct credentials, correct host, production name.
  const production =
    'mongodb+srv://user:pass@cluster0.example.mongodb.net/merzox?retryWrites=true';
  const resolved = resolveIntegrationEnvironment({
    ...SAFE,
    MERZOX_TEST_DB_URI: production
  });

  assert.equal(resolved.enabled, false);
  assert.match(resolved.reason, /not marked disposable/);
  assert.match(resolved.reason, /merzox/);
});

test('a hostname alone never makes a database disposable', () => {
  // Host says "test", database says "merzox": the name is what counts.
  const resolved = resolveIntegrationEnvironment({
    ...SAFE,
    MERZOX_TEST_DB_URI: 'mongodb://test-cluster.internal:27017/merzox'
  });

  assert.equal(resolved.enabled, false);
  assert.match(resolved.reason, /not marked disposable/);
});

test('a uri naming no database is refused', () => {
  for (const uri of [
    'mongodb://127.0.0.1:27017',
    'mongodb://127.0.0.1:27017/',
    'mongodb://127.0.0.1:27017/?retryWrites=true'
  ]) {
    const resolved = resolveIntegrationEnvironment({
      ...SAFE,
      MERZOX_TEST_DB_URI: uri
    });
    assert.equal(resolved.enabled, false, uri);
    assert.match(resolved.reason, /does not name a database/);
  }
});

test('database names are parsed without connecting', () => {
  assert.equal(
    databaseNameFromUri('mongodb://127.0.0.1:27017/merzox_test'),
    'merzox_test'
  );
  assert.equal(
    databaseNameFromUri('mongodb+srv://u:p@host/merzox_integration?ssl=true'),
    'merzox_integration'
  );
  assert.equal(
    databaseNameFromUri('mongodb://a:27017,b:27017/merzox_test?replicaSet=rs'),
    'merzox_test'
  );
  assert.equal(databaseNameFromUri(''), '');
  assert.equal(databaseNameFromUri(undefined), '');
});

test('disposability is decided by an explicit marker list', () => {
  assert.equal(isDisposableDatabaseName('merzox_test'), true);
  assert.equal(isDisposableDatabaseName('integration'), true);
  assert.equal(isDisposableDatabaseName('MERZOX_TEST'), true);
  assert.equal(isDisposableDatabaseName('merzox'), false);
  assert.equal(isDisposableDatabaseName('production'), false);
  assert.equal(isDisposableDatabaseName(''), false);
  assert.equal(isDisposableDatabaseName(undefined), false);
});

test('the real process environment does not enable the harness by accident', () => {
  // Guards against a machine where MONGODB_URI alone would be enough.
  const resolved = resolveIntegrationEnvironment(process.env);
  if (resolved.enabled) {
    assert.equal(isDisposableDatabaseName(resolved.dbName), true);
  } else {
    assert.equal(typeof resolved.reason, 'string');
    assert.ok(resolved.reason.length > 0);
  }
});
