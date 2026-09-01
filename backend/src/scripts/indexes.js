import 'dotenv/config';

import mongoose from 'mongoose';

import {
  safeCliErrorSummary
} from './cli-safety.js';
import {
  executeIndexCommand
} from './index-command.js';
import {
  parseIndexMode
} from './index-management.js';
import {
  merzoxIndexModels
} from './index-models.js';

const CONNECTION_OPTIONS =
  Object.freeze({
    autoIndex: false,
    autoCreate: false,
    serverSelectionTimeoutMS: 5000
  });

async function run() {
  const mode =
    parseIndexMode(
      process.argv.slice(2)
    );

  const result =
    await executeIndexCommand({
      mode,
      models:
        merzoxIndexModels,
      env:
        process.env,

      connect:
        async (uri) => {
          await mongoose.connect(
            uri,
            CONNECTION_OPTIONS
          );
        },

      disconnect:
        async () => {
          await mongoose.disconnect();
        }
    });

  console.log(
    JSON.stringify(
      result.payload,
      null,
      2
    )
  );

  process.exitCode =
    result.exitCode;
}

run().catch(
  (error) => {
    console.error(
      JSON.stringify({
        status:
          'error',
        ...safeCliErrorSummary(
          error
        )
      })
    );

    process.exitCode = 1;
  }
);
