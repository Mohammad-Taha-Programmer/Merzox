import assert from 'node:assert/strict';
import test from 'node:test';

import {
  executeIndexCommand
} from '../src/scripts/index-command.js';
import {
  createIndexPlan,
  INDEX_APPLY_ENV,
  IndexManagementError
} from '../src/scripts/index-management.js';

function fakeCommandModel({
  collection = 'commandprobes',
  diffs = [
    {
      toDrop: [],
      toCreate: []
    }
  ]
} = {}) {
  const state = {
    diffCalls: 0,
    createCalls: 0
  };

  const model = {
    modelName: 'CommandProbe',

    collection: {
      collectionName:
        collection
    },

    schema: {
      indexes() {
        return [
          [
            {
              value: 1
            },
            {
              name:
                'value_1'
            }
          ]
        ];
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

      const position =
        Math.min(
          state.diffCalls,
          diffs.length - 1
        );

      state.diffCalls += 1;

      return diffs[position];
    },

    async createIndexes() {
      state.createCalls += 1;
    }
  };

  return {
    model,
    state
  };
}

function connectionRecorder() {
  const state = {
    connectedUris: [],
    disconnectCalls: 0
  };

  return {
    state,

    async connect(uri) {
      state.connectedUris.push(uri);
    },

    async disconnect() {
      state.disconnectCalls += 1;
    }
  };
}

test(
  'plan mode never asks for a URI or opens a connection',
  async () => {
    const probe =
      fakeCommandModel();

    const result =
      await executeIndexCommand({
        mode: 'plan',
        models: [
          probe.model
        ],
        env: {
          MONGODB_URI:
            'must-not-be-used'
        },

        connect: async () => {
          assert.fail(
            'plan attempted to connect'
          );
        },

        disconnect: async () => {
          assert.fail(
            'plan attempted to disconnect'
          );
        }
      });

    assert.equal(
      result.exitCode,
      0
    );

    assert.equal(
      result.payload.kind,
      'merzox-mongodb-index-plan'
    );

    assert.equal(
      probe.state.diffCalls,
      0
    );
  }
);

test(
  'check mode reports drift with exit code two and always disconnects',
  async () => {
    const probe =
      fakeCommandModel({
        diffs: [
          {
            toDrop: [],
            toCreate: [
              [
                {
                  value: 1
                },
                {
                  name:
                    'value_1'
                }
              ]
            ]
          }
        ]
      });

    const connection =
      connectionRecorder();

    const result =
      await executeIndexCommand({
        mode: 'check',
        models: [
          probe.model
        ],
        env: {
          MONGODB_URI:
            'mongodb://index-check.example/merzox'
        },
        connect:
          connection.connect,
        disconnect:
          connection.disconnect
      });

    assert.equal(
      result.exitCode,
      2
    );

    assert.equal(
      result.payload.clean,
      false
    );

    assert.deepEqual(
      connection.state.connectedUris,
      [
        'mongodb://index-check.example/merzox'
      ]
    );

    assert.equal(
      connection.state.disconnectCalls,
      1
    );

    assert.equal(
      probe.state.createCalls,
      0
    );
  }
);

test(
  'clean check mode exits successfully without creating indexes',
  async () => {
    const probe =
      fakeCommandModel();

    const connection =
      connectionRecorder();

    const result =
      await executeIndexCommand({
        mode: 'check',
        models: [
          probe.model
        ],
        env: {
          MONGODB_URI:
            'mongodb://clean-check.example/merzox'
        },
        connect:
          connection.connect,
        disconnect:
          connection.disconnect
      });

    assert.equal(
      result.exitCode,
      0
    );

    assert.equal(
      result.payload.clean,
      true
    );

    assert.equal(
      probe.state.createCalls,
      0
    );

    assert.equal(
      connection.state.disconnectCalls,
      1
    );
  }
);

test(
  'apply refuses a missing opt-in before any connection attempt',
  async () => {
    const probe =
      fakeCommandModel();

    const plan =
      createIndexPlan([
        probe.model
      ]);

    let connectCalls = 0;

    await assert.rejects(
      () =>
        executeIndexCommand({
          mode: 'apply',
          models: [
            probe.model
          ],
          env: {
            MONGODB_URI:
              'mongodb://must-not-connect.example/merzox',
            [
              INDEX_APPLY_ENV.planId
            ]:
              plan.planId
          },

          connect: async () => {
            connectCalls += 1;
          },

          disconnect: async () => {}
        }),
      (error) =>
        error instanceof
          IndexManagementError &&
        error.code ===
          'INDEX_APPLY_OPT_IN_REQUIRED'
    );

    assert.equal(
      connectCalls,
      0
    );
  }
);

test(
  'apply refuses a mismatched plan before any connection attempt',
  async () => {
    const probe =
      fakeCommandModel();

    let connectCalls = 0;

    await assert.rejects(
      () =>
        executeIndexCommand({
          mode: 'apply',
          models: [
            probe.model
          ],
          env: {
            MONGODB_URI:
              'mongodb://must-not-connect.example/merzox',
            [
              INDEX_APPLY_ENV.allow
            ]:
              'true',
            [
              INDEX_APPLY_ENV.planId
            ]:
              'sha256:wrong'
          },

          connect: async () => {
            connectCalls += 1;
          },

          disconnect: async () => {}
        }),
      (error) =>
        error instanceof
          IndexManagementError &&
        error.code ===
          'INDEX_PLAN_APPROVAL_MISMATCH'
    );

    assert.equal(
      connectCalls,
      0
    );
  }
);

test(
  'apply creates only missing indexes then verifies a clean result',
  async () => {
    const missing = {
      toDrop: [],
      toCreate: [
        [
          {
            value: 1
          },
          {
            name:
              'value_1'
          }
        ]
      ]
    };

    const clean = {
      toDrop: [],
      toCreate: []
    };

    const probe =
      fakeCommandModel({
        diffs: [
          missing,
          clean
        ]
      });

    const plan =
      createIndexPlan([
        probe.model
      ]);

    const connection =
      connectionRecorder();

    const result =
      await executeIndexCommand({
        mode: 'apply',
        models: [
          probe.model
        ],
        env: {
          MONGODB_URI:
            'mongodb://approved.example/merzox',
          [
            INDEX_APPLY_ENV.allow
          ]:
            'true',
          [
            INDEX_APPLY_ENV.planId
          ]:
            plan.planId
        },
        connect:
          connection.connect,
        disconnect:
          connection.disconnect
      });

    assert.equal(
      result.exitCode,
      0
    );

    assert.equal(
      result.payload.clean,
      true
    );

    assert.deepEqual(
      result.payload
        .createdCollections,
      [
        'commandprobes'
      ]
    );

    assert.equal(
      probe.state.createCalls,
      1
    );

    assert.equal(
      probe.state.diffCalls,
      2
    );

    assert.equal(
      connection.state.disconnectCalls,
      1
    );
  }
);

test(
  'apply refuses proposed drops and still disconnects',
  async () => {
    const probe =
      fakeCommandModel({
        diffs: [
          {
            toDrop: [
              'unexpected_1'
            ],
            toCreate: []
          }
        ]
      });

    const plan =
      createIndexPlan([
        probe.model
      ]);

    const connection =
      connectionRecorder();

    await assert.rejects(
      () =>
        executeIndexCommand({
          mode: 'apply',
          models: [
            probe.model
          ],
          env: {
            MONGODB_URI:
              'mongodb://drop-refusal.example/merzox',
            [
              INDEX_APPLY_ENV.allow
            ]:
              'true',
            [
              INDEX_APPLY_ENV.planId
            ]:
              plan.planId
          },
          connect:
            connection.connect,
          disconnect:
            connection.disconnect
        }),
      (error) =>
        error instanceof
          IndexManagementError &&
        error.code ===
          'INDEX_DROP_REFUSED'
    );

    assert.equal(
      probe.state.createCalls,
      0
    );

    assert.equal(
      connection.state.disconnectCalls,
      1
    );
  }
);

test(
  'apply fails closed when post-create verification still finds drift',
  async () => {
    const stillMissing = {
      toDrop: [],
      toCreate: [
        [
          {
            value: 1
          },
          {
            name:
              'value_1'
          }
        ]
      ]
    };

    const probe =
      fakeCommandModel({
        diffs: [
          stillMissing,
          stillMissing
        ]
      });

    const plan =
      createIndexPlan([
        probe.model
      ]);

    const connection =
      connectionRecorder();

    await assert.rejects(
      () =>
        executeIndexCommand({
          mode: 'apply',
          models: [
            probe.model
          ],
          env: {
            MONGODB_URI:
              'mongodb://verification.example/merzox',
            [
              INDEX_APPLY_ENV.allow
            ]:
              'true',
            [
              INDEX_APPLY_ENV.planId
            ]:
              plan.planId
          },
          connect:
            connection.connect,
          disconnect:
            connection.disconnect
        }),
      (error) =>
        error instanceof
          IndexManagementError &&
        error.code ===
          'INDEX_APPLY_VERIFICATION_FAILED'
    );

    assert.equal(
      probe.state.createCalls,
      1
    );

    assert.equal(
      connection.state.disconnectCalls,
      1
    );
  }
);
