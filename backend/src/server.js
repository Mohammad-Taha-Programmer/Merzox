import app from './app.js';
import { connectDatabase } from './config/database.js';
import { env } from './config/env.js';

async function start() {
  await connectDatabase();

  app.listen(env.port, () => {
    console.log(`Merzox API listening on port ${env.port}`);
  });
}

start().catch((error) => {
  console.error('Failed to start Merzox API', error);
  process.exit(1);
});
