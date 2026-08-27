import assert from 'node:assert/strict';
import test from 'node:test';

import {
  EnvironmentConfigurationError,
  resolveEnvironment
} from '../src/config/environment.js';

const LONG_SECRET =
  'x'.repeat(40);

function baseEnvironment(
  overrides = {}
) {
  return {
    MONGODB_URI:
      'mongodb://127.0.0.1:27017/merzox_test',
    JWT_SECRET:
      LONG_SECRET,
    ...overrides
  };
}

function rejectsWithCode(
  environment,
  code
) {
  assert.throws(
    () =>
      resolveEnvironment(
        environment
      ),
    (error) => {
      assert.equal(
        error instanceof
          EnvironmentConfigurationError,
        true
      );

      assert.equal(
        error.code,
        code
      );

      return true;
    }
  );
}

test(
  'development defaults remain compatible and deterministic',
  () => {
    const resolved =
      resolveEnvironment(
        baseEnvironment()
      );

    assert.equal(
      resolved.nodeEnv,
      'development'
    );

    assert.equal(
      resolved.port,
      4000
    );

    assert.equal(
      resolved.publicBaseUrl,
      'http://127.0.0.1:4000'
    );

    assert.equal(
      resolved.rateLimitWindowMs,
      900000
    );

    assert.equal(
      resolved.rateLimitMax,
      300
    );

    assert.equal(
      resolved.smtp.port,
      587
    );

    assert.equal(
      resolved.smtp.secure,
      false
    );

    assert.equal(
      resolved.firebasePushEnabled,
      false
    );
  }
);

test(
  'NODE_ENV is canonicalized and unknown environments fail closed',
  () => {
    assert.equal(
      resolveEnvironment(
        baseEnvironment({
          NODE_ENV:
            ' TEST '
        })
      ).nodeEnv,
      'test'
    );

    rejectsWithCode(
      baseEnvironment({
        NODE_ENV:
          'staging'
      }),
      'INVALID_NODE_ENV'
    );
  }
);

test(
  'required MongoDB and JWT settings cannot be blank',
  () => {
    rejectsWithCode(
      baseEnvironment({
        MONGODB_URI:
          ' '
      }),
      'MISSING_REQUIRED_ENV'
    );

    rejectsWithCode(
      baseEnvironment({
        JWT_SECRET:
          ''
      }),
      'MISSING_REQUIRED_ENV'
    );
  }
);

test(
  'PORT and SMTP_PORT require valid TCP port integers',
  () => {
    for (
      const value of [
        '0',
        '-1',
        '1.5',
        '65536',
        'abc'
      ]
    ) {
      rejectsWithCode(
        baseEnvironment({
          PORT:
            value
        }),
        'INVALID_NUMERIC_ENV'
      );

      rejectsWithCode(
        baseEnvironment({
          SMTP_PORT:
            value
        }),
        'INVALID_NUMERIC_ENV'
      );
    }

    assert.equal(
      resolveEnvironment(
        baseEnvironment({
          PORT:
            '65535'
        })
      ).port,
      65535
    );
  }
);

test(
  'rate-limit settings require positive safe integers',
  () => {
    for (
      const value of [
        '0',
        '-1',
        '1.5',
        'Infinity',
        'abc'
      ]
    ) {
      rejectsWithCode(
        baseEnvironment({
          RATE_LIMIT_WINDOW_MS:
            value
        }),
        'INVALID_NUMERIC_ENV'
      );

      rejectsWithCode(
        baseEnvironment({
          RATE_LIMIT_MAX:
            value
        }),
        'INVALID_NUMERIC_ENV'
      );
    }

    assert.equal(
      resolveEnvironment(
        baseEnvironment({
          RATE_LIMIT_MAX:
            '100000'
        })
      ).rateLimitMax,
      100000
    );
  }
);

test(
  'boolean environment flags accept only literal true or false',
  () => {
    const enabled =
      resolveEnvironment(
        baseEnvironment({
          SMTP_SECURE:
            'true',
          FIREBASE_PUSH_ENABLED:
            'true'
        })
      );

    assert.equal(
      enabled.smtp.secure,
      true
    );

    assert.equal(
      enabled.firebasePushEnabled,
      true
    );

    for (
      const value of [
        'TRUE',
        '1',
        'yes'
      ]
    ) {
      rejectsWithCode(
        baseEnvironment({
          SMTP_SECURE:
            value
        }),
        'INVALID_BOOLEAN_ENV'
      );

      rejectsWithCode(
        baseEnvironment({
          FIREBASE_PUSH_ENABLED:
            value
        }),
        'INVALID_BOOLEAN_ENV'
      );
    }
  }
);

