import {
  isIP
} from 'node:net';

const NODE_ENVIRONMENTS =
  new Set([
    'development',
    'test',
    'production'
  ]);

const MAX_TCP_PORT = 65535;
const MIN_PRODUCTION_JWT_SECRET_LENGTH = 32;

export class EnvironmentConfigurationError
  extends Error {
  constructor(code, message) {
    super(message);

    this.name =
      'EnvironmentConfigurationError';

    this.code =
      code;
  }
}

function configurationError(
  code,
  message
) {
  throw new EnvironmentConfigurationError(
    code,
    message
  );
}

function stringValue(
  source,
  key
) {
  const value =
    source?.[key];

  return typeof value === 'string'
    ? value
    : '';
}

function requiredString(
  source,
  key
) {
  const value =
    stringValue(
      source,
      key
    );

  if (!value.trim()) {
    configurationError(
      'MISSING_REQUIRED_ENV',
      `Missing required environment variable: ${key}`
    );
  }

  return value;
}

function positiveInteger({
  source,
  key,
  fallback,
  max =
    Number.MAX_SAFE_INTEGER
}) {
  const raw =
    stringValue(
      source,
      key
    ).trim();

  const candidate =
    raw === ''
      ? fallback
      : Number(raw);

  if (
    !Number.isSafeInteger(
      candidate
    ) ||
    candidate < 1 ||
    candidate > max
  ) {
    configurationError(
      'INVALID_NUMERIC_ENV',
      `${key} must be a positive integer in the supported range`
    );
  }

  return candidate;
}

function booleanValue({
  source,
  key,
  fallback
}) {
  const raw =
    stringValue(
      source,
      key
    ).trim();

  if (raw === '') {
    return fallback;
  }

  if (raw === 'true') {
    return true;
  }

  if (raw === 'false') {
    return false;
  }

  configurationError(
    'INVALID_BOOLEAN_ENV',
    `${key} must be either true or false`
  );
}

function resolveNodeEnv(
  source
) {
  const raw =
    stringValue(
      source,
      'NODE_ENV'
    ).trim();

  const nodeEnv =
    (
      raw ||
      'development'
    ).toLowerCase();

  if (
    !NODE_ENVIRONMENTS.has(
      nodeEnv
    )
  ) {
    configurationError(
      'INVALID_NODE_ENV',
      'NODE_ENV must be development, test, or production'
    );
  }

  return nodeEnv;
}

/**
 * Whether a string is an origin a browser could actually open.
 *
 * `new URL` alone is not enough: it accepts `http://${CURRENT_IP_ADDRESS}:x`
 * as a host of literal `${current_ip_address}`, which resolves nowhere.
 */
export function isUsableBaseUrl(value) {
  let parsed;

  try {
    parsed = new URL(value);
  } catch {
    return false;
  }

  return (
    ['http:', 'https:'].includes(parsed.protocol) &&
    parsed.hostname.length > 0 &&
    !/[${}\s]/.test(parsed.hostname) &&
    !/[${}\s]/.test(parsed.port)
  );
}

function resolvePublicBaseUrl({
  source,
  nodeEnv,
  port
}) {
  const configured =
    stringValue(
      source,
      'PUBLIC_BASE_URL'
    ).trim();

  const fallback = `http://127.0.0.1:${port}`;

  if (
    nodeEnv !== 'production'
  ) {
    if (configured === '') {
      return fallback;
    }

    // Outside production this value used to be taken verbatim, so a template
    // that was never filled in - `http://${CURRENT_IP_ADDRESS}:${PORT}` - went
    // straight into the address a verification email asks someone to open.
    // The link is unopenable and nothing said so. Refusing to boot over it
    // would be harsh for a development machine; falling back to the loopback
    // default keeps the link working, and the warning names what was ignored.
    if (!isUsableBaseUrl(configured)) {
      process.emitWarning(
        `PUBLIC_BASE_URL is not a usable http(s) origin (${configured}); ` +
          `using ${fallback} instead`,
        'MerzoxConfigurationWarning'
      );

      return fallback;
    }

    return configured;
  }

  if (configured === '') {
    configurationError(
      'PUBLIC_BASE_URL_REQUIRED',
      'PUBLIC_BASE_URL is required in production'
    );
  }

  let parsed;

  try {
    parsed =
      new URL(configured);
  } catch {
    configurationError(
      'INVALID_PUBLIC_BASE_URL',
      'PUBLIC_BASE_URL must be a valid HTTP(S) origin'
    );
  }

  if (
    parsed.protocol !== 'https:' ||
    parsed.username ||
    parsed.password ||
    parsed.pathname !== '/' ||
    parsed.search ||
    parsed.hash
  ) {
    if (
      parsed.protocol !== 'https:' &&
      [
        'http:',
        'https:'
      ].includes(
        parsed.protocol
      )
    ) {
      configurationError(
        'PUBLIC_BASE_URL_HTTPS_REQUIRED',
        'PUBLIC_BASE_URL must use HTTPS in production'
      );
    }

    configurationError(
      'INVALID_PUBLIC_BASE_URL',
      'PUBLIC_BASE_URL must be a valid HTTPS origin'
    );
  }

  return parsed.origin;
}

