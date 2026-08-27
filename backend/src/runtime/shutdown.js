function requiredFunction(value, name) {
  if (typeof value !== 'function') {
    throw new TypeError(
      `${name} must be a function`
    );
  }

  return value;
}

function normalizedTimerClear(clearTimer) {
  return typeof clearTimer === 'function'
    ? clearTimer
    : clearInterval;
}

/**
 * Closes a Node HTTP server without treating an already-closed server as an
 * error. Socket.IO may already have closed the attached HTTP server.
 */
export function closeHttpServer(server) {
  if (!server || server.listening !== true) {
    return Promise.resolve();
  }

  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (
        error &&
        error.code !== 'ERR_SERVER_NOT_RUNNING'
      ) {
        reject(error);
        return;
      }

      resolve();
    });
  });
}

/**
 * Creates one idempotent shutdown operation.
 *
 * Every cleanup step is attempted even if an earlier one fails. This prevents,
 * for example, a push-provider close failure from leaving MongoDB connected.
 */
export function createGracefulShutdown({
  markNotReady,
  reconcilerTimer = null,
  clearTimer = clearInterval,
  closePushProvider,
  closeRealtime,
  closeHttp,
  disconnectDatabase
}) {
  requiredFunction(
    markNotReady,
    'markNotReady'
  );

  requiredFunction(
    closePushProvider,
    'closePushProvider'
  );

  requiredFunction(
    closeRealtime,
    'closeRealtime'
  );

  requiredFunction(
    closeHttp,
    'closeHttp'
  );

  requiredFunction(
    disconnectDatabase,
    'disconnectDatabase'
  );

  const clearTimerFn =
    normalizedTimerClear(clearTimer);

  let shutdownPromise = null;

  return function shutdown() {
    if (shutdownPromise) {
      return shutdownPromise;
    }

    shutdownPromise = (async () => {
      const failures = [];

      const attempt = async (operation) => {
        try {
          await operation();
        } catch (error) {
          failures.push(error);
        }
      };

      await attempt(
        () => markNotReady()
      );

      await attempt(() => {
        if (reconcilerTimer) {
          clearTimerFn(
            reconcilerTimer
          );
        }
      });

      await attempt(
        () => closePushProvider()
      );

      // Socket.IO owns upgraded/long-polling transports and may close the
      // attached HTTP server itself. The HTTP close step remains explicit and
      // safely becomes a no-op when Socket.IO already completed it.
      await attempt(
        () => closeRealtime()
      );

      await attempt(
        () => closeHttp()
      );

      await attempt(
        () => disconnectDatabase()
      );

      if (failures.length > 0) {
        throw new AggregateError(
          failures,
          'Graceful shutdown failed'
        );
      }
    })();

    return shutdownPromise;
  };
}

/**
 * Installs process signal hooks without terminating the process directly.
 * Once all runtime handles close, Node exits naturally.
 */
export function registerProcessShutdownHandlers({
  shutdown,
  processRef = process,
  onFailure = () => {}
}) {
  requiredFunction(
    shutdown,
    'shutdown'
  );

  requiredFunction(
    onFailure,
    'onFailure'
  );

  const handler = () => {
    void shutdown().catch(
      onFailure
    );
  };

  processRef.once(
    'SIGTERM',
    handler
  );

  processRef.once(
    'SIGINT',
    handler
  );

  return function unregisterProcessShutdownHandlers() {
    processRef.off(
      'SIGTERM',
      handler
    );

    processRef.off(
      'SIGINT',
      handler
    );
  };
}
