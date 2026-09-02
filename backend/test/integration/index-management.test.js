import assert from 'node:assert/strict';
import test from 'node:test';

import mongoose from 'mongoose';

import {
  applyMissingIndexes,
  createIndexPlan,
  IndexManagementError,
  inspectIndexDrift,
  isIndexDriftClean
} from '../../src/scripts/index-management.js';
import {
  FIXTURE_PREFIX,
  resolveIntegrationDatabase
} from './test-environment.js';

const configuration =
  resolveIntegrationDatabase();

const COLLECTION_NAME =
  `${FIXTURE_PREFIX}_index_management`;

const EXPECTED_INDEX_NAME =
  'merzox_index_probe_owner_created';

const UNEXPECTED_INDEX_NAME =
  'merzox_index_probe_unexpected';

async function dropProbeCollection(
  connection
) {
  try {
    await connection.db.dropCollection(
      COLLECTION_NAME
    );
  } catch (error) {
    if (
      error?.code !== 26 &&
      error?.codeName !==
        'NamespaceNotFound'
    ) {
      throw error;
    }
  }
}

if (!configuration.enabled) {
  test(
    'INTEGRATION_INDEXES real Mongoose index lifecycle',
    {
      skip:
        `INTEGRATION_INDEXES=SKIPPED - ${configuration.reason}`
    },
    () => {}
  );
} else {
  test(
    'INTEGRATION_INDEXES real Mongoose index lifecycle',
    async () => {
      const connection =
        mongoose.createConnection();

      let opened = false;

      try {
        await connection.openUri(
          configuration.dbUri,
          {
            autoIndex: false,
            autoCreate: false,
            serverSelectionTimeoutMS:
              5000
          }
        );

        opened = true;

        await dropProbeCollection(
          connection
        );

        const schema =
          new mongoose.Schema(
            {
              ownerId: {
                type: String,
                required: true
              },

              createdAt: {
                type: Date,
                required: true
              }
            },
            {
              autoIndex: false,
              autoCreate: false,
              collection:
                COLLECTION_NAME
            }
          );

        schema.index(
          {
            ownerId: 1,
            createdAt: -1
          },
          {
            name:
              EXPECTED_INDEX_NAME
          }
        );

        const Probe =
          connection.model(
            'IndexManagementIntegrationProbe',
            schema,
            COLLECTION_NAME
          );

        await Probe.createCollection();

        const plan =
          createIndexPlan([
            Probe
          ]);

        assert.equal(
          plan.modelCount,
          1
        );

        assert.equal(
          plan.indexCount,
          1
        );

        const missing =
          await inspectIndexDrift([
            Probe
          ]);

        assert.equal(
          isIndexDriftClean(
            missing
          ),
          false
        );

        assert.equal(
          missing.length,
          1
        );

        assert.equal(
          missing[0].toDrop.length,
          0
        );

        assert.equal(
          missing[0].toCreate.length,
          1
        );

        const created =
          await applyMissingIndexes({
            models: [
              Probe
            ],
            drift:
              missing
          });

        assert.deepEqual(
          created,
          [
            COLLECTION_NAME
          ]
        );

        const clean =
          await inspectIndexDrift([
            Probe
          ]);

        assert.equal(
          isIndexDriftClean(
            clean
          ),
          true
        );

        const installedIndexes =
          await Probe.collection
            .indexes();

        assert.equal(
          installedIndexes.some(
            (index) =>
              index.name ===
                EXPECTED_INDEX_NAME
          ),
          true
        );

        await Probe.collection
          .createIndex(
            {
              unexpected: 1
            },
            {
              name:
                UNEXPECTED_INDEX_NAME
            }
          );

        const unsafe =
          await inspectIndexDrift([
            Probe
          ]);

        assert.equal(
          unsafe[0].toDrop.includes(
            UNEXPECTED_INDEX_NAME
          ),
          true
        );

        await assert.rejects(
          () =>
            applyMissingIndexes({
              models: [
                Probe
              ],
              drift:
                unsafe
            }),
          (error) =>
            error instanceof
              IndexManagementError &&
            error.code ===
              'INDEX_DROP_REFUSED'
        );

        const afterRefusal =
          await Probe.collection
            .indexes();

        assert.equal(
          afterRefusal.some(
            (index) =>
              index.name ===
                UNEXPECTED_INDEX_NAME
          ),
          true,
          'drop refusal must leave the unexpected index untouched'
        );

        console.log(
          'INTEGRATION_INDEXES=EXECUTED'
        );
      } finally {
        if (opened) {
          try {
            await dropProbeCollection(
              connection
            );
          } finally {
            await connection.close();
          }
        }
      }
    }
  );
}