function resolveCorsOrigins({
  source,
  nodeEnv
}) {
  const origins =
    stringValue(
      source,
      'CORS_ORIGINS'
    )
      .split(',')
      .map(
        (origin) =>
          origin.trim()
      )
      .filter(Boolean);

  if (
    nodeEnv !== 'production'
  ) {
    return origins;
  }

  return origins.map(
    (origin) => {
      if (
        origin.includes('*')
      ) {
        configurationError(
          'INVALID_PRODUCTION_CORS_ORIGIN',
          'Production CORS origins must be exact HTTPS origins'
        );
      }

      let parsed;

      try {
        parsed =
          new URL(origin);
      } catch {
        configurationError(
          'INVALID_PRODUCTION_CORS_ORIGIN',
          'Production CORS origins must be exact HTTPS origins'
        );
      }

      if (
        parsed.protocol !== 'https:' ||
        parsed.username ||
        parsed.password ||
        parsed.pathname !== '/' ||
        parsed.search ||
        parsed.hash
      ) {
        configurationError(
          'INVALID_PRODUCTION_CORS_ORIGIN',
          'Production CORS origins must be exact HTTPS origins'
        );
      }

      return parsed.origin;
    }
  );
}

function isValidTrustedProxyRange(
  value
) {
  if (isIP(value)) {
    return true;
  }

  const parts =
    value.split('/');

  if (parts.length !== 2) {
    return false;
  }

  const [
    address,
    prefixText
  ] = parts;

  const family =
    isIP(address);

  if (!family) {
    return false;
  }

  if (!/^\d+$/.test(prefixText)) {
    return false;
  }

  const prefix =
    Number(prefixText);

  const maximum =
    family === 4
      ? 32
      : 128;

  return (
    Number.isInteger(prefix) &&
    prefix >= 0 &&
    prefix <= maximum
  );
}

function resolveTrustedProxyRanges(
  source
) {
  const raw =
    stringValue(
      source,
      'TRUST_PROXY_RANGES'
    );

  const ranges =
    raw
      .split(',')
      .map(
        (value) =>
          value.trim()
      )
      .filter(Boolean);

  const unique =
    [
      ...new Set(ranges)
    ];

  for (const range of unique) {
    if (
      !isValidTrustedProxyRange(
        range
      )
    ) {
      configurationError(
        'INVALID_TRUST_PROXY_RANGE',
        'TRUST_PROXY_RANGES must contain only explicit IP addresses or CIDR ranges'
      );
    }
  }

  return unique;
}

function resolveSmtp({
  source,
  nodeEnv
}) {
  const smtp = {
    host:
      stringValue(
        source,
        'SMTP_HOST'
      ).trim(),

    port:
      positiveInteger({
        source,
        key:
          'SMTP_PORT',
        fallback:
          587,
        max:
          MAX_TCP_PORT
      }),

    secure:
      booleanValue({
        source,
        key:
          'SMTP_SECURE',
        fallback:
          false
      }),

    user:
      stringValue(
        source,
        'SMTP_USER'
      ).trim(),

    pass:
      stringValue(
        source,
        'SMTP_PASS'
      ),

    from:
      (
        stringValue(
          source,
          'SMTP_FROM'
        ).trim() ||
        stringValue(
          source,
          'SMTP_USER'
        ).trim()
      )
  };

  if (
    nodeEnv === 'production' &&
    (
      !smtp.host ||
      !smtp.user ||
      !smtp.pass ||
      !smtp.from
    )
  ) {
    configurationError(
      'SMTP_REQUIRED_IN_PRODUCTION',
      'Complete SMTP configuration is required in production'
    );
  }

  return smtp;
}

