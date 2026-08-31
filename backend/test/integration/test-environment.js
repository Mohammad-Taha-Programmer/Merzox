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
 * Hosts accepted for the integration API.
 *
 * The MongoDB guard protects the cleanup connection, but fixtures are created
 * through MERZOX_TEST_API_URL - and nothing proves that API is serving the test
 * database. A configuration like:
 *
 *   MERZOX_TEST_DB_URI=mongodb://localhost:27017/merzox_test
 *   MERZOX_TEST_API_URL=https://a-production-api.example/api/v1
 *
 * would create real users and orders remotely and then clean only the local
 * database. Until the harness can verify a server's identity, only a loopback
 * API is accepted: an operator can point that at the test database, a remote
 * host cannot be vouched for.
 */
const LOOPBACK_API_HOSTS = new Set(['localhost', '127.0.0.1', '::1', '[::1]']);

/**
 * Validates the integration API URL without touching the network.
 *
 * Returns `{ ok: true }` or `{ ok: false, reason }`. No DNS is resolved and no
 * TLS setting is relaxed; a host that merely looks local by name is not enough,
 * which is why the check is on the parsed hostname.
 */
export function validateIntegrationApiUrl(rawUrl) {
  const value = String(rawUrl ?? '').trim();

  if (value.length === 0) {
    return { ok: false, reason: 'MERZOX_TEST_API_URL is not set' };
  }

  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    return { ok: false, reason: 'MERZOX_TEST_API_URL is not a valid URL' };
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    return {
      ok: false,
      reason: `MERZOX_TEST_API_URL must be http or https (got "${parsed.protocol.replace(':', '')}")`
    };
  }

  // Credentials in the URL would end up in fixture requests and logs.
  if (parsed.username.length > 0 || parsed.password.length > 0) {
    return {
      ok: false,
      reason: 'MERZOX_TEST_API_URL must not embed credentials'
    };
  }

  const host = parsed.hostname.toLowerCase();
  if (!LOOPBACK_API_HOSTS.has(host)) {
    return {
      ok: false,
      reason: `MERZOX_TEST_API_URL host "${host}" is not loopback (the integration API must run locally against MERZOX_TEST_DB_URI)`
    };
  }

  return { ok: true };
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
  const apiCheck = validateIntegrationApiUrl(apiUrl);
  if (!apiCheck.ok) {
    return { enabled: false, reason: apiCheck.reason };
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


/**
 * The canonical hosts a connection string points at, credentials stripped.
 * Local aliases collapse to `localhost:<port>`, so loopback is one comparison.
 */
function canonicalHostsFromUri(uri) {
  const withoutScheme = String(uri ?? '')
    .trim()
    .replace(/^mongodb(\+srv)?:\/\//i, '');
  const atIndex = withoutScheme.lastIndexOf('@');
  const hostAndPath =
    atIndex === -1 ? withoutScheme : withoutScheme.slice(atIndex + 1);
  const slashIndex = hostAndPath.indexOf('/');
  const hostSection =
    slashIndex === -1 ? hostAndPath : hostAndPath.slice(0, slashIndex);

  return hostSection.split(',').map(canonicalHost).filter(Boolean);
}

/**
 * A second opt-in, on top of MERZOX_INTEGRATION_TESTS, for a database that is
 * disposable but not local.
 *
 * The loopback rule below exists because a suite that boots its own server has
 * no operator watching where it points. Naming this variable is that operator:
 * it has to be set deliberately, per run, by someone who knows which cluster
 * they are aiming at. Everything else still applies - the name must be marked
 * disposable and it must not resolve to the application's own database.
 */
export const REMOTE_OPT_IN = 'MERZOX_ALLOW_REMOTE_INTEGRATION_DB';

function allowsRemoteDatabase(env) {
  return String(env[REMOTE_OPT_IN] ?? '').trim() === 'true';
}

/**
 * The DB-only gate, for a suite that starts its own loopback API in-process
 * rather than talking to one somebody launched by hand.
 *
 * It keeps every safety rule of the full gate - explicit opt-in, a disposable
 * database name, no MONGODB_URI fallback - and adds one the API-based gate got
 * for free: the database host must be loopback, unless the run says in as many
 * words that it means to use a remote one.
 */
export function resolveIntegrationDatabase(env = process.env) {
  if (String(env.MERZOX_INTEGRATION_TESTS ?? '').trim() !== 'true') {
    return {
      enabled: false,
      reason:
        'MERZOX_INTEGRATION_TESTS is not "true" (explicit opt-in is required)'
    };
  }

  const dbUri = String(
    env.MERZOX_TEST_MONGODB_URI ?? env.MERZOX_TEST_DB_URI ?? ''
  ).trim();

  if (dbUri.length === 0) {
    return { enabled: false, reason: 'MERZOX_TEST_MONGODB_URI is not set' };
  }

  // An SRV record resolves to hosts this process cannot inspect, so it can
  // never be proved local. Refused outright.
  if (/^mongodb\+srv:/i.test(dbUri)) {
    return {
      enabled: false,
      reason: 'MERZOX_TEST_MONGODB_URI must not be a mongodb+srv connection'
    };
  }

  // Never borrow the application's own database, however it is spelled.
  const appUri = String(env.MONGODB_URI ?? '').trim();
  if (appUri.length > 0) {
    const appTarget = normalizedDatabaseTarget(appUri);
    const testTarget = normalizedDatabaseTarget(dbUri);

    if (appUri === dbUri || (appTarget.length > 0 && appTarget === testTarget)) {
      return {
        enabled: false,
        reason:
          'MERZOX_TEST_MONGODB_URI resolves to the same database as MONGODB_URI (refusing to mutate the application database)'
      };
    }
  }

  const hosts = canonicalHostsFromUri(dbUri);
  if (hosts.length === 0) {
    return { enabled: false, reason: 'MERZOX_TEST_MONGODB_URI names no host' };
  }

  const remote = hosts.filter((host) => !host.startsWith('localhost:'));
  if (remote.length > 0 && !allowsRemoteDatabase(env)) {
    return {
      enabled: false,
      reason:
        `MERZOX_TEST_MONGODB_URI must point at loopback only (${remote.length} non-loopback host); ` +
        `set ${REMOTE_OPT_IN} to true to allow a remote disposable database`
    };
  }

  const dbName = databaseNameFromUri(dbUri);
  if (dbName.length === 0) {
    return {
      enabled: false,
      reason: 'MERZOX_TEST_MONGODB_URI does not name a database'
    };
  }

  if (!isDisposableDatabaseName(dbName)) {
    return {
      enabled: false,
      reason: `database "${dbName}" is not marked disposable (name must contain one of: ${TEST_DB_MARKERS.join(', ')})`
    };
  }

  return { enabled: true, dbUri, dbName };
}

/** A collision-resistant identity so cleanup only ever removes its own rows. */
export function fixtureId(now) {
  return `${FIXTURE_PREFIX}-${now}`;
}