test(
  'production requires a sufficiently long JWT secret',
  () => {
    rejectsWithCode(
      baseEnvironment({
        NODE_ENV:
          'production',
        JWT_SECRET:
          'too-short',
        PUBLIC_BASE_URL:
          'https://api.merzox.example',
        SMTP_HOST:
          'smtp.example',
        SMTP_USER:
          'mailer',
        SMTP_PASS:
          'not-a-real-secret',
        SMTP_FROM:
          'Merzox <no-reply@example.test>'
      }),
      'WEAK_JWT_SECRET'
    );
  }
);

test(
  'non-production preserves a configured legacy base URL without production enforcement',
  () => {
    assert.equal(
      resolveEnvironment(
        baseEnvironment({
          NODE_ENV:
            'test',
          PUBLIC_BASE_URL:
            'localhost:4000'
        })
      ).publicBaseUrl,
      'localhost:4000'
    );
  }
);

test(
  'production requires an explicit HTTPS public origin',
  () => {
    const production =
      baseEnvironment({
        NODE_ENV:
          'production',
        SMTP_HOST:
          'smtp.example',
        SMTP_USER:
          'mailer',
        SMTP_PASS:
          'not-a-real-secret',
        SMTP_FROM:
          'Merzox <no-reply@example.test>'
      });

    rejectsWithCode(
      production,
      'PUBLIC_BASE_URL_REQUIRED'
    );

    rejectsWithCode(
      {
        ...production,
        PUBLIC_BASE_URL:
          'http://api.merzox.example'
      },
      'PUBLIC_BASE_URL_HTTPS_REQUIRED'
    );

    for (
      const value of [
        'https://user:pass@api.merzox.example',
        'https://api.merzox.example/path',
        'https://api.merzox.example?x=1',
        'not-a-url'
      ]
    ) {
      rejectsWithCode(
        {
          ...production,
          PUBLIC_BASE_URL:
            value
        },
        'INVALID_PUBLIC_BASE_URL'
      );
    }
  }
);

test(
  'production requires complete SMTP delivery configuration',
  () => {
    rejectsWithCode(
      baseEnvironment({
        NODE_ENV:
          'production',
        PUBLIC_BASE_URL:
          'https://api.merzox.example'
      }),
      'SMTP_REQUIRED_IN_PRODUCTION'
    );
  }
);

test(
  'production CORS permits an empty deny-all list or exact HTTPS origins',
  () => {
    const production =
      baseEnvironment({
        NODE_ENV:
          'production',
        PUBLIC_BASE_URL:
          'https://api.merzox.example',
        SMTP_HOST:
          'smtp.example',
        SMTP_USER:
          'mailer',
        SMTP_PASS:
          'not-a-real-secret',
        SMTP_FROM:
          'Merzox <no-reply@example.test>'
      });

    assert.deepEqual(
      resolveEnvironment(
        production
      ).corsOrigins,
      []
    );

    assert.deepEqual(
      resolveEnvironment({
        ...production,
        CORS_ORIGINS:
          'https://merzox.example, https://admin.merzox.example/'
      }).corsOrigins,
      [
        'https://merzox.example',
        'https://admin.merzox.example'
      ]
    );

    rejectsWithCode(
      {
        ...production,
        CORS_ORIGINS:
          'https://merzox.example:*'
      },
      'INVALID_PRODUCTION_CORS_ORIGIN'
    );

    rejectsWithCode(
      {
        ...production,
        CORS_ORIGINS:
          'http://merzox.example'
      },
      'INVALID_PRODUCTION_CORS_ORIGIN'
    );
  }
);

test(
  'development keeps the existing wildcard CORS contract',
  () => {
    assert.deepEqual(
      resolveEnvironment(
        baseEnvironment({
          CORS_ORIGINS:
            'http://localhost:*,http://127.0.0.1:*'
        })
      ).corsOrigins,
      [
        'http://localhost:*',
        'http://127.0.0.1:*'
      ]
    );
  }
);

test(
  'configuration errors never expose supplied secret values',
  () => {
    const secret =
      'private-value-that-must-not-appear';

    try {
      resolveEnvironment({
        NODE_ENV:
          'production',
        MONGODB_URI:
          'mongodb://example.test/merzox',
        JWT_SECRET:
          secret,
        PUBLIC_BASE_URL:
          'not-a-url'
      });

      assert.fail(
        'configuration should have failed'
      );
    } catch (error) {
      const serialized =
        `${error.name} ${error.code} ${error.message} ${error.stack}`;

      assert.equal(
        serialized.includes(
          secret
        ),
        false
      );
    }
  }
);

