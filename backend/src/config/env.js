import dotenv from 'dotenv';

import {
  resolveEnvironment
} from './environment.js';

dotenv.config();

export const env =
  resolveEnvironment(
    process.env
  );
