import assert from 'node:assert/strict';
import {
  readFile
} from 'node:fs/promises';
import test from 'node:test';

import mongoose from 'mongoose';

import {
  applyMissingIndexes,
  createIndexPlan,
  INDEX_APPLY_ENV,
  IndexManagementError,
  inspectIndexDrift,
  isIndexDriftClean,
  parseIndexMode,
  validateIndexApplyApproval
} from '../src/scripts/index-management.js';
import {
  merzoxIndexModels
} from '../src/scripts/index-models.js';

function fakeModel({
  modelName =
    'Probe',
  collection =
    'probes',
  indexes =
    [],
  diff = {
    toDrop: [],
    toCreate: []
  },
  onCreate =
    async () => {}
} = {}) {
  return {
    modelName,

    collection: {
      collectionName:
        collection
    },

    schema: {
      indexes() {
        return indexes;
      }
    },

    async diffIndexes(options) {
      assert.deepEqual(
        options,
        {
          indexOptionsToCreate:
            true
        }
      );

      return diff;
    },

    async createIndexes() {
      await onCreate();
    }
  };
}

test(
  'real model registry yields the reviewed 12-model 54-index plan without connecting',
  () => {
    assert.equal(
      mongoose.connection.readyState,
      0
    );

    const plan =
      createIndexPlan(
        merzoxIndexModels
      );

    assert.equal(
      plan.kind,
      'merzox-mongodb-index-plan'
    );

    assert.equal(
      plan.version,
      1
    );

    assert.equal(
      plan.modelCount,
      12
    );

    assert.equal(
      plan.indexCount,
      54
    );

    assert.equal(
      plan.collections.length,
      12
    );

    assert.match(
      plan.planId,
      /^sha256:[a-f0-9]{64}$/
    );

    assert.equal(
      mongoose.connection.readyState,
      0
    );
  }
);

test(
  'the same schema inventory produces the same plan identity',
  () => {
    const first =
      createIndexPlan(
        merzoxIndexModels
      );

    const second =
      createIndexPlan(
        [...merzoxIndexModels]
          .reverse()
      );

    assert.equal(
      first.planId,
      second.planId
    );

    assert.deepEqual(
      first,
      second
    );
  }
);

test(
  'compound index key order participates in the approval identity',
  () => {
    const first =
      createIndexPlan([
        fakeModel({
          indexes: [
            [
              {
                first: 1,
                second: -1
              },
              {}
            ]
          ]
        })
      ]);

    const second =
      createIndexPlan([
        fakeModel({
          indexes: [
            [
              {
                second: -1,
                first: 1
              },
              {}
            ]
          ]
        })
      ]);

    assert.notEqual(
      first.planId,
      second.planId
    );
  }
);

test(
  'mode parsing fails closed',
  () => {
    assert.equal(
      parseIndexMode([
        'plan'
      ]),
      'plan'
    );

    assert.equal(
      parseIndexMode([
        'check'
      ]),
      'check'
    );

    assert.equal(
      parseIndexMode([
        'apply'
      ]),
      'apply'
    );

    for (
      const argv of [
        [],
        ['unknown'],
        ['plan', 'apply']
      ]
    ) {
      assert.throws(
        () =>
          parseIndexMode(
            argv
          ),
        IndexManagementError
      );
    }
  }
);

test(
  'apply approval requires exact true and the exact plan identity',
  () => {
    const planId =
      'sha256:' +
      'a'.repeat(64);

    assert.throws(
      () =>
        validateIndexApplyApproval({
          env: {},
          planId
        }),
      (error) =>
        error.code ===
          'INDEX_APPLY_OPT_IN_REQUIRED'
    );

    assert.throws(
      () =>
        validateIndexApplyApproval({
          env: {
            [
              INDEX_APPLY_ENV.allow
            ]:
              'true',
            [
              INDEX_APPLY_ENV.planId
            ]:
              'sha256:' +
              'b'.repeat(64)
          },
          planId
        }),
      (error) =>
        error.code ===
          'INDEX_PLAN_APPROVAL_MISMATCH'
    );

    assert.equal(
      validateIndexApplyApproval({
        env: {
          [
            INDEX_APPLY_ENV.allow
          ]:
            'true',
          [
            INDEX_APPLY_ENV.planId
          ]:
            planId
        },
        planId
      }),
      true
    );
  }
);

