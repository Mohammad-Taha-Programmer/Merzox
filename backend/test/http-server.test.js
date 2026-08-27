import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createConfiguredHttpServer
} from '../src/runtime/http-server.js';

const HTTP_POLICY =
  Object.freeze({
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
  });

test(
  'configured HTTP server applies the declared parser and connection policy',
  () => {
    const server =
      createConfiguredHttpServer(
        (_req, res) => {
          res.end('ok');
        },
        HTTP_POLICY
      );

    assert.equal(
      server.requestTimeout,
      30000
    );

    assert.equal(
      server.headersTimeout,
      15000
    );

    assert.equal(
      server.keepAliveTimeout,
      5000
    );

    assert.equal(
      server.connectionsCheckingInterval,
      5000
    );

    assert.equal(
      server.maxHeadersCount,
      100
    );

    assert.equal(
      server.maxRequestsPerSocket,
      1000
    );
  }
);

test(
  'generic HTTP socket inactivity timeout remains disabled for shared realtime transport',
  () => {
    const server =
      createConfiguredHttpServer(
        (_req, res) => {
          res.end('ok');
        },
        HTTP_POLICY
      );

    assert.equal(
      server.timeout,
      0
    );
  }
);
