import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

function read(relativePath) {
  return fs.readFileSync(
    new URL(
      relativePath,
      import.meta.url
    ),
    'utf8'
  );
}

const telemetry =
  read('../TELEMETRY.md');

const packageJson =
  JSON.parse(
    read('../package.json')
  );

const loggerSource =
  read('../src/observability/logger.js');

const requestContextSource =
  read('../src/middleware/request-context.js');

const dependencies = {
  ...(packageJson.dependencies ?? {}),
  ...(packageJson.devDependencies ?? {})
};

test(
  'telemetry contract is explicitly provider-neutral and not production activation evidence',
  () => {
    assert.match(
      telemetry,
      /provider-neutral telemetry and alerting contract/is
    );

    assert.match(
      telemetry,
      /does not select a logging vendor, metrics backend, tracing platform, error-reporting SDK, pager, or hosting provider/is
    );

    assert.match(
      telemetry,
      /not an activated production telemetry service/is
    );
  }
);

test(
  'existing application signals are the authoritative telemetry baseline',
  () => {
    for (
      const expected of [
        'http_request_completed',
        'http_request_aborted',
        'http_request_error',
        'X-Request-ID',
        'durationMs',
        'GET /health',
        'GET /ready'
      ]
    ) {
      assert.ok(
        telemetry.includes(expected),
        `missing baseline signal: ${expected}`
      );
    }

    assert.match(
      requestContextSource,
      /statusCode:\s*res\.statusCode/is
    );

    assert.match(
      requestContextSource,
      /durationMs/is
    );
  }
);

test(
  'structured logger keeps bounded status and duration fields available',
  () => {
    assert.match(
      loggerSource,
      /fields\.statusCode/is
    );

    assert.match(
      loggerSource,
      /min:\s*100[\s\S]*max:\s*599/is
    );

    assert.match(
      loggerSource,
      /fields\.durationMs/is
    );

    assert.match(
      loggerSource,
      /max:\s*86_400_000/is
    );
  }
);

test(
  'required operational visibility covers requests readiness lifecycle and critical delivery failures',
  () => {
    for (
      const expected of [
        'HTTP request volume',
        'HTTP status distribution, including 5xx failures',
        'request latency distribution',
        'aborted HTTP requests',
        'repeated or sustained `/ready` failures',
        'process starts, exits, restarts, and graceful-shutdown failures',
        'push provider initialization and delivery failures',
        'notification delivery failures',
        'email delivery fallback/failure events',
        'checkout reconciliation or compensation failures',
        'messaging compensation failures'
      ]
    ) {
      assert.ok(
        telemetry.includes(expected),
        `missing operational signal: ${expected}`
      );
    }
  }
);

test(
  'alerting contract defines conditions but does not invent production thresholds',
  () => {
    for (
      const expected of [
        'sustained readiness failure',
        'elevated HTTP 5xx rate',
        'latency degradation',
        'repeated process restarts or crash loops',
        'repeated graceful-shutdown failures',
        'repeated checkout reconciliation or compensation failures'
      ]
    ) {
      assert.ok(
        telemetry.includes(expected),
        `missing alert consideration: ${expected}`
      );
    }

    assert.match(
      telemetry,
      /does not invent SLOs, latency thresholds, error-rate thresholds, pager destinations, or retention durations/is
    );

    assert.equal(
      /99\.9%|99\.99%|p95\s*[<=>]|p99\s*[<=>]|alert after\s+\d+/i.test(
        telemetry
      ),
      false
    );
  }
);

test(
  'privacy boundary forbids customer content secrets and raw diagnostic payloads',
  () => {
    for (
      const expected of [
        'request bodies',
        'authorization headers',
        'cookies',
        'push targets',
        'verification URLs',
        'email recipients',
        'customer content',
        'raw database URIs',
        'raw provider responses',
        'stack traces',
        'unbounded error messages'
      ]
    ) {
      assert.ok(
        telemetry.includes(expected),
        `missing privacy boundary: ${expected}`
      );
    }
  }
);

test(
  'dedicated metrics and Prometheus endpoint remain optional architecture changes',
  () => {
    assert.match(
      telemetry,
      /dedicated in-process metrics library and `\/metrics` endpoint are not required by the current repository baseline/is
    );

    assert.match(
      telemetry,
      /No Prometheus-compatible endpoint should be added merely to satisfy this contract/is
    );

    assert.equal(
      dependencies['prom-client'],
      undefined
    );
  }
);

test(
  'distributed tracing and external error reporting remain optional',
  () => {
    assert.match(
      telemetry,
      /Distributed tracing is not required by the current single-backend-replica baseline/is
    );

    assert.match(
      telemetry,
      /external error-reporting SDK is optional/is
    );

    assert.equal(
      Object.keys(
        dependencies
      ).some(
        (name) =>
          name.startsWith('@opentelemetry/')
      ),
      false
    );

    assert.equal(
      dependencies['@sentry/node'],
      undefined
    );
  }
);

test(
  'health probe telemetry keeps liveness separate from readiness',
  () => {
    assert.match(
      telemetry,
      /`GET \/health` and `GET \/ready` remain authoritative health interfaces/is
    );

    assert.match(
      telemetry,
      /Alerting must distinguish process liveness from deployment readiness/is
    );
  }
);

test(
  'production telemetry acceptance requires real collector dashboard alert and drill evidence',
  () => {
    for (
      const expected of [
        'production log collector or equivalent platform facility',
        'structured JSON fields remain queryable',
        'dashboard or query evidence',
        'approved alert rules and responsible responder',
        'non-destructive alert-delivery drill',
        'configured retention and access controls'
      ]
    ) {
      assert.ok(
        telemetry.includes(expected),
        `missing activation evidence: ${expected}`
      );
    }
  }
);