test(
  'drift inspection is read-only and reports missing indexes',
  async () => {
    const model =
      fakeModel({
        diff: {
          toDrop: [],
          toCreate: [
            [
              {
                marker: 1
              },
              {
                unique: true
              }
            ]
          ]
        }
      });

    const drift =
      await inspectIndexDrift([
        model
      ]);

    assert.equal(
      drift.length,
      1
    );

    assert.equal(
      drift[0].toDrop.length,
      0
    );

    assert.equal(
      drift[0].toCreate.length,
      1
    );

    assert.equal(
      isIndexDriftClean(
        drift
      ),
      false
    );
  }
);

test(
  'apply refuses every proposed index drop before creating anything',
  async () => {
    let createCalls = 0;

    const model =
      fakeModel({
        onCreate:
          async () => {
            createCalls += 1;
          }
      });

    await assert.rejects(
      applyMissingIndexes({
        models: [
          model
        ],
        drift: [
          {
            model:
              'Probe',
            collection:
              'probes',
            toDrop: [
              'unexpected_index'
            ],
            toCreate: [
              [
                {
                  marker: 1
                },
                {}
              ]
            ]
          }
        ]
      }),
      (error) =>
        error.code ===
          'INDEX_DROP_REFUSED'
    );

    assert.equal(
      createCalls,
      0
    );
  }
);

test(
  'apply creates indexes only for collections with missing definitions',
  async () => {
    const calls = [];

    const missing =
      fakeModel({
        modelName:
          'Missing',
        collection:
          'missing',
        onCreate:
          async () => {
            calls.push(
              'missing'
            );
          }
      });

    const clean =
      fakeModel({
        modelName:
          'Clean',
        collection:
          'clean',
        onCreate:
          async () => {
            calls.push(
              'clean'
            );
          }
      });

    const created =
      await applyMissingIndexes({
        models: [
          missing,
          clean
        ],
        drift: [
          {
            model:
              'Missing',
            collection:
              'missing',
            toDrop: [],
            toCreate: [
              [
                {
                  marker: 1
                },
                {}
              ]
            ]
          },
          {
            model:
              'Clean',
            collection:
              'clean',
            toDrop: [],
            toCreate: []
          }
        ]
      });

    assert.deepEqual(
      calls,
      [
        'missing'
      ]
    );

    assert.deepEqual(
      created,
      [
        'missing'
      ]
    );
  }
);

test(
  'operational CLI keeps mutations and diagnostics fail closed',
  async () => {
    const cliSource =
      await readFile(
        new URL(
          '../src/scripts/indexes.js',
          import.meta.url
        ),
        'utf8'
      );

    const commandSource =
      await readFile(
        new URL(
          '../src/scripts/index-command.js',
          import.meta.url
        ),
        'utf8'
      );

    for (
      const required of [
        'executeIndexCommand',
        'safeCliErrorSummary',
        'autoIndex: false',
        'autoCreate: false',
        'serverSelectionTimeoutMS: 5000',
        'process.exitCode'
      ]
    ) {
      assert.equal(
        cliSource.includes(required),
        true,
        required
      );
    }

    assert.equal(
      /\bmongoose\.connect\s*\(/u.test(
        cliSource
      ),
      true,
      'mongoose.connect call'
    );

    for (
      const forbidden of [
        'syncIndexes',
        'dropIndex(',
        'dropIndexes(',
        'error.message',
        'error.stack',
        'process.exit('
      ]
    ) {
      assert.equal(
        (
          cliSource +
          commandSource
        ).includes(forbidden),
        false,
        forbidden
      );
    }

    assert.equal(
      commandSource.includes(
        'validateIndexApplyApproval'
      ),
      true
    );

    assert.equal(
      commandSource.includes(
        'INDEX_APPLY_VERIFICATION_FAILED'
      ),
      true
    );

    assert.equal(
      commandSource.includes(
        'INDEX_DATABASE_URI_REQUIRED'
      ),
      true
    );
  }
);
