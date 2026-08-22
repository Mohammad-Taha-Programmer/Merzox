/**
 * Fail-closed gate for the integration authorization harness.
 *
 * The harness seeds and deletes real MongoDB documents, so it refuses to run
 * unless the environment states plainly that it is pointed at a disposable
 * database. There is deliberately no fallback to the application's own
 * MONGODB_URI: an unconfigured environment SKIPS, it never silently borrows
 * the running database.
 */

/** A database whose name carries one of these markers is treated as disposable. */
const TEST_DB_MARKERS = ['test', 'integration'];

/** Fixture identities are prefixed with this so cleanup can scope itself. */
export const FIXTURE_PREFIX = 'mc001fix1';

/**
 * Pulls the database name out of a MongoDB connection string without
 * connecting. Returns '' when the URI names no database, which the guard then
 * rejects rather than guessing.
 */
export function databaseNameFromUri(uri) {
  if (typeof uri !== 'string' || uri.length === 0) return '';

  const withoutScheme = uri.replace(/^mongodb(\+srv)?:\/\//i, '');
  const afterHost = withoutScheme.indexOf('/');
  if (afterHost === -1) return '';

  const tail = withoutScheme.slice(afterHost + 1);
  const name = tail.split('?')[0].trim();

  return name;
}

/**
 * Reduces a connection string to the thing that actually decides which data is
 * at risk: the set of hosts plus the database name. Credentials, query options,
 * and casing are dropped, so two URIs that differ only cosmetically are
 * recognised as the same target.
 *
 * Textual inequality is not enough on its own -
 * `mongodb://h/merzox_test` and `mongodb://u:p@h/merzox_test?retryWrites=true`
 * are different strings and the same database.
 */
/**
 * Host aliases that denote the same local MongoDB server. Comparing raw host
 * strings would treat `localhost` and `127.0.0.1` as different machines, so a
 * test URI could point at the very database the app is serving and slip past
 * the collision check.
 *
 * These are folded deterministically - no DNS is performed. The guard errs
 * toward refusing: a false refusal costs a skipped test, a false accept costs
 * the application's data.
 */
const LOCAL_HOST_ALIASES = new Set([
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '::1',
  '[::1]'
]);

const DEFAULT_MONGO_PORT = '27017';

/**
 * Folds one `host[:port]` into a canonical form: local aliases collapse to a
 * single token and an omitted port becomes MongoDB's default, so
 * `localhost`, `127.0.0.1:27017` and `[::1]` all compare equal.
 */
function canonicalHost(entry) {
  const trimmed = entry.trim().toLowerCase();
  if (trimmed.length === 0) return '';

  // An IPv6 literal keeps its brackets; the port is whatever follows them.
  let host = trimmed;
  let port = '';

  if (trimmed.startsWith('[')) {
    const close = trimmed.indexOf(']');
    if (close !== -1) {
      host = trimmed.slice(0, close + 1);
      const rest = trimmed.slice(close + 1);
      port = rest.startsWith(':') ? rest.slice(1) : '';
    }
  } else {
    const colon = trimmed.lastIndexOf(':');
    if (colon !== -1) {
      host = trimmed.slice(0, colon);
      port = trimmed.slice(colon + 1);
    }
  }

  const canonicalName = LOCAL_HOST_ALIASES.has(host) ? 'localhost' : host;
  const canonicalPort = port.length === 0 ? DEFAULT_MONGO_PORT : port;

  return `${canonicalName}:${canonicalPort}`;
}

export function normalizedDatabaseTarget(uri) {
  if (typeof uri !== 'string' || uri.trim().length === 0) return '';

  const withoutScheme = uri.trim().replace(/^mongodb(\+srv)?:\/\//i, '');
  // Credentials sit before the last '@' and never identify the target.
  const atIndex = withoutScheme.lastIndexOf('@');
  const hostAndPath =
    atIndex === -1 ? withoutScheme : withoutScheme.slice(atIndex + 1);

  const slashIndex = hostAndPath.indexOf('/');
  if (slashIndex === -1) return '';

  const hosts = hostAndPath
    .slice(0, slashIndex)
    .split(',')
    .map(canonicalHost)
    .filter(Boolean)
    .sort()
    .join(',');

  const database = hostAndPath
    .slice(slashIndex + 1)
    .split('?')[0]
    .trim()
    .toLowerCase();

  if (database.length === 0) return '';

  return `${hosts}/${database}`;
}

export function isDisposableDatabaseName(name) {
  if (typeof name !== 'string' || name.length === 0) return false;

  const lowered = name.toLowerCase();
  return TEST_DB_MARKERS.some((marker) => lowered.includes(marker));
}

/**
 * Resolves the harness configuration.
 *
 * Returns either `{ enabled: true, apiUrl, dbUri, dbName }` or
 * `{ enabled: false, reason }` where `reason` names the exact missing or
 * unsafe prerequisite. It never throws, so a caller can report a clean SKIP.
 */
export function resolveIntegrationEnvironment(env = process.env) {
  if (String(env.MERZOX_INTEGRATION_TESTS ?? '').trim() !== 'true') {
    return {
      enabled: false,
      reason:
        'MERZOX_INTEGRATION_TESTS is not "true" (explicit opt-in is required)'
    };
  }

  const apiUrl = String(env.MERZOX_TEST_API_URL ?? '').trim();
  if (apiUrl.length === 0) {
    return { enabled: false, reason: 'MERZOX_TEST_API_URL is not set' };
  }

  const dbUri = String(env.MERZOX_TEST_DB_URI ?? '').trim();
  if (dbUri.length === 0) {
    return { enabled: false, reason: 'MERZOX_TEST_DB_URI is not set' };
  }

  // Refuse the application's own database even if it were named like a test
  // one. The comparison is on the normalized target, not the raw string, so
  // differing credentials or query options cannot disguise the same database.
  const appUri = String(env.MONGODB_URI ?? '').trim();
  if (appUri.length > 0) {
    const appTarget = normalizedDatabaseTarget(appUri);
    const testTarget = normalizedDatabaseTarget(dbUri);

    if (appUri === dbUri || (appTarget.length > 0 && appTarget === testTarget)) {
      return {
        enabled: false,
        reason:
          'MERZOX_TEST_DB_URI resolves to the same database as MONGODB_URI (refusing to mutate the application database)'
      };
    }
  }

  const dbName = databaseNameFromUri(dbUri);
  if (dbName.length === 0) {
    return {
      enabled: false,
      reason: 'MERZOX_TEST_DB_URI does not name a database'
    };
  }

  // The name, not the hostname, is what has to prove disposability: a test
  // database on a production host is still a production host.
  if (!isDisposableDatabaseName(dbName)) {
    return {
      enabled: false,
      reason: `database "${dbName}" is not marked disposable (name must contain one of: ${TEST_DB_MARKERS.join(', ')})`
    };
  }

  return { enabled: true, apiUrl, dbUri, dbName };
}

/** A collision-resistant identity so cleanup only ever removes its own rows. */
export function fixtureId(now) {
  return `${FIXTURE_PREFIX}-${now}`;
}