test(
  'proxy trust is disabled by default',
  () => {
    assert.deepEqual(
      resolveEnvironment(
        baseEnvironment()
      ).trustedProxyRanges,
      []
    );
  }
);

test(
  'trusted proxies accept only explicit IP addresses and CIDR ranges',
  () => {
    assert.deepEqual(
      resolveEnvironment(
        baseEnvironment({
          TRUST_PROXY_RANGES:
            '127.0.0.1, 10.20.30.0/24, 2001:db8::/48, 127.0.0.1'
        })
      ).trustedProxyRanges,
      [
        '127.0.0.1',
        '10.20.30.0/24',
        '2001:db8::/48'
      ]
    );

    for (
      const value of [
        'true',
        '1',
        'loopback',
        'proxy.example.test',
        '10.0.0.0/33',
        '2001:db8::/129',
        '10.0.0.0/not-a-prefix'
      ]
    ) {
      rejectsWithCode(
        baseEnvironment({
          TRUST_PROXY_RANGES:
            value
        }),
        'INVALID_TRUST_PROXY_RANGE'
      );
    }
  }
);

test(
  'HTTP server defaults are bounded and deterministic',
  () => {
    const resolved =
      resolveEnvironment(
        baseEnvironment()
      );

    assert.deepEqual(
      resolved.httpServer,
      {
        requestTimeoutMs:
          30000,
        headersTimeoutMs:
          15000,
        keepAliveTimeoutMs:
          5000,
        connectionsCheckingIntervalMs:
          5000,
        maxHeadersCount:
          100,
        maxRequestsPerSocket:
          1000
      }
    );

    assert.equal(
      Object.isFrozen(
        resolved.httpServer
      ),
      true
    );
  }
);

test(
  'HTTP server policy accepts explicit bounded overrides',
  () => {
    const resolved =
      resolveEnvironment(
        baseEnvironment({
          HTTP_REQUEST_TIMEOUT_MS:
            '120000',
          HTTP_HEADERS_TIMEOUT_MS:
            '30000',
          HTTP_KEEP_ALIVE_TIMEOUT_MS:
            '10000',
          HTTP_CONNECTIONS_CHECKING_INTERVAL_MS:
            '5000',
          HTTP_MAX_HEADERS_COUNT:
            '250',
          HTTP_MAX_REQUESTS_PER_SOCKET:
            '5000'
        })
      );

    assert.deepEqual(
      resolved.httpServer,
      {
        requestTimeoutMs:
          120000,
        headersTimeoutMs:
          30000,
        keepAliveTimeoutMs:
          10000,
        connectionsCheckingIntervalMs:
          5000,
        maxHeadersCount:
          250,
        maxRequestsPerSocket:
          5000
      }
    );
  }
);

test(
  'HTTP server policy rejects zero negative fractional and excessive values',
  () => {
    for (
      const [
        key,
        value
      ] of [
        [
          'HTTP_REQUEST_TIMEOUT_MS',
          '0'
        ],
        [
          'HTTP_HEADERS_TIMEOUT_MS',
          '-1'
        ],
        [
          'HTTP_KEEP_ALIVE_TIMEOUT_MS',
          '1.5'
        ],
        [
          'HTTP_CONNECTIONS_CHECKING_INTERVAL_MS',
          'abc'
        ],
        [
          'HTTP_MAX_HEADERS_COUNT',
          '2001'
        ],
        [
          'HTTP_MAX_REQUESTS_PER_SOCKET',
          '100001'
        ]
      ]
    ) {
      rejectsWithCode(
        baseEnvironment({
          [key]:
            value
        }),
        'INVALID_NUMERIC_ENV'
      );
    }
  }
);

test(
  'HTTP headers timeout cannot exceed whole-request timeout',
  () => {
    rejectsWithCode(
      baseEnvironment({
        HTTP_REQUEST_TIMEOUT_MS:
          '10000',
        HTTP_HEADERS_TIMEOUT_MS:
          '15000'
      }),
      'INVALID_HTTP_TIMEOUT_RELATION'
    );
  }
);

test(
  'HTTP timeout sweep interval cannot exceed headers timeout',
  () => {
    rejectsWithCode(
      baseEnvironment({
        HTTP_HEADERS_TIMEOUT_MS:
          '4000',
        HTTP_CONNECTIONS_CHECKING_INTERVAL_MS:
          '5000'
      }),
      'INVALID_HTTP_TIMEOUT_RELATION'
    );
  }
);
