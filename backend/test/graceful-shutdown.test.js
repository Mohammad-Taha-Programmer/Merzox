import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import test from 'node:test';

import {
  closeHttpServer,
  createGracefulShutdown,
  registerProcessShutdownHandlers
} from '../src/runtime/shutdown.js';

test(
  'graceful shutdown closes runtime resources in the declared order',
  async () => {
    const calls = [];
    const timer = {};

    const shutdown =
      createGracefulShutdown({
        markNotReady() {
          calls.push(
            'readiness-off'
          );
        },
        reconcilerTimer: timer,
        clearTimer(value) {
          assert.equal(
            value,
            timer
          );

          calls.push(
            'reconciler-stop'
          );
        },
        closePushProvider() {
          calls.push(
            'push-close'
          );
        },
        async closeRealtime() {
          calls.push(
            'realtime-close'
          );
        },
        async closeHttp() {
          calls.push(
            'http-close'
          );
        },
        async disconnectDatabase() {
          calls.push(
            'database-disconnect'
          );
        }
      });

    await shutdown();

    assert.deepEqual(
      calls,
      [
        'readiness-off',
        'reconciler-stop',
        'push-close',
        'realtime-close',
        'http-close',
        'database-disconnect'
      ]
    );
  }
);

test(
  'graceful shutdown is idempotent and returns one shared promise',
  async () => {
    let disconnects = 0;

    const shutdown =
      createGracefulShutdown({
        markNotReady() {},
        closePushProvider() {},
        async closeRealtime() {},
        async closeHttp() {},
        async disconnectDatabase() {
          disconnects += 1;
        }
      });

    const first = shutdown();
    const second = shutdown();
    const third = shutdown();

    assert.equal(
      first,
      second
    );

    assert.equal(
      second,
      third
    );

    await Promise.all([
      first,
      second,
      third
    ]);

    assert.equal(
      disconnects,
      1
    );
  }
);

test(
  'one cleanup failure never prevents later cleanup steps',
  async () => {
    const calls = [];

    const shutdown =
      createGracefulShutdown({
        markNotReady() {
          calls.push(
            'readiness-off'
          );
        },
        closePushProvider() {
          calls.push(
            'push-close'
          );

          throw new Error(
            'provider failure'
          );
        },
        async closeRealtime() {
          calls.push(
            'realtime-close'
          );
        },
        async closeHttp() {
          calls.push(
            'http-close'
          );
        },
        async disconnectDatabase() {
          calls.push(
            'database-disconnect'
          );
        }
      });

    await assert.rejects(
      shutdown(),
      AggregateError
    );

    assert.deepEqual(
      calls,
      [
        'readiness-off',
        'push-close',
        'realtime-close',
        'http-close',
        'database-disconnect'
      ]
    );
  }
);

test(
  'HTTP close is a no-op when Socket.IO already closed the server',
  async () => {
    let closeCalls = 0;

    await closeHttpServer({
      listening: false,
      close() {
        closeCalls += 1;
      }
    });

    assert.equal(
      closeCalls,
      0
    );
  }
);

test(
  'HTTP close waits for the server close callback',
  async () => {
    const events = [];

    const server = {
      listening: true,
      close(callback) {
        events.push(
          'close-start'
        );

        queueMicrotask(() => {
          events.push(
            'close-finish'
          );

          callback();
        });
      }
    };

    await closeHttpServer(
      server
    );

    assert.deepEqual(
      events,
      [
        'close-start',
        'close-finish'
      ]
    );
  }
);

test(
  'SIGTERM and SIGINT reuse the same idempotent shutdown',
  async () => {
    const processRef =
      new EventEmitter();

    let runs = 0;

    const shutdown =
      createGracefulShutdown({
        markNotReady() {
          runs += 1;
        },
        closePushProvider() {},
        async closeRealtime() {},
        async closeHttp() {},
        async disconnectDatabase() {}
      });

    const unregister =
      registerProcessShutdownHandlers({
        shutdown,
        processRef
      });

    processRef.emit(
      'SIGTERM'
    );

    processRef.emit(
      'SIGINT'
    );

    await shutdown();

    assert.equal(
      runs,
      1
    );

    unregister();

    assert.equal(
      processRef.listenerCount(
        'SIGTERM'
      ),
      0
    );

    assert.equal(
      processRef.listenerCount(
        'SIGINT'
      ),
      0
    );
  }
);

test(
  'signal cleanup failure is reported without direct process termination',
  async () => {
    const processRef =
      new EventEmitter();

    let failureCount = 0;

    const shutdown =
      createGracefulShutdown({
        markNotReady() {},
        closePushProvider() {
          throw new Error(
            'close failed'
          );
        },
        async closeRealtime() {},
        async closeHttp() {},
        async disconnectDatabase() {}
      });

    registerProcessShutdownHandlers({
      shutdown,
      processRef,
      onFailure() {
        failureCount += 1;
      }
    });

    processRef.emit(
      'SIGTERM'
    );

    await assert.rejects(
      shutdown(),
      AggregateError
    );

    await new Promise(
      (resolve) =>
        setImmediate(resolve)
    );

    assert.equal(
      failureCount,
      1
    );
  }
);
