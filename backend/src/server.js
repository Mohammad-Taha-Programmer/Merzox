import { createServer } from 'node:http';

import app from './app.js';
import { connectDatabase } from './config/database.js';
import { env } from './config/env.js';
import { createRealtimeServer } from './realtime/realtime.gateway.js';
import { initializeFirebasePushProvider } from './push/firebase-push.provider.js';
import { startCheckoutReconciler } from './services/checkout-reconciler.service.js';

async function start() {
  await connectDatabase();

  initializeFirebasePushProvider();

  // Recovers checkouts whose client never came back - including anything the
  // previous process left mid-flight. The sweep is bounded and its timer is
  // unref'd, so startup never waits on it and it can never hold the process up.
  startCheckoutReconciler();

  const server = createServer(app);

  createRealtimeServer(server);

  server.listen(env.port, () => {
    console.log(
      `Merzox API listening on port ${env.port}`
    );
  });
}

start().catch((error) => {
  console.error(
    'Failed to start Merzox API',
    error
  );
  process.exit(1);
});
