import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import test from 'node:test';

import app from '../src/app.js';
import {
  currentReadiness,
  evaluateReadiness,
  markRuntimeNotReady,
  markRuntimeReady,
  registerDatabaseReadinessProbe
} from '../src/runtime/readiness.js';

async function request(pathname) {
  const server = createServer(app);

  await new Promise((resolve, reject) => {
    const onError = (error) => {
      reject(error);
    };

    server.once('error', onError);

    server.listen(0, '127.0.0.1', () => {
      server.off('error', onError);
      resolve();
    });
  });

  const address = server.address();

  try {
    const response = await fetch(
      `http://127.0.0.1:${address.port}${pathname}`
    );

    return {
      status: response.status,
      body: await response.json()
    };
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
}

test(
  'readiness contract is fail-closed and separates liveness from readiness',
  async (t) => {
    await t.test(
      'pure readiness requires both runtime and database readiness',
      () => {
        assert.deepEqual(
          evaluateReadiness({
            acceptingTraffic: true,
            databaseReady: true
          }),
          {
            ready: true,
            status: 'ready',
            service: 'merzox-api'
          }
        );

        for (const input of [
          {
            acceptingTraffic: false,
            databaseReady: true
          },
          {
            acceptingTraffic: true,
            databaseReady: false
          },
          {
            acceptingTraffic: false,
            databaseReady: false
          }
        ]) {
          assert.deepEqual(
            evaluateReadiness(input),
            {
              ready: false,
              status: 'not_ready',
              service: 'merzox-api'
            }
          );
        }
      }
    );

    await t.test(
      'readiness probe exceptions fail closed',
      () => {
        markRuntimeReady();

        const unregister =
          registerDatabaseReadinessProbe(
            () => {
              throw new Error(
                'database details must not escape'
              );
            }
          );

        try {
          assert.deepEqual(
            currentReadiness(),
            {
              ready: false,
              status: 'not_ready',
              service: 'merzox-api'
            }
          );
        } finally {
          markRuntimeNotReady();
          unregister();
        }
      }
    );

    await t.test(
      '/ready returns 503 before runtime starts accepting traffic',
      async () => {
        markRuntimeNotReady();

        const unregister =
          registerDatabaseReadinessProbe(
            () => true
          );

        try {
          const response =
            await request('/ready');

          assert.equal(
            response.status,
            503
          );

          assert.deepEqual(
            response.body,
            {
              success: false,
              data: {
                status: 'not_ready',
                service: 'merzox-api'
              }
            }
          );
        } finally {
          markRuntimeNotReady();
          unregister();
        }
      }
    );

    await t.test(
      '/ready returns 503 when MongoDB is not ready',
      async () => {
        markRuntimeReady();

        const unregister =
          registerDatabaseReadinessProbe(
            () => false
          );

        try {
          const response =
            await request('/ready');

          assert.equal(
            response.status,
            503
          );

          assert.equal(
            response.body.success,
            false
          );
        } finally {
          markRuntimeNotReady();
          unregister();
        }
      }
    );

    await t.test(
      '/ready returns 200 only when runtime and database are ready',
      async () => {
        markRuntimeReady();

        const unregister =
          registerDatabaseReadinessProbe(
            () => true
          );

        try {
          const response =
            await request('/ready');

          assert.equal(
            response.status,
            200
          );

          assert.deepEqual(
            response.body,
            {
              success: true,
              data: {
                status: 'ready',
                service: 'merzox-api'
              }
            }
          );
        } finally {
          markRuntimeNotReady();
          unregister();
        }
      }
    );

    await t.test(
      '/health remains live even while readiness is false',
      async () => {
        markRuntimeNotReady();

        const unregister =
          registerDatabaseReadinessProbe(
            () => false
          );

        try {
          const response =
            await request('/health');

          assert.equal(
            response.status,
            200
          );

          assert.deepEqual(
            response.body,
            {
              success: true,
              data: {
                status: 'ok',
                service: 'merzox-api'
              }
            }
          );
        } finally {
          markRuntimeNotReady();
          unregister();
        }
      }
    );
  }
);
