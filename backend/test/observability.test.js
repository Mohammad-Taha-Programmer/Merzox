import assert from 'node:assert/strict';
import {
  createServer
} from 'node:http';
import test from 'node:test';

import express from 'express';

import app from '../src/app.js';
import {
  errorLogFields
} from '../src/middleware/errorHandler.js';
import {
  createRequestContextMiddleware
} from '../src/middleware/request-context.js';
import {
  buildLogRecord,
  createStructuredLogger,
  isRequestId,
  sanitizeLogFields
} from '../src/observability/logger.js';
import { AppError } from '../src/utils/AppError.js';

const FIXED_REQUEST_ID =
  '123e4567-e89b-42d3-a456-426614174000';

function memoryStream() {
  const chunks = [];

  return {
    chunks,

    write(chunk) {
      chunks.push(
        String(chunk)
      );

      return true;
    }
  };
}

async function listen(server) {
  await new Promise(
    (resolve, reject) => {
      const onError = (error) => {
        reject(error);
      };

      server.once(
        'error',
        onError
      );

      server.listen(
        0,
        '127.0.0.1',
        () => {
          server.off(
            'error',
            onError
          );

          resolve();
        }
      );
    }
  );
}

async function close(server) {
  await new Promise(
    (resolve, reject) => {
      server.close(
        (error) => {
          if (error) {
            reject(error);
            return;
          }

          resolve();
        }
      );
    }
  );
}

test(
  'structured logger emits bounded JSON and drops unknown sensitive fields',
  () => {
    const stdout =
      memoryStream();

    const stderr =
      memoryStream();

    const structured =
      createStructuredLogger({
        stdout,
        stderr,
        enabled: true,
        now: () =>
          new Date(
            '2026-08-26T09:00:00.000Z'
          )
      });

    structured.info(
      'http_request_completed',
      {
        requestId:
          FIXED_REQUEST_ID,
        method: 'GET',
        route: '/:id',
        statusCode: 200,
        durationMs: 12.34567,

        authorization:
          'Bearer top-secret',
        body:
          'top-secret',
        query:
          'token=top-secret',
        email:
          'private@example.com'
      }
    );

    assert.equal(
      stdout.chunks.length,
      1
    );

    assert.equal(
      stderr.chunks.length,
      0
    );

    const raw =
      stdout.chunks[0];

    assert.equal(
      raw.includes(
        'top-secret'
      ),
      false
    );

    assert.equal(
      raw.includes(
        'private@example.com'
      ),
      false
    );

    assert.deepEqual(
      JSON.parse(raw),
      {
        timestamp:
          '2026-08-26T09:00:00.000Z',
        level: 'info',
        event:
          'http_request_completed',
        service:
          'merzox-api',
        requestId:
          FIXED_REQUEST_ID,
        method: 'GET',
        route: '/:id',
        statusCode: 200,
        durationMs: 12.346
      }
    );
  }
);

test(
  'logger rejects unsafe events and unsupported field shapes',
  () => {
    assert.throws(
      () =>
        buildLogRecord({
          level: 'info',
          event:
            'bad event value'
        }),
      TypeError
    );

    assert.deepEqual(
      sanitizeLogFields({
        requestId:
          'attacker-value',
        method:
          'GET\nSECRET',
        route:
          '/safe route with spaces',
        statusCode:
          999,
        durationMs:
          -1,
        appCode:
          'INVALID CODE',
        errorName:
          'Error:secret',
        errorCode: {
          secret: true
        }
      }),
      {}
    );
  }
);

test(
  'request middleware ignores inbound correlation identity and never logs raw URL secrets',
  async () => {
    const lines = [];

    const log = {
      info(
        event,
        fields
      ) {
        lines.push({
          event,
          fields
        });
      },

      warn(
        event,
        fields
      ) {
        lines.push({
          event,
          fields
        });
      }
    };

    const localApp =
      express();

    localApp.use(
      createRequestContextMiddleware({
        createId: () =>
          FIXED_REQUEST_ID,
        log
      })
    );

    localApp.get(
      '/items/:id',
      (_req, res) => {
        res.json({
          success: true
        });
      }
    );

    const server =
      createServer(
        localApp
      );

    await listen(server);

    const address =
      server.address();

    try {
      const response =
        await fetch(
          `http://127.0.0.1:${address.port}/items/secret-object-id?token=top-secret`,
          {
            headers: {
              'X-Request-ID':
                'client-controlled-id',
              Authorization:
                'Bearer top-secret'
            }
          }
        );

      assert.equal(
        response.status,
        200
      );

      assert.equal(
        response.headers.get(
          'x-request-id'
        ),
        FIXED_REQUEST_ID
      );

      await response.json();

      await new Promise(
        (resolve) =>
          setImmediate(resolve)
      );

      assert.equal(
        lines.length,
        1
      );

      assert.equal(
        lines[0].event,
        'http_request_completed'
      );

      assert.deepEqual(
        lines[0].fields,
        {
          requestId:
            FIXED_REQUEST_ID,
          method: 'GET',
          route:
            '/items/:id',
          statusCode: 200,
          durationMs:
            lines[0].fields.durationMs
        }
      );

      const serialized =
        JSON.stringify(lines);

      for (
        const forbidden of [
          'top-secret',
          'secret-object-id',
          'client-controlled-id',
          'Authorization'
        ]
      ) {
        assert.equal(
          serialized.includes(
            forbidden
          ),
          false,
          serialized
        );
      }
    } finally {
      await close(server);
    }
  }
);

test(
  'real app sends valid server request IDs for liveness and errors',
  async () => {
    const server =
      createServer(app);

    await listen(server);

    const address =
      server.address();

    try {
      for (
        const pathname of [
          '/health',
          '/definitely-missing?token=never-log-this'
        ]
      ) {
        const response =
          await fetch(
            `http://127.0.0.1:${address.port}${pathname}`,
            {
              headers: {
                'X-Request-ID':
                  'client-value-must-not-survive'
              }
            }
          );

        const requestId =
          response.headers.get(
            'x-request-id'
          );

        assert.equal(
          isRequestId(requestId),
          true
        );

        assert.notEqual(
          requestId,
          'client-value-must-not-survive'
        );

        await response.text();
      }
    } finally {
      await close(server);
    }
  }
);

test(
  'error correlation fields expose no message or stack',
  () => {
    const secret =
      'customer-secret-123';

    const error =
      new Error(
        `database failed for ${secret}`
      );

    error.stack =
      `STACK ${secret}`;

    error.code =
      11000;

    const normalized =
      new AppError(
        'A resource with this value already exists',
        409,
        'DUPLICATE_VALUE'
      );

    const fields =
      errorLogFields({
        error,
        normalized,
        requestId:
          FIXED_REQUEST_ID,
        statusCode: 409
      });

    const serialized =
      JSON.stringify(fields);

    assert.equal(
      serialized.includes(
        secret
      ),
      false
    );

    assert.deepEqual(
      fields,
      {
        requestId:
          FIXED_REQUEST_ID,
        statusCode: 409,
        appCode:
          'DUPLICATE_VALUE',
        errorName:
          'Error',
        errorCode:
          11000
      }
    );
  }
);
