import { createConfiguredHttpServer } from './runtime/http-server.js';

import app from './app.js';
import { logger } from './observability/logger.js';
import {
  safeErrorCode,
  safeErrorName
} from './utils/safe-log.js';
import {
  connectDatabase,
  disconnectDatabase,
  isDatabaseReady
} from './config/database.js';
import { env } from './config/env.js';
import {
  closeRealtimeServer,
  createRealtimeServer
} from './realtime/realtime.gateway.js';
import {
  closeFirebasePushProvider,
  initializeFirebasePushProvider
} from './push/firebase-push.provider.js';
import { startCheckoutReconciler } from './services/checkout-reconciler.service.js';
import {
  markRuntimeNotReady,
  markRuntimeReady,
  registerDatabaseReadinessProbe
} from './runtime/readiness.js';
import {
  closeHttpServer,
  createGracefulShutdown,
  registerProcessShutdownHandlers
} from './runtime/shutdown.js';

async function start() {
  registerDatabaseReadinessProbe(
    isDatabaseReady
  );

  await connectDatabase();

  initializeFirebasePushProvider();

  // Recovers checkouts whose client never came back - including anything the
  // previous process left mid-flight. The sweep is bounded and its timer is
  // unref'd, so startup never waits on it and it can never hold the process up.
  const reconcilerTimer =
    startCheckoutReconciler();

  const server =
    createConfiguredHttpServer(
      app,
      env.httpServer
    );

  const io =
    createRealtimeServer(server);

  const shutdown =
    createGracefulShutdown({
      markNotReady:
        markRuntimeNotReady,
      reconcilerTimer,
      closePushProvider:
        closeFirebasePushProvider,
      closeRealtime: () =>
        closeRealtimeServer(io),
      closeHttp: () =>
        closeHttpServer(server),
      disconnectDatabase
    });

  registerProcessShutdownHandlers({
    shutdown,
    onFailure(error) {
      logger.error(
        'graceful_shutdown_failed',
        {
          errorName:
            safeErrorName(error),
          errorCode:
            safeErrorCode(error)
        }
      );

      process.exitCode = 1;
    }
  });

  await new Promise((resolve, reject) => {
    const onError = (error) => {
      reject(error);
    };

    server.once('error', onError);

    server.listen(env.port, () => {
      server.off('error', onError);
      resolve();
    });
  });

  markRuntimeReady();

  logger.info(
    'server_listening',
    {
      port: env.port
    }
  );
}

start().catch(async (error) => {
  markRuntimeNotReady();

  logger.error(
    'server_start_failed',
    {
      errorName:
        safeErrorName(error),
      errorCode:
        safeErrorCode(error)
    }
  );

  try {
    closeFirebasePushProvider();
    await disconnectDatabase();
  } catch (cleanupError) {
    logger.error(
      'startup_cleanup_failed',
      {
        errorName:
          safeErrorName(
            cleanupError
          ),
        errorCode:
          safeErrorCode(
            cleanupError
          )
      }
    );
  }

  process.exitCode = 1;
});