function resolveHttpServer(
  source
) {
  const requestTimeoutMs =
    positiveInteger({
      source,
      key:
        'HTTP_REQUEST_TIMEOUT_MS',
      fallback:
        30_000,
      max:
        300_000
    });

  const headersTimeoutMs =
    positiveInteger({
      source,
      key:
        'HTTP_HEADERS_TIMEOUT_MS',
      fallback:
        15_000,
      max:
        60_000
    });

  const keepAliveTimeoutMs =
    positiveInteger({
      source,
      key:
        'HTTP_KEEP_ALIVE_TIMEOUT_MS',
      fallback:
        5_000,
      max:
        60_000
    });

  const connectionsCheckingIntervalMs =
    positiveInteger({
      source,
      key:
        'HTTP_CONNECTIONS_CHECKING_INTERVAL_MS',
      fallback:
        5_000,
      max:
        30_000
    });

  const maxHeadersCount =
    positiveInteger({
      source,
      key:
        'HTTP_MAX_HEADERS_COUNT',
      fallback:
        100,
      max:
        2_000
    });

  const maxRequestsPerSocket =
    positiveInteger({
      source,
      key:
        'HTTP_MAX_REQUESTS_PER_SOCKET',
      fallback:
        1_000,
      max:
        100_000
    });

  if (
    headersTimeoutMs >
      requestTimeoutMs
  ) {
    configurationError(
      'INVALID_HTTP_TIMEOUT_RELATION',
      'HTTP_HEADERS_TIMEOUT_MS must not exceed HTTP_REQUEST_TIMEOUT_MS'
    );
  }

  if (
    connectionsCheckingIntervalMs >
      headersTimeoutMs
  ) {
    configurationError(
      'INVALID_HTTP_TIMEOUT_RELATION',
      'HTTP_CONNECTIONS_CHECKING_INTERVAL_MS must not exceed HTTP_HEADERS_TIMEOUT_MS'
    );
  }

  return Object.freeze({
    requestTimeoutMs,
    headersTimeoutMs,
    keepAliveTimeoutMs,
    connectionsCheckingIntervalMs,
    maxHeadersCount,
    maxRequestsPerSocket
  });
}

export function resolveEnvironment(
  source
) {
  const nodeEnv =
    resolveNodeEnv(
      source
    );

  const port =
    positiveInteger({
      source,
      key:
        'PORT',
      fallback:
        4000,
      max:
        MAX_TCP_PORT
    });

  const mongoUri =
    requiredString(
      source,
      'MONGODB_URI'
    ).trim();

  const jwtSecret =
    requiredString(
      source,
      'JWT_SECRET'
    );

  if (
    nodeEnv === 'production' &&
    jwtSecret.length <
      MIN_PRODUCTION_JWT_SECRET_LENGTH
  ) {
    configurationError(
      'WEAK_JWT_SECRET',
      'JWT_SECRET must be at least 32 characters in production'
    );
  }

  return Object.freeze({
    nodeEnv,

    port,

    mongoUri,

    jwtSecret,

    jwtExpiresIn:
      (
        stringValue(
          source,
          'JWT_EXPIRES_IN'
        ).trim() ||
        '7d'
      ),

    httpServer:
      resolveHttpServer(
        source
      ),

    publicBaseUrl:
      resolvePublicBaseUrl({
        source,
        nodeEnv,
        port
      }),

    smtp:
      Object.freeze(
        resolveSmtp({
          source,
          nodeEnv
        })
      ),

    corsOrigins:
      Object.freeze(
        resolveCorsOrigins({
          source,
          nodeEnv
        })
      ),

    trustedProxyRanges:
      Object.freeze(
        resolveTrustedProxyRanges(
          source
        )
      ),

    rateLimitWindowMs:
      positiveInteger({
        source,
        key:
          'RATE_LIMIT_WINDOW_MS',
        fallback:
          900000
      }),

    rateLimitMax:
      positiveInteger({
        source,
        key:
          'RATE_LIMIT_MAX',
        fallback:
          300
      }),

    // The credential endpoints have their own budgets, configurable for the
    // same reason the global one is: an integration run seeds dozens of
    // accounts through the real HTTP API and would otherwise throttle itself.
    // The fallbacks are the production values.
    loginRateLimitMax:
      positiveInteger({
        source,
        key:
          'LOGIN_RATE_LIMIT_MAX',
        fallback:
          20
      }),

    signupRateLimitMax:
      positiveInteger({
        source,
        key:
          'SIGNUP_RATE_LIMIT_MAX',
        fallback:
          10
      }),

    firebasePushEnabled:
      booleanValue({
        source,
        key:
          'FIREBASE_PUSH_ENABLED',
        fallback:
          false
      })
  });
}
